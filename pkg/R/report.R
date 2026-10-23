# The Quarto transaction report.

#' Find the Quarto binary
#'
#' Looks at the `quarto_bin` argument, the `QUARTO_PATH` environment variable,
#' the PATH, and the usual install locations (including the copy bundled with
#' RStudio on macOS).
#'
#' @param quarto_bin Optional path to try first.
#' @return The path of the binary, or `""` when none was found.
#' @export
#' @examples
#' quarto_bin()
quarto_bin <- function(quarto_bin = NULL) {
  cands <- c(quarto_bin, Sys.getenv("QUARTO_PATH"), unname(Sys.which("quarto")),
             "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto",
             "/Applications/quarto/bin/quarto", "/usr/local/bin/quarto", "/opt/quarto/bin/quarto",
             "C:/Program Files/Quarto/bin/quarto.exe", "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe")
  cands <- cands[!is.na(cands) & nzchar(cands)]
  for (c in cands) if (file.exists(c)) return(c)
  ""
}

#' Path of the report template
#'
#' @return The path of `transaction-report.qmd` inside the installed package.
#' @export
#' @examples
#' report_template_path()
report_template_path <- function() system.file("templates", "transaction-report.qmd", package = "washhealth")

#' Render the transaction report
#'
#' Renders the Quarto report for one transaction, one enterprise or a small
#' portfolio: the inputs as verified (or planned), every factor row used with
#' its citation, the results with low, central and high values, the
#' confidence label and its reasons, the additionality statement, the
#' communication rules applied and a methods note. Needs Quarto and the
#' package installed (the report runs in a separate R process).
#'
#' @param transactions A transaction table, data frame or CSV path (see
#'   [read_transactions()]). Filter it to one transaction or enterprise for a
#'   single report.
#' @param output_dir Folder for the rendered file (created if needed).
#' @param mode `"ex-post"` (verified outputs) or `"ex-ante"` (planned
#'   outputs).
#' @param file Output file name; by default the date, the transaction id or
#'   enterprise and `-transaction-report.html`.
#' @param title Report title; by default built from the enterprise name.
#' @param require_verification Ex-post only; see [estimate_transaction()].
#' @param methodology_url Link printed in the methods note; by default the
#'   methodology document in the tool repository is named without a link.
#' @param quarto_bin Path to the Quarto binary; see [quarto_bin()].
#' @param quiet Hide Quarto's output.
#' @return The path of the rendered file, invisibly.
#' @export
#' @examples
#' \dontrun{
#' tx <- example_transactions()
#' render_transaction_report(tx[tx$enterprise == "KWSH", ], output_dir = tempdir())
#' }
render_transaction_report <- function(transactions, output_dir = ".", mode = c("ex-post", "ex-ante"), file = NULL, title = NULL,
                                      require_verification = TRUE, methodology_url = NULL, quarto_bin = NULL, quiet = TRUE) {
  tx <- as_transactions(transactions)
  mode <- match.arg(mode)
  bin <- quarto_bin(quarto_bin)
  if (!nzchar(bin)) stop("Quarto was not found; set the QUARTO_PATH environment variable or pass quarto_bin", call. = FALSE)
  template <- report_template_path()
  if (!nzchar(template)) stop("the report template was not found; is washhealth installed?", call. = FALSE)
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  work <- tempfile("washhealth-report-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  tx_chr <- as.data.frame(tx)
  for (col in names(tx_chr)) if (inherits(tx_chr[[col]], "Date")) tx_chr[[col]] <- format(tx_chr[[col]], "%Y-%m-%d")
  tx_chr <- tx_chr[, c(REQUIRED_COLUMNS, OPTIONAL_COLUMNS)]
  utils::write.csv(tx_chr, file.path(work, "transactions.csv"), row.names = FALSE, na = "", fileEncoding = "UTF-8")
  ids <- unique(tx$transaction_id); ents <- unique(tx$enterprise)
  if (is.null(title)) title <- if (length(ents) == 1) paste0(ents, ": estimated health outcomes") else "Estimated health outcomes across transactions"
  if (is.null(file)) {
    file <- paste0(format(Sys.Date(), "%Y-%m-%d"), "-", slug(if (length(ids) == 1) ids else if (length(ents) == 1) ents else "portfolio"), "-transaction-report.html")
  }
  if (basename(file) != file) stop("file must be a file name; use output_dir for the folder", call. = FALSE)
  # Quarto does not evaluate R inside the YAML title, so the title is written into the copy of the template.
  qmd <- readLines(template, warn = FALSE)
  qmd <- sub("__WASHHEALTH_TITLE__", gsub("\"", "'", title), qmd, fixed = TRUE)
  writeLines(qmd, file.path(work, "transaction-report.qmd"))
  yml <- function(k, v) paste0(k, ": \"", gsub("\"", "'", v), "\"")
  writeLines(c(yml("transactions_file", "transactions.csv"), yml("mode", mode),
               paste0("require_verification: ", tolower(as.character(require_verification))),
               yml("methodology_url", or_null(methodology_url, ""))),
             file.path(work, "params.yml"))
  # Quarto resolves --output against the working directory, so render from inside the work folder.
  old_wd <- setwd(work)
  on.exit(setwd(old_wd), add = TRUE)
  # With quiet = TRUE the log goes to a file, so a failure can still show its cause.
  log <- file.path(work, "quarto.log")
  status <- system2(bin, c("render", "transaction-report.qmd", "--to", "html", "--execute-params", "params.yml", "--output", shQuote(file)),
                    stdout = if (quiet) log else "", stderr = if (quiet) log else "")
  setwd(old_wd)
  out <- file.path(work, file)
  if (!identical(status, 0L) || !file.exists(out)) {
    tail_log <- if (quiet && file.exists(log)) utils::tail(readLines(log, warn = FALSE), 25) else character(0)
    stop("Quarto failed to render the report (exit status ", status, ")",
         if (length(tail_log)) paste0("; last lines of the log:\n", paste(tail_log, collapse = "\n")) else "; run with quiet = FALSE to see the log",
         call. = FALSE)
  }
  dest <- file.path(output_dir, file)
  file.copy(out, dest, overwrite = TRUE)
  invisible(normalizePath(dest))
}
