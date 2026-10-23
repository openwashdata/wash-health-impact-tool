# washhealth

Estimate health outcomes from verified water and sanitation outputs for outcome-based finance. Scratch build for the Aqua for All assignment (stage 3), not reviewed. Code MIT, factor tables CC BY 4.0.

One rule: retrieve, do not compute. Every number comes from a versioned factor table row with a citation. Each result carries the ledger of rows used, a low, central and high value and a confidence label.

## Install

From the tool repository root:

```sh
R CMD INSTALL pkg
```

## Use

```r
library(washhealth)

# ex-post: verified outputs from the verifier's report
tx <- read_transactions("transactions.csv")      # template: transaction_template_path()
res <- estimate_transaction(tx)
res$results                                       # totals and incentive-attributable rows, with labels
res$ledger                                        # every factor row used, with citations
summarise_portfolio(res)
export_results(res, "results-export")             # CSV folder, or format = "xlsx"
render_transaction_report(tx, output_dir = "reports")

# ex-ante: planned outputs and a baseline trajectory
plan <- new_transaction("PLAN-1", "Example Co", "Kenya", "household water filter", 2000,
                        "2027-01-01", "2027-12-31", use_rate = 0.9, baseline_quantity = 1200)
estimate_scenario(plan)

# one output through the engine
estimate_output("household water filter", units = 1000, country = "Kenya", residence = "rural",
                baseline_source = "unimproved", verified_use = 0.93)

# flat tables for Airtable, mWater or Excel
export_factors("factors-export")                  # or export_factors("factors.xlsx", format = "xlsx")
factors_version()

# the app
run_app()
```

## Updating the factor tables

The canonical tables live in `data/factors/` at the repository root. After a reviewed change there (see `docs/factor-table-governance.md`), rebuild the package copy with `Rscript pkg/data-raw/factors.R`, which stamps the copy with the date and git hash of the last commit that touched the tables, then reinstall.

## Layout

- `R/retrieve.R` table access and the ledger, `R/estimate.R` the chain, `R/label.R` confidence labels, `R/transactions.R` the input schema and the runners, `R/export.R` flat exports, `R/report.R` the Quarto report runner, `R/app.R` the app launcher, `R/data.R` generated documentation of the data objects
- `inst/extdata/` the stamped tables, the transaction template and the worked examples
- `inst/templates/transaction-report.qmd` the report
- `inst/app/app.R` the Shiny app
- `tests/testthat/` the tests
