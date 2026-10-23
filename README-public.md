# wash-health-impact-tool

Estimate health outcomes from verified water and sanitation outputs, for outcome-based finance. An evidence review, versioned conversion factor tables, a methodology, additionality guidance and an R package (`washhealth`) with a transaction report template, a small Shiny app and flat exports for Airtable, mWater or Excel.

Status: **prototype, under review.** Read the next section before using any number.

## How this was made, and what has been reviewed

In October 2026 Aqua for All published terms of reference for a consultancy to develop a water and sanitation health impact estimation tool for its Social Impact Incentives (SIINC) transactions. Lars Schöbitz did not bid. Instead, to test whether the three evidence questions in the terms of reference can be answered from the literature, he had an AI agent (Claude, Anthropic) run the assignment as a scratch build on 2026-10-23: the literature search, the screening, the extraction of effect sizes, the country baselines, the methodology, the factor tables, the package, its tests and the documents. The decisions (which outcomes, which countries, which counterfactual, which licences) were his and are listed at the top of each stage report; the work between the decisions was the agent's, in about one afternoon. This repository is independent of Aqua for All and of any institution; nobody has endorsed it.

What this means for a reader:

- Every screening decision (10 577 records, one reader, one pass), every extracted number (77 effect size rows) and every factor row (24 effects, 20 adjustments, 13 pathways) was produced by the agent. The human review of the factor rows is recorded in `data/factors/CHANGELOG.md`; where an entry says "Reviewer: none", the row is unreviewed.
- Every number is traceable: each factor row carries a DOI, a locator (table, figure or section), the source review's certainty rating and a use rule. Each result carries the ledger of rows it used. Checking a row takes minutes; please do, and open an issue when a value is wrong.
- The tool refuses to guess. Where no pooled evidence exists (faecal sludge management services, water kiosks, safely managed on-site sanitation, institutional connections, menstrual health products) it reports reach and says "not estimable" or carries an evidence gap flag.

## What the tool does

You give it the outputs an enterprise delivered or plans to deliver (household connections, filters, toilets, hygiene products; country, period, verified use, baseline water source of the customers). It returns people reached, diarrhoea cases averted in children under five, deaths and DALYs averted, each with a low, central and high value, a confidence label (moderate, low, very low, not estimable) with the reasons, and the ledger of every published number used. One rule: retrieve, do not compute.

Two uses: ex-post from a verifier's report, ex-ante from planned outputs with a baseline trajectory for the incentive-attributable share.

## Install and use

Needs R 4.1 or newer. From the repository root:

```sh
R CMD INSTALL pkg
```

```r
library(washhealth)
tx <- read_transactions("transactions.csv")         # template: transaction_template_path()
res <- estimate_transaction(tx)                      # ex-post
res$results; res$ledger; summarise_portfolio(res)
render_transaction_report(tx, output_dir = "reports")
export_factors("factors-export")                     # flat tables for Airtable, mWater or Excel
run_app()                                            # Shiny app, ex-ante and ex-post
```

The user guide is `docs/user-guide.qmd`; the methodology, the additionality guidance, the worked examples and the evidence review are in `docs/` as well. Render them with Quarto after installing the package.

## Layout

- `data/factors/` the versioned factor tables and their changelog (CC BY 4.0)
- `data/` the screening logs, the effect size table, the landscape tables, the country baselines and the reference list
- `queries/` every API query as it was run, with date and counts
- `scripts/` the data pulls and builds (Python 3 standard library and R)
- `pkg/` the `washhealth` R package (MIT), with a stamped copy of the tables
- `docs/` the evidence review, methodology, additionality guidance, worked examples, user guide, governance rules and the stage reports

Full texts and raw API responses are not in the repository.

## Licences

Code: MIT. Methodology, factor tables and documents: Creative Commons Attribution 4.0 International (CC BY 4.0). Source data keep their own terms: WHO Global Health Observatory (open use with attribution), DHS Program indicator data (aggregates, citation required), WHO/UNICEF JMP data via the openwashdata jmpdata package (CC BY 4.0), the WHO 2023 burden report (values cited, the report and its workbook not redistributed; the attributable fraction method is re-implemented from the published description).

## Cite

See `CITATION.cff`. Please also cite the source reviews behind any factor you use; they are named in the factor table rows and in the evidence review's reference list.

## Contribute or review

Open an issue for a wrong value, a missing source or a method question. To propose a change to a factor row, follow `docs/factor-table-governance.md`: a new row with a new `valid_from` date, the old row marked `superseded_by`, a changelog entry, and a second person's review. An agent may draft a change; a person merges it.

Contact: CONTACT PLACEHOLDER.
