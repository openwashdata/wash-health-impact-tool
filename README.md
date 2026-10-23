# wash-health-impact-tool

Scratch build of the Aqua for All assignment "Developing a water and sanitation - health impact estimation tool for outcome-based finance" (ToR of October 2026). Local repository, no remote. Built in the background by an agent for Lars Schöbitz; nothing here has been reviewed or shared.

Decisions of 2026-10-23: outcomes modelled are diarrhoeal disease (cases, deaths, DALYs) and soil-transmitted helminth infection; respiratory infection and stunting are mapped in the evidence review but not modelled. Country baselines cover Aqua for All's geographies only. Methodology and factor tables under CC BY 4.0, code under MIT.

## Layout

- `queries/` every OpenAlex and other API query as it was run, with date and counts
- `data/` screening logs, the effect size table, country baselines (tracked)
- `data/factors/` the versioned factor tables the tool retrieves from: schema, effects, baselines (disease and exposure), adjustments, pathways
- `data-raw/` raw API responses and downloaded datasets (ignored)
- `papers/` open access full texts (ignored)
- `R/estimate.R` the estimation chain (function set; stage 3 turns it into a package); `tests/testthat/` its tests
- `scripts/` the data pulls and builds (Python 3 standard library and R); `09_stage2_baselines.py` and `10_build_baseline_tables.R` rebuild the baseline tables
- `docs/` stage reports (`stage1-report.md`, `stage2-report.md`), `methodology.qmd`, `additionality-guidance.qmd`, `worked-examples.qmd` (rendered HTML is ignored)

## Running the chain

```r
source("R/estimate.R")
tables <- load_factors("data/factors")
est <- estimate_output(tables, "P_POU_FILTER", units = 1000, country = "Kenya", residence = "rural",
                       baseline_source = "unimproved", verified_use = 0.93)
est            # summary with low, central, high and the confidence label
est$factors_used   # every row used, with citation
```

Tests: `Rscript -e 'testthat::test_dir("tests/testthat")'`. Documents: `quarto render docs/methodology.qmd` (same for the other two).

## Stages

1. Evidence and tool mapping
2. Methodology and additionality guidance
3. Tool: R package, Quarto template, Shiny app, flat factor export
4. Write-up
