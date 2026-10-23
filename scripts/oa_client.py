"""Shared OpenAlex and Crossref client for the evidence stage.

Standard library only. Run scripts with `python3 -I`.

Rules implemented here:
- the API key is read from OPENALEX_API_KEY, then <root>/.env, then ~/.Renviron;
  when present it is sent as `api_key=`; the key never reaches logs or files
- no email address goes into any request; plain User-Agent only
- keyless runs pause one second between requests and page with `page=`
- exponential backoff on 429 and 5xx; a 403 or budget error stops the run
- every raw response is saved under data-raw/ (ignored by git)
- every request is appended to queries/request-log.csv without the key
"""

import csv
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_RAW = ROOT / "data-raw"
QUERIES = ROOT / "queries"
LOG = QUERIES / "request-log.csv"
USER_AGENT = "wash-health-impact-tool/0.1 (scratch evidence stage; no contact)"
BASE = "https://api.openalex.org"
MAX_REQUESTS_KEYLESS = 400


class BudgetStop(Exception):
    """Raised when the API answers 403 or reports an exhausted budget."""


def find_key():
    key = os.environ.get("OPENALEX_API_KEY", "").strip()
    if key:
        return key
    for path in (ROOT / ".env", Path.home() / ".Renviron"):
        if path.exists():
            for line in path.read_text().splitlines():
                m = re.match(r"\s*(?:export\s+)?OPENALEX_API_KEY\s*=\s*['\"]?([^'\"\s#]+)", line)
                if m:
                    return m.group(1)
    return ""


API_KEY = find_key()
KEYED = bool(API_KEY)
PAUSE = 0.25 if KEYED else 1.0
_count = {"n": 0}


def _log(url, status, n_results, note=""):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    new = not LOG.exists()
    with LOG.open("a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["timestamp", "script", "url", "status", "n_results", "mode", "note"])
        w.writerow([
            time.strftime("%Y-%m-%dT%H:%M:%S"),
            Path(sys.argv[0]).name if sys.argv and sys.argv[0] else "",
            url,
            status,
            n_results,
            "keyed" if KEYED else "keyless",
            note,
        ])


def get_json(url, raw_path=None, params=None, host_is_openalex=True):
    """GET a JSON document, save it raw, log it, return the parsed object."""
    params = dict(params or {})
    if host_is_openalex and KEYED:
        params["api_key"] = API_KEY
    full = url
    if params:
        full = url + ("&" if "?" in url else "?") + urllib.parse.urlencode(params, safe="|:,()+/")
    public = re.sub(r"([?&])api_key=[^&]*&?", r"\1", full).rstrip("?&")
    if not KEYED and host_is_openalex and _count["n"] >= MAX_REQUESTS_KEYLESS:
        raise BudgetStop("keyless request budget of %d reached" % MAX_REQUESTS_KEYLESS)
    delay = 2.0
    for attempt in range(6):
        req = urllib.request.Request(full, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                body = r.read()
                status = r.status
        except urllib.error.HTTPError as e:
            status = e.code
            body = e.read()
            text = body.decode("utf-8", "replace")[:300]
            if status == 403 or "budget" in text.lower():
                _log(public, status, 0, "stopped: " + text.replace("\n", " "))
                raise BudgetStop("HTTP %d: %s" % (status, text))
            if status == 404:
                _log(public, status, 0, "not found")
                return None
            if status == 429 or status >= 500:
                _log(public, status, 0, "retry in %.0fs" % delay)
                time.sleep(delay)
                delay *= 2
                continue
            _log(public, status, 0, text.replace("\n", " "))
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            _log(public, "error", 0, str(e)[:200])
            time.sleep(delay)
            delay *= 2
            continue
        _count["n"] += 1
        data = json.loads(body)
        if raw_path is not None:
            raw_path = Path(raw_path)
            raw_path.parent.mkdir(parents=True, exist_ok=True)
            raw_path.write_bytes(body)
        n = len(data.get("results", [])) if isinstance(data, dict) and "results" in data else 1
        meta = data.get("meta", {}) if isinstance(data, dict) else {}
        _log(public, status, n, "count=%s" % meta.get("count", "") if meta else "")
        time.sleep(PAUSE)
        return data
    raise RuntimeError("gave up after retries: " + public)


def oa_works(filter_str, select, raw_dir, stem, max_pages=50, per_page=200, extra=None):
    """Page through /works with a filter. Returns the list of results."""
    out = []
    page = 1
    while page <= max_pages:
        params = {"filter": filter_str, "select": select, "per_page": per_page, "page": page}
        if extra:
            params.update(extra)
        data = get_json(BASE + "/works", Path(raw_dir) / ("%s-p%03d.json" % (stem, page)), params)
        if data is None:
            break
        res = data.get("results", [])
        out.extend(res)
        count = data.get("meta", {}).get("count", 0)
        if len(res) < per_page or page * per_page >= count or page * per_page >= 10000:
            break
        page += 1
    return out


def short_id(url_or_id):
    if not url_or_id:
        return ""
    return url_or_id.rsplit("/", 1)[-1]


def venue_of(work):
    loc = work.get("primary_location") or {}
    src = loc.get("source") or {}
    return src.get("display_name") or ""


def oa_of(work):
    oa = work.get("open_access") or {}
    best = work.get("best_oa_location") or {}
    return oa.get("is_oa", False), oa.get("oa_status", ""), (best.get("pdf_url") or best.get("landing_page_url") or oa.get("oa_url") or "")


def first_author(work):
    auths = work.get("authorships") or []
    if not auths:
        return ""
    a = auths[0].get("author") or {}
    return a.get("display_name", "")


def inverted_to_text(inv):
    if not inv:
        return ""
    pos = {}
    for word, idxs in inv.items():
        for i in idxs:
            pos[i] = word
    return " ".join(pos[i] for i in sorted(pos))


def write_csv(path, rows, fields):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)


def read_csv(path):
    with Path(path).open(newline="") as f:
        return list(csv.DictReader(f))


def requests_made():
    return _count["n"]
