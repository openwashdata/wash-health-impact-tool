# Stage 4 report: write-up and demo kit

Scratch reproduction of the Aqua for All assignment "Developing a water and sanitation - health impact estimation tool for outcome-based finance". Stage 4 was built on 2026-10-23 by an agent for Lars Schöbitz on top of stages 1 to 3. Nothing here has been reviewed by a person. Local repository on branch `dev`, no remote; nothing was published or sent. Network use in this stage: three read-only HEAD requests to doi.org to confirm the DOIs of hand-typed references; no email address in any request.

The situation this stage was built for: Lars will not bid. His professor's verdict is that the three evidence questions in the terms of reference are a research programme, not a five-month consultancy; the scratch build tested that verdict. On Monday 26 October Lars shows her the tool. A possible next step is to publish the repository (CC BY 4.0 for tables and documents, MIT for code) and to write to Aqua for All and to Rick Johnston. Stage 4 prepares all of that and decides nothing.

## 1. What exists

| Deliverable | Location | State |
| --- | --- | --- |
| Evidence review | `docs/evidence-review.qmd` | renders to HTML (4.1 MB, self-contained): question and scope, search strategy with counts, a Mermaid flow computed from `data/candidates.csv` and `data/screening-log.csv`, effect size and factor tables from the CSV files, service levels and baseline conditions, the two mortality routes, STH, mapped outcomes, MHH, the landscape tables, the data gaps per country, limitations, 69 cited works with a reference list from `data/references.bib` plus `docs/references-extra.bib` |
| Supplementary references | `docs/references-extra.bib` | four hand-typed entries that the OpenAlex-built bib does not hold (WHO 2023 report, Lamberti 2012, Fischer Walker 2012, Zhang and Yu 1998); DOIs confirmed |
| User guide | `docs/user-guide.qmd` | renders to HTML (1.3 MB): install, the template column by column (from `transaction_columns()`), the output types, ex-post and ex-ante runs, reading a result on the KWSH case with the label, flags, notes and ledger computed by the package, the flag dictionary, portfolio sums, the report, exports and factor cards, the app, update rules, what the tool does not do |
| Demo script | `docs/demo-script.md` | ten-minute walk-through: tabs to open, the app inputs for KWSH and Aqua Clara, the three points, the four questions, the commands, the fallbacks, what not to say |
| Pre-publication checklist | `docs/publication-checklist.md` | decisions, row review (linked to the governance checklist), licence checks per source, names and contacts, citation file, public README, excluded folders, Zotero import, pkgdown, repository name and organisation with the trade-off, the push |
| Citation file | `CITATION.cff` | draft with Lars as author, agent assistance stated in the abstract, placeholders for affiliation, ORCID, URL and release date; not yet validated |
| Public README | `README-public.md` | draft for a public audience, honest about how the repository was made and what is unreviewed; replaces `README.md` on publication after the placeholders are filled |
| Email drafts | `docs/draft-email-aqua-for-all.md` | one to ILF@aquaforall.org with Rick Johnston in copy, one shorter reply to the LinkedIn post; no proposal, the two-sentence finding, the offer; affiliation placeholders |
| One-page summary for Aqua for All | `docs/one-page-summary.qmd` | typst, A4, one page (checked with pdfinfo: 1 page, 595 x 842 pt); evidence table and the two examples computed from the package; contact and repository placeholders; the PDF is ignored by git |
| pkgdown site | `pkg/docs/` (ignored) | built locally with pkgdown 2.2.0, exit 0, no warnings, 492 KB, 34 reference pages plus home, news and licence pages; no `_pkgdown.yml` yet |
| This report and the README | `docs/stage4-report.md`, `README.md` | layout and stages updated |

## 2. Render results

- `quarto render docs/evidence-review.qmd`: clean. The Mermaid flow is emitted from an R chunk (`results='asis'`) so that every count comes from the data files; Quarto renders it client-side (`mermaid-js`). All 69 citation keys resolve (checked by script against both bib files); no `???` in the output.
- `quarto render docs/user-guide.qmd`: clean; the KWSH tables are live package output (272 cases, 0 to 519, very low; ledger of 12 rows).
- `quarto render docs/one-page-summary.qmd`: clean after two fixes. Quarto's typst format opens an SVG graphics device even for a document without figures, and this R cannot load cairo, so the format sets `fig-format: png`; and people reached is printed with `format_number()` because typst rendered R's scientific notation as a superscript. `pdfinfo`: 1 page, A4.
- pkgdown: `pkgdown::build_site("pkg")` in a separate process, exit 0, "Checking for problems" found none. The site runs the examples; the two `\dontrun{}` examples (app, report) are skipped as intended.
- The three stage 2 documents and the four stage 3 example reports were not re-rendered; nothing they depend on changed.
- Tests and check were not re-run; no package file changed in this stage.

## 3. What is left for a person to do

Before Monday:

1. Read the demo script and open the four tabs it names; render the KWSH report into `docs/reports/` if the folder is empty (the one-line R command is in the script).
2. Read the one-pager written for Liz next to the neutral one-pager (`docs/one-page-summary.pdf`); the first is the anchor for the meeting, the second is the one that could go to Aqua for All.

Decisions for Monday (the demo script's four questions): publish or keep private; whose name and whether an affiliation appears; who reviews the factor rows and samples the abstract decisions; write to Aqua for All and Rick Johnston or not. Then the repository home (openwashdata, Global-Health-Engineering or a personal account; the trade-off is in the checklist) and whether the pkgdown site goes up.

If the answer is publish, the checklist in `docs/publication-checklist.md` has the work: the row review (24 effect, 20 adjustment and 13 pathway rows; the build scripts of the two rebuilt tables; a sample of the 1 626 abstract decisions), the licence checks, the placeholders in `CITATION.cff`, `README-public.md`, the one-pager and the emails, the licence file layout for GitHub, a `_pkgdown.yml`, the Zotero import after the human screen, and the push. Only then the emails.

Open questions carried from stage 3 and not closed here: STH baselines, a valuation step, real transaction data in place of the illustrative counts, the platform recommendation (the user guide says: Airtable or mWater import results and factor cards; the label logic, the deaths and DALYs route and the ledger stay in R), and the update rhythm and roles.

## 4. Final state of the repository

At the commit of this report:

- Commits on `dev`: 25 (20 from stages 1 to 3, 5 in stage 4).
- Tracked files: 134 (data 19, docs 15, pkg 74, scripts 16, queries 4, root 6).
- Ignored folders: `data-raw/` 192 MB (raw API responses, abstracts, landscape PDFs), `papers/` 53 MB (full texts), `docs/reports/` 4.7 MB (four rendered example reports), `pkg/docs/` 492 KB (pkgdown site), rendered `docs/*.html` 12 MB in total (five documents), `docs/one-page-summary.pdf` 48 KB, `docs/.quarto/` 12 KB.
- Working tree clean; no app, Quarto or R process left running.

Commits in this stage: `968b6a2` (evidence review), `8315e27` (user guide), `3e1f767` (demo script, checklist, citation file, public README, email drafts, one-pager, ignore rules), `287824d` (one-pager fixes), plus the commit of this report and the README update.
