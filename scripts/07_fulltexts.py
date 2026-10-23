"""Fetch open access full texts for a list of works.

Order of attempts per work:
1. Europe PMC: search by DOI (no email needed), and if the record is open
   access with full text in PMC, download the full text XML and flatten it
   to plain text
2. the OpenAlex best OA location (PDF URL), downloaded with curl and read
   with pdftotext -layout
3. a fallback URL given in the input (for reports)

Never bypasses a paywall. Files go to papers/ (ignored by git):
papers/<openalex_id>.xml, .pdf and .txt. Results are logged to
data/fulltext-log.csv (identifiers and status only).

Usage: python3 -I scripts/07_fulltexts.py <works.csv>
The CSV needs openalex_id, doi, oa_url columns; title and seed_key are
copied into the log when present.
"""

import csv
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

PAPERS = oa.ROOT / "papers"
LOG = oa.ROOT / "data" / "fulltext-log.csv"
EPMC = "https://www.ebi.ac.uk/europepmc/webservices/rest/"


def epmc_lookup(doi):
    q = urllib.parse.quote('DOI:"%s"' % doi)
    url = EPMC + "search?query=%s&format=json&resultType=lite" % q
    data = oa.get_json(url, oa.DATA_RAW / "europepmc" / (re.sub(r"[^A-Za-z0-9]", "_", doi) + ".json"), host_is_openalex=False)
    for r in (data or {}).get("resultList", {}).get("result", []):
        if r.get("pmcid") and r.get("isOpenAccess") == "Y":
            return r["pmcid"], r.get("fullTextIdList", {}).get("fullTextId", [])
        if r.get("pmcid") and r.get("inEPMC") == "Y":
            return r["pmcid"], []
    return None, []


def fetch_bytes(url, out):
    req = urllib.request.Request(url, headers={"User-Agent": oa.USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as r:
        body = r.read()
        ctype = r.headers.get("Content-Type", "")
    out.write_bytes(body)
    return ctype, len(body)


def xml_to_text(xml_path, txt_path):
    xml = xml_path.read_text(errors="replace")
    xml = re.sub(r"<xref[^>]*>.*?</xref>", "", xml, flags=re.S)
    xml = re.sub(r"</(p|sec|title|table-wrap|tr|caption|abstract|fig)>", "\n", xml)
    xml = re.sub(r"</t[dh]>", "\t", xml)
    text = re.sub(r"<[^>]+>", "", xml)
    text = re.sub(r"\n{3,}", "\n\n", text)
    txt_path.write_text(text)
    return len(text.split())


def main():
    src = Path(sys.argv[1])
    works = oa.read_csv(src)
    PAPERS.mkdir(exist_ok=True)
    existing = {}
    if LOG.exists():
        for r in oa.read_csv(LOG):
            existing[r["openalex_id"]] = r
    rows = list(existing.values())
    for w in works:
        oid = w.get("openalex_id") or ""
        if not oid or (oid in existing and existing[oid].get("status") == "ok"):
            continue
        doi = (w.get("doi") or "").strip()
        rec = {"openalex_id": oid, "doi": doi, "seed_key": w.get("seed_key", ""), "title": (w.get("title") or "")[:120], "method": "", "status": "", "path": "", "words": "", "note": ""}
        txt = PAPERS / (oid + ".txt")
        try:
            if doi:
                pmcid, ftids = epmc_lookup(doi)
                if pmcid:
                    url = EPMC + pmcid + "/fullTextXML"
                    xml_path = PAPERS / (oid + ".xml")
                    try:
                        ctype, n = fetch_bytes(url, xml_path)
                        oa._log(url, 200, 0, "europepmc xml %d bytes" % n)
                        if n > 2000 and b"<article" in xml_path.read_bytes()[:5000]:
                            words = xml_to_text(xml_path, txt)
                            rec.update(method="europepmc_xml", status="ok", path=str(txt.relative_to(oa.ROOT)), words=words, note=pmcid)
                        else:
                            rec["note"] = "%s in PMC but no full text XML" % pmcid
                            xml_path.unlink(missing_ok=True)
                    except Exception as e:  # noqa: BLE001
                        oa._log(url, "error", 0, str(e)[:100])
                        rec["note"] = "%s: xml fetch failed %s" % (pmcid, str(e)[:60])
                    time.sleep(0.5)
            if rec["status"] != "ok":
                for url in (w.get("oa_url") or "", w.get("url_fallback") or ""):
                    if not url or not url.startswith("http"):
                        continue
                    pdf = PAPERS / (oid + ".pdf")
                    r = subprocess.run(["curl", "-sL", "--max-time", "120", "-A", oa.USER_AGENT, "-o", str(pdf), "-w", "%{http_code} %{content_type}", url], capture_output=True, text=True)
                    code_type = r.stdout.strip()
                    oa._log(url, code_type.split(" ")[0] if code_type else "error", 0, "pdf download " + code_type)
                    if pdf.exists() and pdf.stat().st_size > 10000 and pdf.read_bytes()[:5] == b"%PDF-":
                        subprocess.run(["pdftotext", "-layout", str(pdf), str(txt)], check=False)
                        words = len(txt.read_text(errors="replace").split()) if txt.exists() else 0
                        if words > 300:
                            rec.update(method="oa_pdf", status="ok", path=str(txt.relative_to(oa.ROOT)), words=words, note=url[:80])
                            break
                        rec["note"] = (rec["note"] + "; " if rec["note"] else "") + "pdf had no text layer"
                    else:
                        if pdf.exists():
                            pdf.unlink()
                        rec["note"] = (rec["note"] + "; " if rec["note"] else "") + "no pdf at %s (%s)" % (url[:60], code_type[:30])
                    time.sleep(1)
            if rec["status"] != "ok":
                rec["status"] = "missing"
        except oa.BudgetStop as e:
            rec.update(status="stopped", note=str(e)[:100])
            rows = [r for r in rows if r["openalex_id"] != oid] + [rec]
            break
        rows = [r for r in rows if r["openalex_id"] != oid] + [rec]
        print("%-13s %-8s %-15s %-6s %s" % (oid, rec["status"], rec["method"], rec["words"], rec["note"][:50]))
    oa.write_csv(LOG, rows, ["openalex_id", "doi", "seed_key", "title", "method", "status", "path", "words", "note"])
    print("ok:", sum(1 for r in rows if r["status"] == "ok"), "missing:", sum(1 for r in rows if r["status"] != "ok"))


if __name__ == "__main__":
    main()
