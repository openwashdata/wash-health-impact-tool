"""Citation chaining and the candidate union.

For every seed with chain = yes (verified meta-analyses and burden papers):
- works citing it (filter cites:ID), 2005 on
- its references (referenced_works, fetched in batches of 50 by openalex_id), 2005 on

Then the union of seeds, author works, cited_by and references goes to
data/candidates.csv, deduplicated on OpenAlex ID, with a `source` column that
lists every route a work came in by (seed, author, cited_by, reference) and a
`chained_from` column with the seed keys.

Raw:    data-raw/openalex/cited-by/<seed_key>-p001.json ...
        data-raw/openalex/references/<seed_key>-b01.json ...
Run: python3 -I scripts/03_citation_chain.py
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

RAW_CB = oa.DATA_RAW / "openalex" / "cited-by"
RAW_REF = oa.DATA_RAW / "openalex" / "references"
RAW_SEEDS = oa.DATA_RAW / "openalex" / "seeds"
SELECT = ",".join([
    "id", "doi", "title", "publication_year", "type", "open_access", "best_oa_location",
    "primary_location", "cited_by_count", "authorships", "abstract_inverted_index", "language",
])
FIELDS = ["openalex_id", "doi", "title", "year", "venue", "type", "first_author", "language", "is_oa", "oa_status", "oa_url", "cited_by_count", "source", "chained_from", "has_abstract"]


def row_of(w):
    is_oa, oa_status, oa_url = oa.oa_of(w)
    return {
        "openalex_id": oa.short_id(w["id"]),
        "doi": (w.get("doi") or "").replace("https://doi.org/", ""),
        "title": (w.get("title") or "").replace("\n", " ").strip(),
        "year": w.get("publication_year"),
        "venue": oa.venue_of(w),
        "type": w.get("type"),
        "first_author": oa.first_author(w),
        "language": w.get("language") or "",
        "is_oa": is_oa,
        "oa_status": oa_status,
        "oa_url": oa_url,
        "cited_by_count": w.get("cited_by_count"),
        "has_abstract": bool(w.get("abstract_inverted_index")),
    }


def main():
    seeds = oa.read_csv(oa.ROOT / "data" / "seed-works.csv")
    chain_seeds = [s for s in seeds if s.get("chain") == "yes" and s.get("openalex_id")]
    union = {}  # openalex_id -> row
    sources = {}  # openalex_id -> set of sources
    chained = {}  # openalex_id -> set of seed keys

    def add(w_row, source, seed_key=""):
        oid = w_row["openalex_id"]
        if oid not in union:
            union[oid] = w_row
        sources.setdefault(oid, set()).add(source)
        if seed_key:
            chained.setdefault(oid, set()).add(seed_key)

    # seeds themselves
    for s in seeds:
        if s.get("openalex_id"):
            add({k: s.get(k, "") for k in FIELDS if k in s} | {"openalex_id": s["openalex_id"], "language": "", "has_abstract": ""}, "seed", s["seed_key"])
    # author works
    for a in oa.read_csv(oa.ROOT / "data" / "author-works.csv"):
        add({k: a.get(k, "") for k in FIELDS if k in a} | {"language": "", "has_abstract": ""}, "author")

    counts = {}
    for s in chain_seeds:
        key, oid = s["seed_key"], s["openalex_id"]
        # citing works
        citing = oa.oa_works("cites:%s,publication_year:>2004" % oid, SELECT, RAW_CB, key, max_pages=25)
        for w in citing:
            add(row_of(w), "cited_by", key)
        # references: read the seed's own record for referenced_works
        seed_rec = oa.get_json(oa.BASE + "/works/" + oid, RAW_SEEDS / (key + "-full.json"), {"select": "id,referenced_works"})
        refs = [oa.short_id(r) for r in (seed_rec or {}).get("referenced_works", [])]
        nref = 0
        for b in range(0, len(refs), 50):
            batch = refs[b:b + 50]
            got = oa.oa_works("openalex_id:%s,publication_year:>2004" % "|".join(batch), SELECT, RAW_REF, "%s-b%02d" % (key, b // 50), max_pages=1, per_page=50)
            for w in got:
                add(row_of(w), "reference", key)
                nref += 1
        counts[key] = (len(citing), len(refs), nref)
        print("%-16s citing: %5d   references: %4d (%d from 2005 on)" % (key, len(citing), len(refs), nref))

    rows = []
    for oid, r in union.items():
        r = dict(r)
        r["source"] = ";".join(sorted(sources[oid]))
        r["chained_from"] = ";".join(sorted(chained.get(oid, [])))
        rows.append(r)
    rows.sort(key=lambda r: (-int(r.get("cited_by_count") or 0), r["openalex_id"]))
    oa.write_csv(oa.ROOT / "data" / "candidates.csv", rows, FIELDS)
    summary = {
        "n_candidates": len(rows),
        "by_source": {s: sum(1 for r in rows if s in r["source"].split(";")) for s in ("seed", "author", "cited_by", "reference")},
        "per_seed": {k: {"citing": v[0], "references_total": v[1], "references_2005_on": v[2]} for k, v in counts.items()},
        "requests_this_run": oa.requests_made(),
        "mode": "keyed" if oa.KEYED else "keyless",
    }
    (oa.QUERIES / "03-citation-chain-summary.json").write_text(json.dumps(summary, indent=1))
    print(json.dumps(summary["by_source"]), "candidates:", len(rows))
    print("requests made:", oa.requests_made(), "mode:", summary["mode"])


if __name__ == "__main__":
    main()
