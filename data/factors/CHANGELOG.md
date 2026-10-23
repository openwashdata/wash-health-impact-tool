# Changelog of the factor tables

Every change to `data/factors/` gets an entry: date, git hash (the version stamp is the date plus this hash), rows changed, reason, source, reviewer, and which outputs change. Rules in `docs/factor-table-governance.md`. Newest first.

## 2026-10-23, 55eb4cc: superseded_by column on the curated tables

- Tables: `effects.csv`, `adjustments.csv`, `pathways.csv` (new column `superseded_by`, empty on every row), `factors-schema.csv` (three rows describing it).
- Reason: the governance rules need a machine-readable pointer from a replaced row to its replacement; the package retrieves only rows whose `superseded_by` is empty.
- Values changed: none.
- Reviewer: none (agent draft, stage 3).
- Outputs that change: none.

## 2026-10-23, 9ab53d4: schema descriptions point at the package

- Table: `factors-schema.csv` (descriptions of `effects.factor_id`, `adjustments.adjustment_id`, `pathways.pathway_id`, `pathways.effect_rule`).
- Reason: the estimation chain moved from `R/estimate.R` at the repository root into the `washhealth` package.
- Values changed: none.
- Reviewer: none (agent draft, stage 3).
- Outputs that change: none.

## 2026-10-23, b6df8b7: stage 2 state (first version)

The tables as built in stage 2 (`docs/stage2-report.md`), the state the package copy was first stamped with (`2026-10-23-b6df8b7`).

- `factors-schema.csv`: 76 rows, column definitions for the five tables.
- `effects.csv`: 24 rows. 16 diarrhoea rows (water supply and point-of-use rows from Wolf et al. 2022, sanitation rows from Wolf et al. 2022 and the household-targeted row, hygiene promotion), 1 STH row (Cochrane 2022, OR 0.86), 7 mortality rows for the sensitivity band (Kremer et al. 2023, Sharma Waddington et al. 2023). Certainty labels carried from the source reviews' GRADE ratings; `valid_from` 2026-10-23 on every row.
- `adjustments.csv`: 20 rows. Use references (chlorination 0.62, filtration 0.90 from the Cochrane 2015 trial tables; connections, sanitation and hygiene by rule), decay (point-of-use 0.62 derived from the long-run filter row; sanitation and hygiene unquantified), the sanitation coverage threshold 0.50 (judgement call after Sharma Waddington 2023 and Larsen 2017), the episode duration 4.3 days (Lamberti 2012), the U5MR to annual rate factor 0.2, the OR to RR formula (Zhang and Yu 1998), three PAF counterfactual relative risks (Wolf et al. 2023 and WHO 2023), three service ladder RR sets.
- `pathways.csv`: 13 rows: household connection, institutional connection, water point or kiosk, filter, chlorination, solar disinfection, in-line chlorination, basic toilet, sewer connection, container-based or on-site with service, emptying service, hygiene product with promotion, MHH.
- `baseline-disease.csv`: 346 rows for 11 countries plus three WHO regions and one global row. WHO 2019 attributable deaths and DALYs (all ages and under five), four attributable fractions, SDG 3.9.2 deaths and rate, U5MR; DHS two-week diarrhoea prevalence, household size, under-five share, U5MR; derived population, total deaths and DALYs, death and DALY rates; STH prevalence as missing markers (not pulled); regional rows from WHO 2023 Annexes 3 to 5 and Fischer Walker 2012. Built by `scripts/10_build_baseline_tables.R` (commit b6df8b7 fixed the DHS row selection by the by-variable label).
- `baseline-exposure.csv`: 520 rows. JMP water ladder 2024 (national, urban, rural) via the openwashdata jmpdata package; GHO sanitation and hygiene series with derived rungs; three missing markers (safely managed water for Kenya and Rwanda, safely managed sanitation for Rwanda).
- Judgement calls are written into the `notes` and `use_rule` columns and listed in `docs/stage2-report.md` section 3.
- Reviewer: none (agent build, stage 2). Every row needs a human review before any number is published.
