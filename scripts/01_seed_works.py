"""Verify the seed candidates against OpenAlex and write data/seed-works.csv.

Input:  queries/seed-candidates.csv (my recollection of DOIs and titles)
Output: data/seed-works.csv (what OpenAlex says; OpenAlex wins)
Raw:    data-raw/openalex/seeds/<seed_key>.json

Run: python3 -I scripts/01_seed_works.py
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

SELECT = ",".join([
    "id", "doi", "title", "publication_year", "type", "open_access", "best_oa_location",
    "primary_location", "cited_by_count", "authorships", "referenced_works_count",
])
RAW = oa.DATA_RAW / "openalex" / "seeds"


def norm(s):
    return re.sub(r"[^a-z0-9 ]", "", (s or "").lower())


def token_overlap(a, b):
    ta, tb = set(norm(a).split()), set(norm(b).split())
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta)


def pick_by_title(seed):
    params = {"search": seed["title_query"], "select": SELECT, "per_page": 5}
    if seed["role"] == "erratum":
        params["filter"] = "type:erratum"
    data = oa.get_json(oa.BASE + "/works", RAW / (seed["seed_key"] + "-search.json"), params)
    best, score = None, 0.0
    for w in (data or {}).get("results", []):
        s = token_overlap(seed["title_query"], w.get("title") or "")
        if s > score:
            best, score = w, s
    return best, score


def main():
    seeds = oa.read_csv(oa.QUERIES / "seed-candidates.csv")
    rows = []
    for seed in seeds:
        work, method, note = None, "", ""
        if seed["doi_guess"]:
            work = oa.get_json(oa.BASE + "/works/doi:" + seed["doi_guess"], RAW / (seed["seed_key"] + ".json"), {"select": SELECT})
            if work is not None:
                method = "doi"
                if token_overlap(seed["title_query"], work.get("title") or "") < 0.5:
                    note = "doi resolved but title differs from my recollection; check"
            else:
                note = "doi guess not in OpenAlex; fell back to title search"
        if work is None:
            work, score = pick_by_title(seed)
            method = "title search (overlap %.2f)" % score
            if work is not None:
                (RAW / (seed["seed_key"] + ".json")).write_text(__import__("json").dumps(work, indent=1))
            if work is None or score < 0.5:
                note = (note + "; " if note else "") + "no confident match"
        # a title search that lands on a work already claimed by another seed means the
        # document itself (for example a WHO report) is not in OpenAlex
        if work is not None and not seed["doi_guess"] and any(r.get("openalex_id") == oa.short_id(work["id"]) for r in rows):
            note = "title search returned %s, already matched by another seed; this document is not in OpenAlex" % oa.short_id(work["id"])
            work = None
        if work is None:
            rows.append({"seed_key": seed["seed_key"], "author_year": seed["author_year"], "title": seed["title_query"], "oa_url": seed.get("url_fallback", ""), "role": seed["role"], "chain": "no", "match_method": method, "match_note": note or "not found in OpenAlex"})
            print("NOT FOUND", seed["seed_key"], "|", note)
            continue
        is_oa, oa_status, oa_url = oa.oa_of(work)
        title = work.get("title") or ""
        is_review = bool(re.search(r"systematic review|meta-analys|meta-regression|cochrane|pooled", title, re.I)) or seed["role"] in ("meta-analysis",)
        rows.append({
            "seed_key": seed["seed_key"],
            "author_year": seed["author_year"],
            "openalex_id": oa.short_id(work["id"]),
            "doi": (work.get("doi") or "").replace("https://doi.org/", ""),
            "title": title,
            "year": work.get("publication_year"),
            "venue": oa.venue_of(work),
            "type": work.get("type"),
            "first_author": oa.first_author(work),
            "is_oa": is_oa,
            "oa_status": oa_status,
            "oa_url": oa_url,
            "cited_by_count": work.get("cited_by_count"),
            "n_references": work.get("referenced_works_count"),
            "is_systematic_review_or_ma": is_review,
            "role": seed["role"],
            "chain": seed["chain"],
            "match_method": method,
            "match_note": note,
        })
        print("%-16s %-12s %s %s" % (seed["seed_key"], oa.short_id(work["id"]), work.get("publication_year"), title[:70]))
    fields = ["seed_key", "author_year", "openalex_id", "doi", "title", "year", "venue", "type", "first_author", "is_oa", "oa_status", "oa_url", "cited_by_count", "n_references", "is_systematic_review_or_ma", "role", "chain", "match_method", "match_note"]
    oa.write_csv(oa.ROOT / "data" / "seed-works.csv", rows, fields)
    print("requests made:", oa.requests_made(), "mode:", "keyed" if oa.KEYED else "keyless")


if __name__ == "__main__":
    main()
