# washhealth 0.1.0

First package version (stage 3 of the scratch build, 2026-10-23). Nothing has been reviewed by a person.

- The stage 2 function set (`R/estimate.R` of the tool repository) moved into the package. `estimate_output()` is the engine; `tables` is now the last argument and defaults to the package's own copy of the factor tables (`factor_tables()`). The result class is `washhealth_estimate`.
- `estimate_scenario_difference()` was renamed `compare_who_scenario()` to leave `estimate_scenario()` free for the ex-ante run.
- Factor tables ship as data objects (`effects`, `adjustments`, `pathways`, `baseline_disease`, `baseline_exposure`, `factors_schema`) with a version stamp from `factors_version()`; the package never reads the repository's `data/factors/` folder.
- New: `read_transactions()`, `as_transactions()`, `new_transaction()` and the input template; `estimate_transaction()` (ex-post) and `estimate_scenario()` (ex-ante) with totals and incentive-attributable rows; `summarise_portfolio()`; `check_ledger()`; `export_factors()`, `factor_cards()` and `export_results()`; `render_transaction_report()` with the Quarto template; `run_app()` with the Shiny app.
- Engine changes against stage 2: `years` may be a fraction (a six-month period counts half of year one); a missing community sanitation coverage now falls back to the JMP country value with the flag `coverage_from_jmp` and a ledger row, as the `ADJ_COV_SAN_THRESHOLD` use rule says (stage 2 jumped to the household-targeted row); water points, institutional connections and MHH outputs refuse to run without `people_per_unit`, as their pathway rule says.
- The curated tables (effects, adjustments, pathways) carry a `superseded_by` column; `current_rows()` drops superseded rows and the retrieval functions return the one current row for an identifier or stop with a message. Factor table stamp `2026-10-23-55eb4cc`.
- No new dependencies beyond tibble; shiny, bslib and writexl are optional.
