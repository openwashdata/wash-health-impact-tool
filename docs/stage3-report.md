# Stage 3 report: the tool

Scratch reproduction of phase 3 of the Aqua for All assignment "Developing a water and sanitation - health impact estimation tool for outcome-based finance". Built on 2026-10-23 by an agent for Lars Schöbitz on top of the stage 2 methodology and factor tables. Nothing here has been reviewed by a person. Local repository on branch `dev`, no remote, nothing published anywhere. No network request was made in this stage.

The decisions taken before the run were applied and not reopened: an open calculation core as an R package (MIT for code, CC BY 4.0 for the tables and documents); the canonical tables stay in `data/factors/` and the package carries a stamped copy; a Quarto transaction report template, a small Shiny app for ex-ante and ex-post use, and a flat factor export for an Airtable, mWater or spreadsheet front end; retrieve, do not compute, with a ledger and a confidence label on every result.

## 1. What exists

| Deliverable | Location | State |
| --- | --- | --- |
| R package `washhealth` 0.1.0 | `pkg/` | builds, checks clean, installed locally for the tests and the examples |
| Factor tables as package data with a version stamp | `pkg/data/*.rda`, `pkg/inst/extdata/*.csv`, `pkg/inst/extdata/factors-version.txt`, built by `pkg/data-raw/factors.R` | stamp `2026-10-23-55eb4cc` (date and short hash of the last commit that changed a table file); `factors_version()` returns it; `pkg/R/data.R` is generated from the schema |
| Estimation chain | `pkg/R/estimate.R` (`estimate_output()`, `estimate_mortality_band()`, `compare_who_scenario()`, `bind_estimates()`), `pkg/R/retrieve.R`, `pkg/R/label.R` | the stage 2 functions, ported; `tables` is now the last argument and defaults to the package copy |
| Transaction input schema | `pkg/inst/extdata/transaction-template.csv` (14 required columns plus 9 optional), `transaction_columns()`, `read_transactions()`, `as_transactions()`, `new_transaction()` | validates columns, countries, output types, dates and shares; reports every problem in one message |
| Ex-post and ex-ante runners | `estimate_transaction()`, `estimate_scenario()` in `pkg/R/transactions.R` | one row per transaction, scope (verified or planned total, incentive-attributable) and outcome, with low, central, high, label, flags; the ledger per row; `summarise_portfolio()`; `check_ledger()` |
| Flat exports | `export_factors()` (CSV folder or one xlsx workbook: the five tables, wide versions of the two baseline tables, `factor_cards()`, a data dictionary, a version sheet), `export_results()` | written and read back in the tests |
| Quarto transaction report | `pkg/inst/templates/transaction-report.qmd`, `render_transaction_report()` | renders; four example reports in `docs/reports/` (ignored by git): KWSH, Aqua Clara Kenya, the five example rows as a portfolio, and an ex-ante plan |
| Shiny app | `pkg/inst/app/app.R`, `run_app()` | two tabs (ex-ante, ex-post), bslib layout when installed; served headless on port 48731 with HTTP 200; server logic tested with `shiny::testServer()` |
| Worked examples as a transaction table | `pkg/inst/extdata/transactions-examples.csv`, `example_transactions()` | KWSH, Tap Effect (two rows), Aqua Clara Kenya, ATEC; counts partly illustrative as in stage 2 |
| Governance | `docs/factor-table-governance.md`, `data/factors/CHANGELOG.md` | roles, review checklist, stamp, rebuild, past reports; changelog starts with the stage 2 state |
| Stage 2 documents on the package | `docs/methodology.qmd`, `docs/additionality-guidance.qmd`, `docs/worked-examples.qmd` | load `washhealth` instead of sourcing `R/estimate.R`; all three render; the root `R/` and `tests/` folders are removed |
| Package documentation | 33 help pages in `pkg/man/`, `pkg/README.md`, `pkg/NEWS.md` | every exported function has a runnable example |

### Changes to the factor tables in this stage

Two commits, both recorded in `data/factors/CHANGELOG.md`, no value changed: four schema descriptions now point at the package (`9ab53d4`), and the three curated tables (effects, adjustments, pathways) got an empty `superseded_by` column with three schema rows (`55eb4cc`). A replaced value gets a new row with the same identifier and a later `valid_from`; the old row's `superseded_by` holds that date and stays for the record. `current_rows()` drops superseded rows and the retrieval functions return the one current row for an identifier or stop with a message.

### Engine changes against stage 2

Written into `pkg/NEWS.md` and tested:

1. `years` may be a fraction: a six-month period counts half of year one. The transaction runners derive it from the period (rounded to two decimals so a calendar year counts as 1).
2. A missing community sanitation coverage falls back to the JMP country value for the residence type, with the flag `coverage_from_jmp` (one step down) and a ledger row, as the `ADJ_COV_SAN_THRESHOLD` use rule says. Stage 2 jumped to the household-targeted row. The ATEC example gives the same numbers as before because stage 2 passed the JMP value by hand.
3. Water points, institutional connections and MHH outputs refuse to run without `people_per_unit`, as their `people_per_unit_rule` says; the validation of a transaction table says so before the run.
4. `estimate_scenario_difference()` is renamed `compare_who_scenario()`.
5. The flag dictionary (`confidence_flags()`) gained `coverage_from_jmp`, `output_not_verified` (ex-post run without a verifier, allowed only with `require_verification = FALSE`), `use_is_target` (ex-ante note) and `incentive_share_missing` (note; attributable rows stay empty).

The stage 2 example values are reproduced by a test (Aqua Clara 681 cases, 545 to 803, moderate; KWSH 272 cases, very low).

## 2. Check and test results

- `devtools::document()`: clean.
- `devtools::test()`: 290 expectations in 40 tests across 5 files, 0 failures, 0 skips (with the package installed; without it the report render and app tests skip).
- `devtools::check("pkg", cran = FALSE, args = "--no-manual")`: 0 errors, 0 warnings, 0 notes; inside the check the test run reports `FAIL 0 | WARN 0 | SKIP 0 | PASS 290`. The check was run without `--as-cran` on purpose: that mode queries CRAN and checks URLs over the network. Expected notes if it is ever run with `--as-cran`: new submission. One thing to know rather than a check finding: the data object `effects` shadows `stats::effects` when the package is attached (`conflicts()` lists it; `library()` prints no message for datasets). Kept because the task named the objects; a one-line rename if wanted.
- Headless app test: `Rscript -e "washhealth::run_app(port = 48731, host = '127.0.0.1', launch.browser = FALSE)"` in the background, `curl` of the page returned HTTP 200 with both tab titles and both buttons present, process killed, none left running. `shiny::testServer()` runs an ex-ante scenario, an ex-post estimate and a validation error through the server logic (part of the test suite).
- The three stage 2 documents re-render on the package (`quarto render docs/*.qmd`).

Installed in this stage: nothing new. `washhealth` itself was installed into the user library (`R CMD INSTALL pkg`) because the report renders in a separate R process and the app sources the package. All other packages used (devtools, usethis, roxygen2, testthat, shiny, bslib, writexl, knitr, rmarkdown, tibble) were already present; shinytest2 is not installed and was not needed.

## 3. How to run it

```r
library(washhealth)

# ex-post from a verifier's table in the template format
tx <- read_transactions("transactions.csv")            # template: transaction_template_path()
res <- estimate_transaction(tx)
res$results; res$ledger; summarise_portfolio(res)
export_results(res, "results-export")                  # CSV folder; format = "xlsx" for one workbook
render_transaction_report(tx[tx$enterprise == "KWSH", ], output_dir = "docs/reports")

# ex-ante
plan <- new_transaction("PLAN-1", "Example Co", "Kenya", "household water filter", 2000,
                        "2027-01-01", "2027-12-31", use_rate = 0.9, baseline_quantity = 1200)
estimate_scenario(plan)
render_transaction_report(plan, output_dir = "docs/reports", mode = "ex-ante")

# flat tables for Airtable, mWater, Power BI or Excel
export_factors("factors-export")                       # ten CSV files
export_factors("factors.xlsx", format = "xlsx")        # one workbook, one sheet per table

# the app
run_app()                                              # or run_app(port = 4000, launch.browser = FALSE)
```

Quarto is found through `QUARTO_PATH`, the PATH, or the RStudio bundle on macOS (`quarto_bin()`); pass `quarto_bin = ` otherwise. After a reviewed table change: commit it, run `Rscript pkg/data-raw/factors.R`, `devtools::document("pkg")`, reinstall, test, commit the package copy (governance document, section 6).

## 4. What was left out

- No Airtable base, mWater form or Power BI model was built; the flat export (`export_factors()`) and the factor cards are the hand-off for whoever builds one. The factor cards let a spreadsheet formula reproduce the central estimate of the cases route; the label logic, the PAF route and the ledger stay in R.
- The app runs one output at a time; a CSV upload of a whole transaction table is not in the app (it is one function call in R and the report covers the table case).
- The report has no PDF format (HTML only, self-contained). Quarto can add `--to pdf` with the installed TinyTeX; not tested.
- No pkgdown site (pkgdown is installed; a site would need a public home and there is none by decision).
- The baseline tables have no `superseded_by` column; they are rebuilt by script and versioned through the stamp and git history (governance document, section 4).
- No valuation step (cost per DALY) and no STH baseline prevalence, as in stage 2.
- The WHO scenario comparison and the direct mortality band are in the package and the worked examples but not in the transaction report or the app (the guidance says they are checks, not headline numbers).
- Validation accepts any `unit` text; it does not force the pathway's `unit_of_output`.
- No human review of any row, test, document or report.

## 5. Open questions for stage 4 (write-up)

1. **Evidence review document.** Stage 1's report and the stage 1 tables (`data/effect-sizes.csv`, the landscape tables, the screening log) are the material; the write-up needs the PRISMA-style flow as a figure and a human check of a sample of the 1 626 abstract decisions before the review is cited. Who does the sample, and how large?
2. **User guide.** Audience and depth: a funder's analyst filling the transaction template and reading the report, or also the maintainer rebuilding tables? The template columns, the flag dictionary (`confidence_flags()`) and the communication rules are the backbone; the worked examples give the screenshots.
3. **One-page summary.** What goes on it: the chain figure from the methodology, the four example results with labels, and the governance rule in one line? And whether deaths and DALYs appear at all on a one-pager (communication rule 5 says portfolio scale only).
4. **Naming and licence text.** The package is `washhealth`; the data objects are named as the task asked (`effects` shadows `stats::effects` when the package is attached). The CC BY 4.0 notice for the tables and the MIT notice for the code are in `pkg/LICENSE.md`; the ToR says all intellectual property of the final deliverables stays with Aqua for All, which the write-up should reconcile with the open licence (the ToR itself asks for a Creative Commons publication).
5. **Validation cases.** The example rows still carry illustrative counts (Aqua Clara filters, ATEC toilets, Tap Effect institutions) and illustrative incentive shares. Real transaction data from Aqua for All and Roots of Impact would replace them, and one hygiene and one MHH enterprise are still missing.
6. **Platform choice.** The ToR names Airtable, mWater and Power BI. The export is platform-neutral; the write-up should recommend one path (for example Airtable for the transaction table and the factor cards, the R package for the runs and reports) and say what a formula-level reproduction on the platform can and cannot do (no label logic, no ledger).
7. **Update rhythm and roles.** The governance document names the method lead, a reviewer and Aqua for All's approver as roles; the names and the yearly update after the JMP release need a decision.

## 6. Files

- Package: `pkg/DESCRIPTION`, `pkg/NAMESPACE`, `pkg/R/` (`washhealth-package.R`, `utils.R`, `retrieve.R`, `label.R`, `estimate.R`, `transactions.R`, `export.R`, `report.R`, `app.R`, `data.R`), `pkg/man/` (33 files), `pkg/data/` (6 objects), `pkg/data-raw/factors.R`, `pkg/inst/extdata/` (6 stamped tables, `factors-version.txt`, `transaction-template.csv`, `transactions-examples.csv`), `pkg/inst/templates/transaction-report.qmd`, `pkg/inst/app/app.R`, `pkg/tests/testthat/` (5 files), `pkg/NEWS.md`, `pkg/README.md`, `pkg/LICENSE`, `pkg/LICENSE.md`.
- Tables: `data/factors/effects.csv`, `adjustments.csv`, `pathways.csv` (new column), `factors-schema.csv` (79 rows), `data/factors/CHANGELOG.md`.
- Documents: `docs/factor-table-governance.md`, `docs/stage3-report.md`, the three stage 2 documents updated; `docs/reports/` holds the four rendered example reports (ignored).
- Repository: `README.md` and `.gitignore` updated (ignore patterns anchored to the root so that `pkg/data-raw/` is tracked; `docs/reports/`, `*.Rcheck/` and `*.tar.gz` ignored); the root `R/estimate.R` and `tests/testthat/test-estimate.R` removed.
- Commits on `dev` in this stage: `9ab53d4`, `4398bc6`, `7f31bee`, `b1e75fe`, `55eb4cc`, `c4b8128`, `f0a8027`, plus the commit of this report.
