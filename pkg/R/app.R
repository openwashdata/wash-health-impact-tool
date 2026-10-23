#' Run the Shiny app
#'
#' Starts the app shipped in `inst/app/`: two tabs, ex-ante (planned outputs
#' and an incentive share) and ex-post (verified outputs), with the results,
#' the confidence label and its reasons, the factor ledger with citations, CSV
#' downloads and a link to the methodology. Needs the shiny package; uses
#' bslib for the layout when it is installed.
#'
#' @param methodology_url Link shown in the app's methods note. By default the
#'   methodology document is named without a link.
#' @param ... Passed to [shiny::runApp()] (for example `port`,
#'   `launch.browser`).
#' @return Called for its side effect.
#' @export
#' @examples
#' \dontrun{
#' run_app()
#' }
run_app <- function(methodology_url = NULL, ...) {
  if (!requireNamespace("shiny", quietly = TRUE)) stop("the app needs the shiny package", call. = FALSE)
  dir <- system.file("app", package = "washhealth")
  if (!nzchar(dir)) stop("the app folder was not found; is washhealth installed?", call. = FALSE)
  old <- options(washhealth.methodology_url = methodology_url)
  on.exit(options(old), add = TRUE)
  shiny::runApp(dir, ...)
}
