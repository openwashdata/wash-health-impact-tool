# Pre-publication checklist

Everything that has to happen before this repository could go public. Drafted on 2026-10-23 by an agent for Lars Schöbitz as part of stage 4; nothing on this list has been done unless the item says so. The checklist assumes the decisions of the Monday meeting (`docs/demo-script.md`): publish, whose name, who reviews, whether to write to Aqua for All.

## 1. Decisions that come first

- [ ] Publish at all (Liz's agreement).
- [ ] Whose name goes on the repository, the package and the citation file (Lars alone; Lars with an affiliation; the group).
- [ ] Whether ETH Zurich or Global Health Engineering is named anywhere. The drafts name no institution as endorsing the work; the affiliation placeholders are in `CITATION.cff`, `README-public.md` and `docs/draft-email-aqua-for-all.md`.
- [ ] Who takes the reviewer role of the governance document (section 3: a second person with water, sanitation and health evidence experience).
- [ ] Repository name and organisation (section 10 below).

## 2. Human review of every factor row

The governance document (`docs/factor-table-governance.md`, section 5) has the checklist a reviewer applies to one curated row. Before publication every current row of the three curated tables needs it:

- [ ] `data/factors/effects.csv`: 24 rows. For each: open the DOI, find the value at the locator, confirm the interval, the study count and the GRADE rating, confirm the use rule matches the code (`pkg/R/estimate.R`, `select_effect()`).
- [ ] `data/factors/adjustments.csv`: 20 rows. The judgement calls are the ones to argue about: the use references (chlorination 0.62, filtration 0.90), the decay 0.62, the coverage threshold 0.50, the episode duration 4.3 days, the U5MR-to-rate factor 0.2, the three PAF counterfactual relative risks.
- [ ] `data/factors/pathways.csv`: 13 rows. Check that each proxy (kiosks, in-line chlorination, container-based sanitation) is flagged and that the reach-only pathways refuse to estimate.
- [ ] The two rebuilt tables (`baseline-disease.csv`, `baseline-exposure.csv`): review the build script `scripts/10_build_baseline_tables.R` and the pull script `scripts/09_stage2_baselines.py` rather than the rows; spot-check five values against the WHO GHO and DHS pages.
- [ ] `data/effect-sizes.csv` (77 rows): at least the 24 rows that feed the factor table (the `effect_id` column of `effects.csv` says which), and a sample of the rest.
- [ ] A sample of the abstract screen: the stage 3 report asks who samples the 1 626 decisions and how many. Suggestion: 100 at random from `data/screening-log.csv` where `stage == "2-abstract"`, stratified by decision; record disagreements in a file next to the log.
- [ ] Record the review: add a `reviewed_by` and `reviewed_on` note per row in `data/factors/CHANGELOG.md` (one entry for the batch is enough), and add the reviewer's name to the changelog entries that say "Reviewer: none".
- [ ] After the review, rebuild the package copy (`Rscript pkg/data-raw/factors.R`), reinstall, run `devtools::test("pkg")` and `devtools::check("pkg")`, re-render the four Quarto documents and the worked examples, and state the differences in the changelog.

## 3. Licence and redistribution checks

- [ ] **WHO country workbook.** The method is re-implemented from the published description (`docs/methodology.qmd`, step 5); the workbook itself is not in the repository. Verify: `git ls-files | grep -i -E 'xlsx|who'` returns no WHO file. The landscape PDFs and the workbook downloaded for the mapping are in `data-raw/` (ignored).
- [ ] **WHO 2023 burden report** (CC BY-NC-SA 3.0 IGO). Values are cited with the report as source; the PDF stays in `papers/` (ignored). The regional rows typed in from Annexes 3 to 5 are facts with a citation; no text or table is reproduced.
- [ ] **WHO Global Health Observatory.** Open use with attribution. The pulled rows carry the indicator URL; the data policy is linked in the methodology licences section.
- [ ] **DHS Program.** Indicator API aggregates only, no microdata, citation required. Verify that nothing under `data/` or `data-raw/` is DHS microdata (no registration was made, so none can be there). The DHS citation is in each baseline row's `source` column; add the standard DHS citation sentence to the README.
- [ ] **JMP via the openwashdata jmpdata package** (CC BY 4.0): attribution present in the baseline-exposure rows and the methodology.
- [ ] **OpenAlex.** Metadata (titles, authors, DOIs, venues) is released under CC0; the screening logs, candidate list and `data/references.bib` hold only such metadata. The abstracts pulled for screening are in `data-raw/` (ignored) and must stay out.
- [ ] **Europe PMC and publisher full texts.** Each article keeps its own licence; the texts in `papers/` are ignored and stay out. `data/fulltext-log.csv` records where each came from and holds no text.
- [ ] **Extracted numbers.** Effect sizes, intervals and study counts are facts with a locator; no figure or table is reproduced. Keep it that way.
- [ ] **ILF for WASH knowledge report** (Aqua for All): the example inputs (2 500 KWSH connections, 1 475 Tap Effect connections, 93 percent filter washing) are quoted with the report as source and marked illustrative where the agent made a number up. Confirm the report is public before citing it in a public README.
- [ ] **Terms of reference.** The ToR text is not in the repository (it was read from a scratch folder). Keep it out; cite it by title and month only. The ToR's clause that intellectual property of the final deliverables stays with Aqua for All does not apply: no contract exists and this is an independent build, which the README says in plain words.
- [ ] **Licence files.** `LICENSE.md` at the root holds both notices in one line; GitHub detects one licence per file. Consider `LICENSE` (MIT text, as in `pkg/LICENSE.md`) plus `LICENSE-CC-BY-4.0.md` for the tables and documents, with the one-line summary kept in the README.

## 4. Names, affiliations and contact details

- [ ] `pkg/DESCRIPTION` carries `lars@lse.de`. Decide whether that is the address to publish, or an institutional one.
- [ ] Every document's callout says "produced by an agent for Lars Schöbitz". Keep the sentence; it is the honest provenance. Decide whether to name the model (Claude) in the README as the citation file does.
- [ ] Remove the author line of the professor's one-pager from anything public (it is not in this repository; the public one-pager is `docs/one-page-summary.qmd` with a contact placeholder).
- [ ] Fill the placeholders: `CITATION.cff` (affiliation, ORCID, repository URL, release date), `README-public.md` (contact, repository URL), `docs/one-page-summary.qmd` (contact line).
- [ ] Check `git log` author and committer names and emails are the ones to publish (the history goes public with the repository; it holds the agent session links in the commit trailers, which is intended).

## 5. Citation file

- [x] Drafted: `CITATION.cff` at the repository root, with Lars as author and the agent assistance stated in the abstract. Validate it before release (`cffconvert --validate`, or the GitHub citation widget after the first push).

## 6. README for a public audience

- [x] Drafted: `README-public.md`. On publication, replace `README.md` with it (`git mv README-public.md README.md`) after filling the placeholders. It says how the repository was made, what has and has not been reviewed, what the tool does and does not do, how to install and cite, and how to review a row.

## 7. Data and files that stay out

- [ ] `papers/` and `data-raw/` are ignored (`.gitignore`). Verify before the push: `git ls-files | grep -E '^(papers|data-raw)/'` must print nothing.
- [ ] No secrets: `git grep -n -i -E 'api[_-]?key|OPENALEX_|Renviron'` must show only the request log's "keyed" marker and the stage 1 report sentence; the key itself lives in `~/.Renviron` outside the repository.
- [ ] `scripts/__pycache__/` is untracked; add it to `.gitignore`.
- [ ] Rendered HTML (`docs/*.html`), the rendered one-pager PDF (`docs/*.pdf`), `docs/reports/` and the pkgdown site (`pkg/docs/`) are ignored. Decide whether to publish rendered documents at all (GitHub Pages from a `gh-pages` branch, or none).
- [ ] The scratch examples with illustrative counts (`pkg/inst/extdata/transactions-examples.csv`) are marked illustrative in their notes column; keep the marks.

## 8. Zotero import

- [ ] Stage 1 left the question open: import `data/references.bib` (373 entries) into Zotero now or after a human screen of the included list. Suggestion: after the screen, into a collection named after the repository, so that the Zotero library does not carry 123 mapped-only works nobody has read. The entries carry an OpenAlex id in the note field and a keyword with the screening category, so a later filter is possible. The import itself is one step (File, Import, or the Zotero MCP `zotero_add_by_bibtex`); no entry has a PDF attached, which is intended.

## 9. pkgdown site

- [ ] The site was built locally into `pkg/docs/` during stage 4 (see `docs/stage4-report.md` for the result and size). `pkg/docs/` is ignored. If the repository goes public, either commit the folder and serve it with GitHub Pages from `pkg/docs/`, or build it in a GitHub Action onto `gh-pages` (the usethis `use_pkgdown_github_pages()` pattern). The package has no `_pkgdown.yml`; add one with a reference index grouped by task (inputs, estimation, labels, exports, report and app, tables) before publishing the site.
- [ ] The package is installed from the repository, not from CRAN or r-universe. If an r-universe home is wanted later, the openwashdata universe already exists.

## 10. Repository name and organisation

Suggested name: keep `wash-health-impact-tool` for the repository (it names the assignment and is findable) with the package inside it as `washhealth`. The alternative, naming the repository `washhealth`, would read as a package repository and hide the evidence review and the tables, which are the larger part.

Organisation options, with the trade-off and no decision:

| Option | For | Against |
| --- | --- | --- |
| `openwashdata` | Open data and tools for the sector is the organisation's purpose; the jmpdata package the tool uses lives there; CC BY and MIT match its practice; an r-universe already exists; no institutional endorsement is implied | Lars's company and ETH both sit behind openwashdata; the name does not say who stands behind the evidence review |
| `Global-Health-Engineering` | The group's research and the professor's involvement are visible; fits a possible research follow-up on the three questions | Implies group endorsement of unreviewed tables unless the README says otherwise; the group's repositories are mostly research projects, not tools for funders; a decision for Liz, not Lars alone |
| Lars's personal account | No institutional question at all; fastest | Harder to find; looks like a hobby project to a funder |

## 11. Before the push

- [ ] `devtools::check("pkg")` clean, `devtools::test("pkg")` passing, `factors_version()` equal to the hash of the last commit touching `data/factors/` (no `-dirty`).
- [ ] All Quarto documents render from a clean clone (`quarto render docs/evidence-review.qmd` and the others) with the package installed.
- [ ] Tag `v0.1.0` after the review, not before; the first public commit can carry the unreviewed state as long as the README says so.
- [ ] Open the repository with issues enabled and one issue per open question from the stage reports (STH baselines, valuation, platform choice, update rhythm), so that reviewers have somewhere to write.
- [ ] Then, and only then, the emails in `docs/draft-email-aqua-for-all.md` with the repository link filled in.
