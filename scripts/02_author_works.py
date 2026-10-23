"""Author pass: resolve 13 WASH and health researchers in OpenAlex and pull
their WASH and health works from 2010 on.

Output: data/authors.csv (the profile chosen per person, with the reason)
        data/author-works.csv (one row per work, identifiers and metadata only)
Raw:    data-raw/openalex/authors/

Run: python3 -I scripts/02_author_works.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

RAW = oa.DATA_RAW / "openalex" / "authors"
WORK_SELECT = ",".join([
    "id", "doi", "title", "publication_year", "type", "open_access", "best_oa_location",
    "primary_location", "cited_by_count", "authorships",
])
AUTHOR_SELECT = "id,display_name,works_count,cited_by_count,last_known_institutions,affiliations,topics,orcid"
# title and abstract search used to keep the author pull on topic
TOPIC_SEARCH = 'diarrhoea OR diarrhea OR sanitation OR "drinking water" OR handwashing OR "hand washing" OR helminth OR hygiene OR latrine OR "water quality" OR "water supply"'

PEOPLE = [
    ("Jennyfer Wolf", "World Health Organization"),
    ("Annette Prüss-Ustün", "World Health Organization"),
    ("Thomas Clasen", "Emory"),
    ("Oliver Cumming", "London School of Hygiene"),
    ("Matthew C. Freeman", "Emory"),
    ("Jamie Bartram", "North Carolina|Leeds"),
    ("Richard Johnston", "World Health Organization"),
    ("Guy Hutton", "UNICEF|World Bank|World Health Organization"),
    ("Joe Brown", "North Carolina|Georgia"),
    ("Amy J. Pickering", "Berkeley|Tufts|Stanford"),
    ("Stephen P. Luby", "Stanford|icddr"),
    ("Sandy Cairncross", "London School of Hygiene"),
    ("Sara Marks", "Eawag|aquatic"),
]


def inst_names(a):
    names = []
    for i in a.get("last_known_institutions") or []:
        names.append(i.get("display_name", ""))
    for i in a.get("affiliations") or []:
        inst = i.get("institution") or {}
        names.append(inst.get("display_name", ""))
    return "; ".join(dict.fromkeys(n for n in names if n))


def topic_names(a):
    return "; ".join((t.get("display_name") or "") for t in (a.get("topics") or [])[:5])


def pick(cands, hint):
    """Prefer a profile whose affiliations match the hint and whose topics are WASH; else most cited."""
    import re
    best, best_score = None, -1
    for a in cands:
        inst = inst_names(a)
        topics = topic_names(a)
        score = 0
        if re.search(hint, inst, re.I):
            score += 10
        if re.search(r"water|sanitation|hygiene|diarrh|helminth|environmental health|global health", topics, re.I):
            score += 5
        score += min(a.get("works_count", 0), 300) / 300.0
        if score > best_score:
            best, best_score = a, score
    return best


def main():
    authors_rows, work_rows = [], []
    for name, hint in PEOPLE:
        stem = name.lower().replace(" ", "-").replace(".", "")
        data = oa.get_json(oa.BASE + "/authors", RAW / ("%s-lookup.json" % stem), {"search": name, "select": AUTHOR_SELECT, "per_page": 10})
        cands = (data or {}).get("results", [])
        chosen = pick(cands, hint)
        if chosen is None:
            authors_rows.append({"person": name, "note": "no profile found"})
            print("NO PROFILE", name)
            continue
        aid = oa.short_id(chosen["id"])
        authors_rows.append({
            "person": name,
            "openalex_author_id": aid,
            "display_name": chosen.get("display_name"),
            "orcid": chosen.get("orcid") or "",
            "works_count": chosen.get("works_count"),
            "cited_by_count": chosen.get("cited_by_count"),
            "institutions": inst_names(chosen),
            "top_topics": topic_names(chosen),
            "n_candidates": len(cands),
            "note": "picked by affiliation hint '%s' and WASH topics" % hint,
        })
        works = oa.oa_works(
            "authorships.author.id:%s,publication_year:>2009,type:article|review" % aid,
            WORK_SELECT, RAW, stem + "-works", max_pages=10,
            extra={"search": TOPIC_SEARCH},
        )
        for w in works:
            is_oa, oa_status, oa_url = oa.oa_of(w)
            work_rows.append({
                "person": name,
                "openalex_author_id": aid,
                "openalex_id": oa.short_id(w["id"]),
                "doi": (w.get("doi") or "").replace("https://doi.org/", ""),
                "title": w.get("title") or "",
                "year": w.get("publication_year"),
                "venue": oa.venue_of(w),
                "type": w.get("type"),
                "first_author": oa.first_author(w),
                "is_oa": is_oa,
                "oa_status": oa_status,
                "oa_url": oa_url,
                "cited_by_count": w.get("cited_by_count"),
            })
        print("%-22s %-12s works on topic since 2010: %d" % (name, aid, len(works)))
    oa.write_csv(oa.ROOT / "data" / "authors.csv", authors_rows, ["person", "openalex_author_id", "display_name", "orcid", "works_count", "cited_by_count", "institutions", "top_topics", "n_candidates", "note"])
    oa.write_csv(oa.ROOT / "data" / "author-works.csv", work_rows, ["person", "openalex_author_id", "openalex_id", "doi", "title", "year", "venue", "type", "first_author", "is_oa", "oa_status", "oa_url", "cited_by_count"])
    print("author works rows:", len(work_rows), "unique works:", len({r["openalex_id"] for r in work_rows}))
    print("requests made:", oa.requests_made(), "mode:", "keyed" if oa.KEYED else "keyless")


if __name__ == "__main__":
    main()
