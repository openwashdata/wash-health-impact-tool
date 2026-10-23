"""Merge the manual stage 2 decisions into data/screening-log.csv and build
data/included-works.csv (works to carry into extraction and full text fetch).

Rules:
- rows with a manual decision in queries/stage2-decisions.csv take it
- remaining stage 2 rows with priority low (title named an outcome but no
  review, trial, burden or finance design) are excluded by rule as primary
  observational, laboratory, technology or out of scope studies
- remaining high or medium rows without a decision are flagged "undecided"

Run: python3 -I scripts/05b_apply_stage2.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

log = oa.read_csv(oa.ROOT / "data" / "screening-log.csv")
dec = {r["openalex_id"]: r for r in oa.read_csv(oa.QUERIES / "stage2-decisions.csv")}
cands = {r["openalex_id"]: r for r in oa.read_csv(oa.ROOT / "data" / "candidates.csv")}
counts = {}
undecided = []
for r in log:
    if r["decision"] != "stage2":
        continue
    d = dec.get(r["openalex_id"])
    if d:
        r["decision"], r["category"], r["reason"] = d["decision"], d["category"], d["reason"]
        r["screener"] = "manual abstract screen"
    elif r.get("priority") == "low":
        r["decision"], r["category"] = "exclude", ""
        r["reason"] = "title screen: primary observational, laboratory, technology or out of scope study; no pooled relevance"
        r["screener"] = "rule (05b_apply_stage2.py)"
    else:
        r["decision"] = "undecided"
        undecided.append(r["openalex_id"])
    r["stage"] = "2-abstract"
    counts[(r["decision"], r["category"])] = counts.get((r["decision"], r["category"]), 0) + 1
oa.write_csv(oa.ROOT / "data" / "screening-log.csv", log, ["openalex_id", "doi", "title", "year", "venue", "type", "source", "stage", "decision", "reason", "category", "priority", "screener"])
inc = []
for r in log:
    if r["decision"] in ("include", "mapped"):
        c = cands.get(r["openalex_id"], {})
        inc.append({**{k: c.get(k, "") for k in ("openalex_id", "doi", "title", "year", "venue", "type", "first_author", "is_oa", "oa_status", "oa_url", "cited_by_count", "source")}, "decision": r["decision"], "category": r["category"], "reason": r["reason"]})
inc.sort(key=lambda x: (x["decision"], x["category"], -int(x["year"] or 0)))
oa.write_csv(oa.ROOT / "data" / "included-works.csv", inc, ["openalex_id", "doi", "title", "year", "venue", "type", "first_author", "is_oa", "oa_status", "oa_url", "cited_by_count", "source", "decision", "category", "reason"])
for k, v in sorted(counts.items(), key=lambda kv: (kv[0][0], -kv[1])):
    print("%-10s %-16s %5d" % (k[0], k[1], v))
print("stage 2 total:", sum(counts.values()), "| included:", sum(1 for x in inc if x["decision"] == "include"), "| mapped:", sum(1 for x in inc if x["decision"] == "mapped"), "| undecided:", len(undecided), undecided[:10])
