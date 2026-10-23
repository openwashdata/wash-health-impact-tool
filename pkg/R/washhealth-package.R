#' washhealth: estimate health outcomes from verified water and sanitation outputs
#'
#' The package follows one rule: retrieve, do not compute. Every number that
#' enters a calculation is a row in a versioned factor table with a citation.
#' The functions only do arithmetic on retrieved rows and return the ledger of
#' rows they used, a low, central and high value and a confidence label.
#'
#' Start with [read_transactions()] and [estimate_transaction()] for verified
#' outputs (ex-post), [estimate_scenario()] for planned outputs (ex-ante),
#' [summarise_portfolio()] to add results up, [render_transaction_report()]
#' for the Quarto report, [export_factors()] for a flat copy of the tables and
#' [run_app()] for the Shiny app. [estimate_output()] is the engine behind all
#' of them.
#'
#' @keywords internal
"_PACKAGE"

NULL
