# wash-health-impact-tool

Scratch build of the Aqua for All assignment "Developing a water and sanitation - health impact estimation tool for outcome-based finance" (ToR of October 2026). Local repository, no remote. Built in the background by an agent for Lars Schöbitz; nothing here has been reviewed or shared.

Decisions of 2026-10-23: outcomes modelled are diarrhoeal disease (cases, deaths, DALYs) and soil-transmitted helminth infection; respiratory infection and stunting are mapped in the evidence review but not modelled. Country baselines cover Aqua for All's geographies only. Methodology and factor tables under CC BY 4.0, code under MIT.

## Layout

- `queries/` every OpenAlex and other API query as it was run, with date and counts
- `data/` screening logs, the effect size table, country baselines (tracked)
- `data/factors/` the canonical versioned factor tables the tool retrieves from: schema, effects, baselines (disease and exposure), adjustments, pathways; `CHANGELOG.md` records every change
- `data-raw/` raw API responses and downloaded datasets (ignored)
- `papers/` open access full texts (ignored)
- `pkg/` the `washhealth` R package: the estimation chain, the transaction input schema, ex-post and ex-ante runners, flat exports, the Quarto transaction report template and the Shiny app; carries a stamped copy of the factor tables
- `scripts/` the data pulls and builds (Python 3 standard library and R); `09_stage2_baselines.py` and `10_build_baseline_tables.R` rebuild the baseline tables
- `docs/` stage reports (`stage1-report.md`, `stage2-report.md`, `stage3-report.md`), `methodology.qmd`, `additionality-guidance.qmd`, `worked-examples.qmd`, `factor-table-governance.md`; rendered HTML and `docs/reports/` (rendered transaction reports) are ignored

## Running the tool

Install the package once from the repository root, then use it:

```sh
R CMD INSTALL pkg
```

```r
library(washhealth)

# ex-post: verified outputs in the template format (transaction_template_path())
tx <- read_transactions("transactions.csv")
res <- estimate_transaction(tx)
res$results        # totals and incentive-attributable rows with low, central, high and the label
res$ledger         # every factor row used, with citation
summarise_portfolio(res)
export_results(res, "results-export")                 # or format = "xlsx"
render_transaction_report(tx, output_dir = "docs/reports")

# ex-ante: planned outputs and a baseline trajectory
plan <- new_transaction("PLAN-1", "Example Co", "Kenya", "household water filter", 2000,
                        "2027-01-01", "2027-12-31", use_rate = 0.9, baseline_quantity = 1200)
estimate_scenario(plan)

# one output through the engine
estimate_output("household water filter", units = 1000, country = "Kenya", residence = "rural",
                baseline_source = "unimproved", verified_use = 0.93)

# flat factor tables for Airtable, mWater or Excel, and the app
export_factors("factors-export")                      # or export_factors("factors.xlsx", format = "xlsx")
run_app()
```

Tests: `Rscript -e 'devtools::test("pkg")'`. Check: `Rscript -e 'devtools::check("pkg")'`. Documents: `quarto render docs/methodology.qmd` (same for the other two; they need the package installed).

After a reviewed change to `data/factors/` (see `docs/factor-table-governance.md`), rebuild the package copy with `Rscript pkg/data-raw/factors.R` and reinstall.

## Stages

1. Evidence and tool mapping
2. Methodology and additionality guidance
3. Tool: R package, Quarto template, Shiny app, flat factor export
4. Write-up
