"""Build data/references.bib for every included and mapped work from OpenAlex
metadata (authors, title, venue, year, volume, issue, pages, DOI), for a
later Zotero import. No Zotero writes. Raw responses to data-raw/openalex/bib/.

Run: python3 -I scripts/08_references_bib.py
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

RAW = oa.DATA_RAW / "openalex" / "bib"
SELECT = "id,doi,title,publication_year,type,authorships,primary_location,biblio,open_access"
TYPE_MAP = {"article": "article", "review": "article", "report": "techreport", "book-chapter": "incollection", "book": "book", "dissertation": "phdthesis", "preprint": "misc", "paratext": "misc", "other": "misc", "erratum": "article", "letter": "article", "editorial": "article"}


def bib_escape(s):
    return (s or "").replace("&", "\\&").replace("%", "\\%").replace("#", "\\#").replace("_", "\\_")


def key_of(w, used):
    first = (w.get("authorships") or [{}])[0].get("author", {}).get("display_name", "anon")
    surname = re.sub(r"[^a-z]", "", first.split()[-1].lower()) if first else "anon"
    base = "%s%s" % (surname or "anon", w.get("publication_year") or "")
    k, i = base, 1
    while k in used:
        k = "%s%s" % (base, "abcdefghijklmnopqrstuvwxyz"[i % 26])
        i += 1
    used.add(k)
    return k


def main():
    inc = oa.read_csv(oa.ROOT / "data" / "included-works.csv")
    seeds = oa.read_csv(oa.ROOT / "data" / "seed-works.csv")
    ids = []
    cat = {}
    for r in inc:
        ids.append(r["openalex_id"])
        cat[r["openalex_id"]] = "%s/%s" % (r["decision"], r["category"])
    for s in seeds:
        if s.get("openalex_id") and s["openalex_id"] not in cat:
            ids.append(s["openalex_id"])
            cat[s["openalex_id"]] = "seed/" + s.get("role", "")
    works = []
    for b in range(0, len(ids), 50):
        batch = ids[b:b + 50]
        works.extend(oa.oa_works("openalex_id:" + "|".join(batch), SELECT, RAW, "bib-b%03d" % (b // 50), max_pages=1, per_page=50))
    used = set()
    out = ["% references for the wash-health-impact-tool evidence stage; built from OpenAlex metadata by scripts/08_references_bib.py; no abstracts\n"]
    works.sort(key=lambda w: (-(w.get("publication_year") or 0), w.get("title") or ""))
    for w in works:
        oid = oa.short_id(w["id"])
        authors = " and ".join(a.get("author", {}).get("display_name", "") for a in (w.get("authorships") or []) if a.get("author", {}).get("display_name"))
        loc = w.get("primary_location") or {}
        src = loc.get("source") or {}
        bib = w.get("biblio") or {}
        etype = TYPE_MAP.get(w.get("type"), "misc")
        fields = [
            ("author", bib_escape(authors)),
            ("title", "{%s}" % bib_escape(w.get("title") or "")),
            ("year", str(w.get("publication_year") or "")),
            ("journal" if etype == "article" else "publisher", bib_escape(src.get("display_name") or "")),
            ("volume", bib.get("volume") or ""),
            ("number", bib.get("issue") or ""),
            ("pages", ("%s--%s" % (bib["first_page"], bib["last_page"])) if bib.get("first_page") and bib.get("last_page") and bib["first_page"] != bib["last_page"] else (bib.get("first_page") or "")),
            ("doi", (w.get("doi") or "").replace("https://doi.org/", "")),
            ("url", (w.get("doi") or loc.get("landing_page_url") or w["id"])),
            ("note", "OpenAlex %s; screening %s" % (oid, cat.get(oid, ""))),
            ("keywords", "wash-health-impact-tool; " + cat.get(oid, "").replace("/", "-")),
        ]
        body = ",\n".join("  %s = {%s}" % (k, v) for k, v in fields if v)
        out.append("@%s{%s,\n%s\n}\n" % (etype, key_of(w, used), body))
    (oa.ROOT / "data" / "references.bib").write_text("\n".join(out))
    print("entries:", len(works), "of", len(ids), "ids; requests:", oa.requests_made())


if __name__ == "__main__":
    main()
