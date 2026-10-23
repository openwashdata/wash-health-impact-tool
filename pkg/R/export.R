# Flat exports of the factor tables and of results, for Airtable, mWater,
# Excel or any other front end that wants the same numbers.

write_tables <- function(sets, path, format) {
  if (format == "xlsx") {
    if (!requireNamespace("writexl", quietly = TRUE)) stop("format = 'xlsx' needs the writexl package", call. = FALSE)
    sets <- lapply(sets, function(d) { for (col in names(d)) if (inherits(d[[col]], "Date")) d[[col]] <- format(d[[col]], "%Y-%m-%d"); as.data.frame(d) })
    names(sets) <- substr(names(sets), 1, 31)
    writexl::write_xlsx(sets, path)
    return(invisible(normalizePath(path)))
  }
  if (!dir.exists(path)) dir.create(path, recursive = TRUE)
  files <- character()
  for (nm in names(sets)) {
    f <- file.path(path, paste0(nm, ".csv"))
    utils::write.csv(as.data.frame(sets[[nm]]), f, row.names = FALSE, na = "", fileEncoding = "UTF-8")
    files <- c(files, f)
  }
  invisible(normalizePath(files))
}

# Long to wide: one row per combination of key columns, one column per name.
pivot_wide <- function(df, keys, name_col, value_col) {
  k <- unique(df[keys])
  rownames(k) <- NULL
  key_of <- function(d) do.call(paste, c(d[keys], sep = "\r"))
  kk <- key_of(k); dk <- key_of(df)
  names_ <- unique(df[[name_col]])
  out <- tibble::as_tibble(k)
  for (nm in names_) {
    sub <- df[df[[name_col]] == nm, , drop = FALSE]
    out[[nm]] <- sub[[value_col]][match(kk, dk[df[[name_col]] == nm])]
  }
  out
}

version_table <- function() {
  tibble::tibble(
    item = c("factors_version", "package", "package_version", "exported_on", "licence_tables", "licence_code", "rule"),
    value = c(factors_version(), "washhealth", as.character(utils::packageVersion("washhealth")), format(Sys.Date(), "%Y-%m-%d"),
              "CC BY 4.0", "MIT", "Retrieve, do not compute: every number traces to a row with a citation; keep the factors_version with every published number")
  )
}

#' One factor card per pathway and input case
#'
#' A flat table with one row per output type and input case (baseline source,
#' water quality verified, sanitation coverage above or below the threshold)
#' giving the effect row the chain would pick, its relative risk with
#' interval, the starting confidence label, the use reference, the decay value
#' and the PAF counterfactual. With this table a spreadsheet or Airtable
#' formula can reproduce the central estimate of the cases route; the label
#' logic and the ledger stay in R.
#'
#' @param tables The factor tables, see [factor_tables()].
#' @return A tibble.
#' @export
#' @examples
#' factor_cards()[, c("pathway_id", "baseline_source", "effect_row", "central", "certainty")]
factor_cards <- function(tables = factor_tables()) {
  p <- tables$pathways
  thr <- get_adjustment("ADJ_COV_SAN_THRESHOLD", tables)$value
  rows <- list()
  for (i in seq_len(nrow(p))) {
    pid <- p$pathway_id[i]
    sources <- if (p$paf_component[i] == "water") {
      opts <- trimws(strsplit(p$exposure_from_input[i], "|", fixed = TRUE)[[1]])
      c(if (any(grepl("unimproved", opts))) "unimproved", if (any(grepl("improved not on premises", opts))) "improved_not_on_premises")
    } else NA_character_
    if (length(sources) == 0) sources <- NA_character_
    quality <- if (pid == "P_CONN_HH") c(FALSE, TRUE) else FALSE
    coverage <- if (pid %in% c("P_SAN_BASIC", "P_CBS")) c("at or above threshold", "below threshold") else NA_character_
    use_id <- first_match(p$adjustment_ids[i], "ADJ_USE_[A-Z_]+")
    decay_id <- first_match(p$adjustment_ids[i], "ADJ_DECAY_[A-Z_]+")
    use_ref <- if (is.na(use_id)) NA_real_ else get_adjustment(use_id, tables)$value
    decay <- if (is.na(decay_id)) NA_real_ else get_adjustment(decay_id, tables)$value
    cf_id <- if (p$paf_component[i] %in% c("water", "sanitation", "hygiene")) paste0("ADJ_PAF_CF_", c(water = "WATER", sanitation = "SAN", hygiene = "HYG")[[p$paf_component[i]]]) else NA_character_
    cf <- if (is.na(cf_id)) NA_real_ else get_adjustment(cf_id, tables)$value
    for (bs in sources) for (wq in quality) for (cv in coverage) {
      cov_val <- if (is.na(cv)) NA_real_ else if (cv == "below threshold") thr / 2 else thr
      sel <- if (p$paf_component[i] == "none" || pid %in% c("P_CONN_INST", "P_FSM_EMPTYING")) list(row = NULL, flags = character()) else
        select_effect(pid, bs, wq, cov_val, TRUE, tables)
      e <- sel$row
      rows[[length(rows) + 1]] <- tibble::tibble(
        pathway_id = pid, output_type = p$output_type[i], unit_of_output = p$unit_of_output[i], paf_component = p$paf_component[i],
        baseline_source = bs, water_quality_verified = wq, sanitation_coverage = cv,
        effect_row = if (is.null(e)) NA_character_ else e$factor_id, measure = if (is.null(e)) NA_character_ else e$measure,
        central = if (is.null(e)) NA_real_ else e$central, low = if (is.null(e)) NA_real_ else e$low, high = if (is.null(e)) NA_real_ else e$high,
        risk_reduction_central = if (is.null(e)) NA_real_ else max(0, 1 - e$central),
        certainty = if (is.null(e)) "not estimable" else e$certainty,
        use_adjustment = use_id, use_reference = use_ref, decay_adjustment = decay_id, decay_after_year_one = decay,
        paf_counterfactual_adjustment = cf_id, paf_counterfactual_rr = cf,
        evidence_gap_flag = p$evidence_gap_flag[i], confidence_default = p$confidence_default[i],
        source_citation = if (is.null(e)) NA_character_ else e$source_citation, source_doi = if (is.null(e)) NA_character_ else e$source_doi,
        factors_version = factors_version()
      )
    }
  }
  rbind_rows(rows)
}

data_dictionary <- function(tables) {
  s <- tables$schema
  base <- tibble::tibble(table = s$table, column = s$column, type = s$type, description = s$description)
  b <- tables$baselines
  ind <- unique(b[c("indicator", "unit")])
  wide_d <- tibble::tibble(table = "baseline_disease_wide", column = c("country", "iso3", "who_region", "population_group", ind$indicator),
                           type = c("text", "text", "text", "text", rep("number", nrow(ind))),
                           description = c("Country name or Region: name", "ISO3 or region code", "WHO region", "all ages or under five",
                                           paste0("Value of the baseline indicator ", ind$indicator, " (", ind$unit, "); see baseline_disease for year, source, flag and derivation")))
  x <- tables$exposure
  lv <- unique(paste0(x$service, ": ", x$level))
  wide_x <- tibble::tibble(table = "baseline_exposure_wide", column = c("country", "iso3", "residence", lv),
                           type = c("text", "text", "text", rep("number", length(lv))),
                           description = c("Country name", "ISO3", "national, rural or urban",
                                           paste0("Share of the population (percent) at ", lv, "; see baseline_exposure for year, source and flag")))
  cards <- tibble::tibble(table = "factor_cards",
    column = c("pathway_id", "output_type", "unit_of_output", "paf_component", "baseline_source", "water_quality_verified", "sanitation_coverage",
               "effect_row", "measure", "central", "low", "high", "risk_reduction_central", "certainty", "use_adjustment", "use_reference",
               "decay_adjustment", "decay_after_year_one", "paf_counterfactual_adjustment", "paf_counterfactual_rr", "evidence_gap_flag",
               "confidence_default", "source_citation", "source_doi", "factors_version"),
    type = c("text", "text", "text", "text", "text", "logical", "text", "text", "text", "number", "number", "number", "number", "text", "text", "number",
             "text", "number", "text", "number", "text", "text", "text", "text", "text"),
    description = c("Pathway id", "Output type label", "What one unit is", "water, sanitation, hygiene or none",
                    "Customer baseline source the card applies to (water pathways)", "Whether water quality at the tap is verified (household connections)",
                    "Community sanitation coverage case (sanitation pathways)", "Effect row the chain picks for this case", "RR or OR",
                    "Point estimate of the effect", "Lower bound of its interval", "Upper bound of its interval", "1 minus the central RR, floored at zero",
                    "Starting confidence label (the effect row's certainty)", "Use adjustment row", "Reference adherence; use multiplier = min(1, verified use / reference)",
                    "Decay adjustment row", "Share of the year-one risk reduction kept in later years", "PAF counterfactual row", "Relative risk of the WHO counterfactual level",
                    "yes when the pathway rests on a proxy", "Pathway default label", "Citation of the effect row", "DOI of the effect row", "Factor table version stamp"))
  ver <- tibble::tibble(table = "version", column = c("item", "value"), type = c("text", "text"), description = c("Metadata item", "Its value"))
  rbind_rows(list(base, wide_d, wide_x, cards, ver))
}

#' Export the factor tables as flat files
#'
#' Writes every factor table as a flat table (CSV files in a folder, or one
#' Excel workbook with one sheet per table) so that an Airtable base, an
#' mWater form or a spreadsheet can be built on the same numbers. Includes the
#' long tables as they are, wide versions of the two baseline tables (one row
#' per country and group), the [factor_cards()] table, a data dictionary and a
#' version sheet with the factor table stamp.
#'
#' @param path For `format = "csv"` a folder (created if needed); for
#'   `format = "xlsx"` the workbook file name.
#' @param format `"csv"` or `"xlsx"` (needs the writexl package).
#' @param tables The factor tables, see [factor_tables()].
#' @return The file paths written, invisibly.
#' @export
#' @examples
#' dir <- file.path(tempdir(), "factors-export")
#' files <- export_factors(dir)
#' basename(files)
export_factors <- function(path, format = c("csv", "xlsx"), tables = factor_tables()) {
  format <- match.arg(format)
  b <- tables$baselines
  x <- tables$exposure
  x$service_level <- paste0(x$service, ": ", x$level)
  sets <- list(
    effects = tables$effects,
    adjustments = tables$adjustments,
    pathways = tables$pathways,
    baseline_disease = b,
    baseline_disease_wide = pivot_wide(b, c("country", "iso3", "who_region", "population_group"), "indicator", "value"),
    baseline_exposure = x[, setdiff(names(x), "service_level")],
    baseline_exposure_wide = pivot_wide(x, c("country", "iso3", "residence"), "service_level", "value"),
    factor_cards = factor_cards(tables),
    data_dictionary = data_dictionary(tables),
    version = version_table()
  )
  write_tables(sets, path, format)
}

#' Export results as flat files
#'
#' Writes the results, the ledger, the notes, the transactions as read, the
#' portfolio summary and a run sheet (factor table stamp, package version, run
#' time) as CSV files in a folder or as one Excel workbook.
#'
#' @param x A `washhealth_results` object from [estimate_transaction()] or
#'   [estimate_scenario()].
#' @inheritParams export_factors
#' @return The file paths written, invisibly.
#' @export
#' @examples
#' res <- estimate_transaction(example_transactions())
#' files <- export_results(res, file.path(tempdir(), "results-export"))
#' basename(files)
export_results <- function(x, path, format = c("csv", "xlsx")) {
  stopifnot(inherits(x, "washhealth_results"))
  format <- match.arg(format)
  tx <- x$transactions
  class(tx) <- setdiff(class(tx), "washhealth_transactions")
  run <- tibble::tibble(item = c("mode", "factors_version", "package_version", "run_time", "n_transactions", "n_output_rows", "rule"),
                        value = c(x$mode, x$factors_version, x$package_version, format(x$run_time, "%Y-%m-%d %H:%M:%S %Z"),
                                  as.character(length(unique(tx$transaction_id))), as.character(nrow(tx)),
                                  "All health numbers are estimates with ranges; outputs are verified, outcomes are modelled"))
  sets <- list(results = x$results, ledger = x$ledger, notes = x$notes, transactions = tx,
               portfolio = summarise_portfolio(x), run = run)
  write_tables(sets, path, format)
}
