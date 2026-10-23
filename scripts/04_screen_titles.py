"""Stage 1 screen: title, venue, year, type and language rules.

Reads data/candidates.csv, applies rules, writes
data/screening-log.csv with one row per candidate (stage, decision, reason).
Rows that pass go to stage 2 (title and abstract read, by hand, logged in
the same file by scripts/05_screen_abstracts.py and manual edits).

Rules (in order):
1. seeds are always carried to stage 2
2. year before 2005: exclude (foundational works came in as seeds)
3. type erratum, paratext, letter, editorial, retraction, dataset: exclude
4. language given and not English: exclude (log the language)
5. title has no WASH term: exclude as off topic
6. title has no health outcome term and no design term: exclude
7. title has a design term (review, meta-analysis, pooled, burden, trial,
   cost, additionality, results-based) or a burden or outcome term: stage 2

Run: python3 -I scripts/04_screen_titles.py
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

WASH = re.compile(r"\b(water|sanitation|hygien\w*|hand[- ]?wash\w*|hand[- ]?hygiene|latrine\w*|toilet\w*|wash\b|faec\w*|fec\w*|sludge|chlorin\w*|filt(er|ration)\w*|menstrua\w*|excreta|sewer\w*|open defecation|defecat\w*|drinking|borehole|pit\b|septic|household water treatment|hwts|pou\b|point[- ]of[- ]use|handpump|piped|on-site|onsite)", re.I)
OUTCOME = re.compile(r"(diarrh\w*|helminth\w*|\bsth\b|ascari\w*|trichur\w*|hookworm|respiratory|pneumonia|stunt\w*|linear growth|child growth|mortality|\bdaly|disability[- ]adjusted|enteric|cholera|typhoid|trachoma|schistosom\w*|undernutrition|malnutrition|anaemia|anemia|absente\w*|attendance|environmental enteropathy|enteric dysfunction|infection\w*|disease burden|burden of disease|health outcome\w*|health impact\w*|health effect\w*|child health|morbidity|deaths?)", re.I)
DESIGN = re.compile(r"(systematic review|meta-?analy\w*|meta-?regression|pooled|burden of disease|disease burden|attributable|global burden|cochrane|randomi[sz]ed|cluster[- ]randomi|controlled trial|\btrial\b|cost[- ]benefit|cost[- ]effective\w*|economic (evaluation|return|benefit|impact)|additionality|results[- ]based|outcome[- ]based|impact bond|attribution|comparative risk|umbrella review|scoping review|rapid review|evidence (map|review|synthesis)|evidence gap|modell?ing|simulation|lives saved|counterfactual|impact evaluation|quasi[- ]experimental|difference[- ]in[- ]difference|regression discontinuity|dose[- ]response|exposure[- ]response|risk factor\w*)", re.I)
HIGH_INCOME_HINT = re.compile(r"\b(united states|u\.s\.|usa\b|europe\w*|canada|australia|japan|korea|germany|netherlands|united kingdom|\buk\b|england|france|italy|spain|sweden|norway|finland|denmark|switzerland|new zealand|singapore|hong kong|taiwan|israel)\b", re.I)
EXCLUDE_TYPES = {"erratum", "paratext", "letter", "editorial", "retraction", "dataset", "peer-review", "grant", "libguides", "supplementary-materials"}

FIELDS = ["openalex_id", "doi", "title", "year", "venue", "type", "source", "stage", "decision", "reason", "category", "priority", "screener"]


def main():
    cands = oa.read_csv(oa.ROOT / "data" / "candidates.csv")
    rows = []
    counts = {}
    for c in cands:
        title = c.get("title") or ""
        year = int(c["year"]) if (c.get("year") or "").isdigit() else 0
        src = c.get("source", "")
        stage, decision, reason, category, priority = "1-title", "", "", "", ""
        if "seed" in src.split(";"):
            decision, reason, stage = "stage2", "seed work; carried to abstract screen", "2-abstract"
        elif year and year < 2005:
            decision, reason = "exclude", "published before 2005 and not a seed"
        elif c.get("type") in EXCLUDE_TYPES:
            decision, reason = "exclude", "type %s" % c.get("type")
        elif not title.strip():
            decision, reason = "exclude", "no title in OpenAlex record"
        elif c.get("language") and c["language"] != "en":
            decision, reason = "exclude", "language %s; title not screened" % c["language"]
        elif not WASH.search(title):
            decision, reason = "exclude", "title has no water, sanitation or hygiene term"
        elif not (OUTCOME.search(title) or DESIGN.search(title)):
            decision, reason = "exclude", "title names no health outcome and no review, trial, burden or finance design"
        else:
            d = DESIGN.search(title)
            o = OUTCOME.search(title)
            stage = "2-abstract"
            decision = "stage2"
            if d and o:
                reason = "title names a design (%s) and an outcome (%s)" % (d.group(0).lower(), o.group(0).lower())
                priority = "high"
            elif d:
                reason = "title names a design (%s), outcome unclear" % d.group(0).lower()
                priority = "medium"
            else:
                reason = "title names an outcome (%s) but no design term; likely primary study" % o.group(0).lower()
                priority = "low"
            if HIGH_INCOME_HINT.search(title):
                reason += "; high income place name in title, check"
        rows.append({
            "openalex_id": c["openalex_id"], "doi": c.get("doi", ""), "title": title, "year": c.get("year", ""),
            "venue": c.get("venue", ""), "type": c.get("type", ""), "source": src,
            "stage": stage, "decision": decision, "reason": reason, "category": category, "priority": priority,
            "screener": "rule (04_screen_titles.py)",
        })
        counts[(decision, priority)] = counts.get((decision, priority), 0) + 1
    oa.write_csv(oa.ROOT / "data" / "screening-log.csv", rows, FIELDS)
    for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
        print("%-10s %-8s %6d" % (k[0], k[1], v))
    print("total", len(rows))


if __name__ == "__main__":
    main()
