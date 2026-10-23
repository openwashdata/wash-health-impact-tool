"""Stage 2 preparation: collect abstracts for the works that passed the title
screen and write a reading file for the manual abstract screen.

- abstracts come from the raw cited-by and reference responses under data-raw/
- works without a stored abstract (seeds, author works) are fetched in
  batches of 50 by OpenAlex ID, raw to data-raw/openalex/abstracts/
- the reading file goes to data-raw/screening/stage2-reading.txt (ignored by
  git; abstracts never enter tracked files)

The manual decisions are written to queries/stage2-decisions.csv
(openalex_id, decision, category, reason) and merged into
data/screening-log.csv by scripts/05b_apply_stage2.py.

Run: python3 -I scripts/05_stage2_prepare.py
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

RAW_ABS = oa.DATA_RAW / "openalex" / "abstracts"
OUT = oa.DATA_RAW / "screening" / "stage2-reading.txt"


def collect_abstracts():
    abstracts = {}
    for sub in ("cited-by", "references", "abstracts"):
        d = oa.DATA_RAW / "openalex" / sub
        if not d.exists():
            continue
        for f in sorted(d.glob("*.json")):
            try:
                data = json.loads(f.read_text())
            except json.JSONDecodeError:
                continue
            for w in data.get("results", []):
                inv = w.get("abstract_inverted_index")
                if inv:
                    abstracts[oa.short_id(w["id"])] = oa.inverted_to_text(inv)
    return abstracts


def main():
    log = oa.read_csv(oa.ROOT / "data" / "screening-log.csv")
    stage2 = [r for r in log if r["decision"] == "stage2"]
    abstracts = collect_abstracts()
    missing = [r["openalex_id"] for r in stage2 if r["openalex_id"] not in abstracts]
    print("stage 2 works:", len(stage2), "abstracts stored:", sum(1 for r in stage2 if r["openalex_id"] in abstracts), "missing:", len(missing))
    for b in range(0, len(missing), 50):
        batch = missing[b:b + 50]
        got = oa.oa_works("openalex_id:" + "|".join(batch), "id,abstract_inverted_index", RAW_ABS, "missing-b%03d" % (b // 50), max_pages=1, per_page=50)
        for w in got:
            inv = w.get("abstract_inverted_index")
            if inv:
                abstracts[oa.short_id(w["id"])] = oa.inverted_to_text(inv)
    still = [r["openalex_id"] for r in stage2 if r["openalex_id"] not in abstracts]
    print("abstracts still missing after fetch:", len(still))
    order = {"": 0, "high": 1, "medium": 2, "low": 3}
    stage2.sort(key=lambda r: (order.get(r.get("priority", ""), 9), -int(r["year"] or 0)))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    # file A: seeds, high and medium priority with abstracts; file B: low priority, titles only
    with OUT.open("w") as f, OUT.with_name("stage2-reading-low.txt").open("w") as g:
        for r in stage2:
            if r.get("priority") == "low":
                g.write("%s|%s|%s|%s|%s\n" % (r["openalex_id"], r["year"], r["type"][:7], r["venue"][:28], r["title"][:150]))
                continue
            a = abstracts.get(r["openalex_id"], "")
            a = " ".join(a.split())[:650]
            f.write("%s|%s|%s|%s|%s\nT: %s\nA: %s\n" % (r["openalex_id"], r["priority"] or "seed", r["year"], r["type"][:7], r["venue"][:40], r["title"][:200], a or "(no abstract)"))
    print("reading file:", OUT, "requests made:", oa.requests_made())


if __name__ == "__main__":
    main()
