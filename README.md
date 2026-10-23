# wash-health-impact-tool

Scratch build of the Aqua for All assignment "Developing a water and sanitation - health impact estimation tool for outcome-based finance" (ToR of October 2026). Local repository, no remote. Built in the background by an agent for Lars Schöbitz; nothing here has been reviewed or shared.

Decisions of 2026-10-23: outcomes modelled are diarrhoeal disease (cases, deaths, DALYs) and soil-transmitted helminth infection; respiratory infection and stunting are mapped in the evidence review but not modelled. Country baselines cover Aqua for All's geographies only. Methodology and factor tables under CC BY 4.0, code under MIT.

## Layout

- `queries/` every OpenAlex and other API query as it was run, with date and counts
- `data/` screening logs, the effect size table, factor tables, country baselines (tracked)
- `data-raw/` raw API responses and downloaded datasets (ignored)
- `papers/` open access full texts (ignored)
- `R/` scripts of the evidence stage, later the package
- `docs/` stage reports, evidence review, methodology, user guide

## Stages

1. Evidence and tool mapping
2. Methodology and additionality guidance
3. Tool: R package, Quarto template, Shiny app, flat factor export
4. Write-up
