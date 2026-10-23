# Access to the factor tables. The package reads only its own copy of the
# tables (the data objects built by data-raw/factors.R), never the repository's
# data/factors/ folder.

#' The factor tables as one list
#'
#' Returns the six factor tables shipped with the package as a named list:
#' `effects`, `adjustments`, `baselines` (the baseline-disease table),
#' `exposure` (the baseline-exposure table), `pathways` and `schema`. Every
#' estimation function takes this list as its `tables` argument, so a user can
#' pass an edited copy (for example with a new effect row under review) without
#' touching the package.
#'
#' @return A named list of six tibbles.
#' @seealso [factors_version()], [effects], [adjustments], [pathways],
#'   [baseline_disease], [baseline_exposure], [factors_schema]
#' @export
#' @examples
#' tables <- factor_tables()
#' names(tables)
#' nrow(tables$effects)
factor_tables <- function() {
  list(
    effects = washhealth::effects,
    adjustments = washhealth::adjustments,
    baselines = washhealth::baseline_disease,
    exposure = washhealth::baseline_exposure,
    pathways = washhealth::pathways,
    schema = washhealth::factors_schema
  )
}

#' Version stamp of the factor tables
#'
#' The stamp is the date and short git hash of the last commit that changed
#' `data/factors/` in the tool repository when the package copy was built
#' (`data-raw/factors.R`). Every result and export carries it so that a
#' published number can be traced to the exact table rows.
#'
#' @return A single string such as `"2026-10-23-b6df8b7"`.
#' @export
#' @examples
#' factors_version()
factors_version <- function() {
  f <- system.file("extdata", "factors-version.txt", package = "washhealth")
  if (!nzchar(f)) return(NA_character_)
  trimws(readLines(f, warn = FALSE)[1])
}

#' Countries and output types the tables cover
#'
#' `countries()` lists the countries with their own baseline rows; other
#' countries can still be estimated with a `who_region` for the regional
#' fallback. `output_types()` lists the pathways with the output type label a
#' funder would use.
#'
#' @param tables The factor tables, see [factor_tables()].
#' @return `countries()` a character vector; `output_types()` a tibble with
#'   `pathway_id`, `output_type`, `unit_of_output` and `confidence_default`.
#' @export
#' @examples
#' countries()
#' output_types()
countries <- function(tables = factor_tables()) {
  b <- tables$baselines
  sort(unique(b$country[!grepl("^Region:", b$country) & b$iso3 != "GLOBAL"]))
}

#' @rdname countries
#' @export
output_types <- function(tables = factor_tables()) {
  p <- tables$pathways
  tibble::tibble(pathway_id = p$pathway_id, output_type = p$output_type,
                 unit_of_output = p$unit_of_output, confidence_default = p$confidence_default)
}

# Turn a pathway id or an output type label into the pathway id.
resolve_pathway <- function(x, tables = factor_tables()) {
  p <- tables$pathways
  if (is_blank(x)) stop("output_type is empty; choose one of: ", paste(p$output_type, collapse = "; "), call. = FALSE)
  key <- tolower(trimws(as.character(x)))
  i <- match(key, tolower(p$pathway_id))
  if (is.na(i)) i <- match(key, tolower(p$output_type))
  if (is.na(i)) stop("output type '", x, "' is not in the pathway table; choose one of: ",
                     paste(p$output_type, collapse = "; "), call. = FALSE)
  p$pathway_id[i]
}

#' Retrieve single rows from the factor tables
#'
#' These functions return one row (or one value) from the tables and stop with
#' a clear message when the row does not exist. The estimation chain uses them
#' for every number it needs.
#'
#' @param factor_id,adjustment_id,pathway_id Row identifiers as in the tables.
#' @param country Country name as in the baseline-disease table.
#' @param indicator Baseline indicator identifier (for example
#'   `"household_size"`, `"diarr_death_rate"`).
#' @param population_group `"all ages"` or `"under five"`.
#' @param who_region `"AFR"`, `"SEAR"` or `"WPR"` for a country that is not in
#'   the table; selects the regional fallback row.
#' @param service `"water"`, `"sanitation"` or `"hygiene"`.
#' @param level Service level as in the baseline-exposure table.
#' @param residence `"national"`, `"rural"` or `"urban"`.
#' @param tables The factor tables, see [factor_tables()].
#' @return `get_effect()`, `get_adjustment()`, `get_pathway()` a one-row
#'   tibble. `get_baseline()` a list with `value`, `low`, `high`, `row`,
#'   `fallback` (TRUE when the regional row was used) and `flag`.
#'   `get_exposure()` a number (percent) or NA. `get_exposure_row()` a one-row
#'   tibble or NULL. `who_region_of()` a region code.
#' @export
#' @examples
#' get_effect("F_POU_FILTER_FROM_UNIMP")[, c("factor_id", "central", "low", "high")]
#' get_adjustment("ADJ_USE_FILTER_REF")$value
#' get_baseline("Kenya", "household_size")$value
#' get_exposure("Cambodia", "sanitation", "at least basic", "rural")
get_effect <- function(factor_id, tables = factor_tables()) {
  row <- tables$effects[tables$effects$factor_id == factor_id, , drop = FALSE]
  if (nrow(row) != 1) stop("effect row not found: ", factor_id, call. = FALSE)
  row
}

#' @rdname get_effect
#' @export
get_adjustment <- function(adjustment_id, tables = factor_tables()) {
  row <- tables$adjustments[tables$adjustments$adjustment_id == adjustment_id, , drop = FALSE]
  if (nrow(row) != 1) stop("adjustment row not found: ", adjustment_id, call. = FALSE)
  row
}

#' @rdname get_effect
#' @export
get_pathway <- function(pathway_id, tables = factor_tables()) {
  row <- tables$pathways[tables$pathways$pathway_id == pathway_id, , drop = FALSE]
  if (nrow(row) != 1) stop("pathway not found: ", pathway_id, call. = FALSE)
  row
}

#' @rdname get_effect
#' @export
who_region_of <- function(country, who_region = NULL, tables = factor_tables()) {
  b <- tables$baselines
  r <- unique(b$who_region[b$country == country & !is.na(b$who_region)])
  r <- r[r != "GLOBAL"]
  if (length(r) >= 1) return(r[1])
  if (!is.null(who_region) && !is.na(who_region) && nzchar(who_region)) {
    if (!who_region %in% unique(b$iso3[grepl("^Region:", b$country)])) {
      stop("who_region '", who_region, "' has no regional rows; use one of ",
           paste(unique(b$iso3[grepl("^Region:", b$country)]), collapse = ", "), call. = FALSE)
    }
    return(who_region)
  }
  stop("Country '", country, "' is not in the baseline-disease table; pass who_region = 'AFR', 'SEAR' or 'WPR' for the regional fallback.", call. = FALSE)
}

#' @rdname get_effect
#' @export
get_baseline <- function(country, indicator, population_group = "all ages", who_region = NULL, tables = factor_tables()) {
  b <- tables$baselines
  row <- b[b$country == country & b$indicator == indicator & b$population_group == population_group, , drop = FALSE]
  fallback <- FALSE
  if (nrow(row) == 0 || all(is.na(row$value))) {
    region <- who_region_of(country, who_region, tables)
    row <- b[b$iso3 == region & b$indicator == indicator & b$population_group == population_group, , drop = FALSE]
    fallback <- TRUE
  }
  if (nrow(row) == 0 || all(is.na(row$value))) {
    return(list(value = NA_real_, low = NA_real_, high = NA_real_, row = NULL, fallback = fallback,
                flag = paste0("missing: no country or regional value for ", indicator, " (", population_group, ")")))
  }
  row <- row[1, , drop = FALSE]
  list(value = row$value, low = row$low, high = row$high, row = row, fallback = fallback,
       flag = if (fallback) paste0("regional substitute used for ", indicator, " (", population_group, "): ", row$flag) else row$flag)
}

#' @rdname get_effect
#' @export
get_exposure_row <- function(country, service, level, residence = "national", tables = factor_tables()) {
  x <- tables$exposure
  row <- x[x$country == country & x$service == service & x$level == level & x$residence == residence, , drop = FALSE]
  if (nrow(row) == 0) return(NULL)
  row[1, , drop = FALSE]
}

#' @rdname get_effect
#' @export
get_exposure <- function(country, service, level, residence = "national", tables = factor_tables()) {
  row <- get_exposure_row(country, service, level, residence, tables)
  if (is.null(row)) return(NA_real_)
  row$value
}

# ---- the factor ledger ----------------------------------------------------------

ledger_row <- function(table, id, what, value, low = NA, high = NA, citation = "", locator = "", flag = "") {
  tibble::tibble(table = table, id = as.character(id), what = what, value = as.numeric(value), low = as.numeric(low),
                 high = as.numeric(high), citation = as.character(citation), locator = as.character(locator), flag = as.character(flag))
}
empty_ledger <- function() ledger_row(character(), character(), character(), numeric(), numeric(), numeric(), character(), character(), character())
ledger_effect <- function(e) {
  ledger_row("effects", e$factor_id, paste0(e$measure, " ", e$exposure_from, " -> ", e$exposure_to, " (", e$outcome, ")"),
             e$central, e$low, e$high, e$source_citation, e$locator, e$certainty)
}
ledger_adjust <- function(a) ledger_row("adjustments", a$adjustment_id, a$parameter, a$value, a$low, a$high, a$source_citation, a$locator, a$evidence_grade)
ledger_baseline <- function(b, what = NULL) {
  r <- b$row
  if (is.null(r)) return(ledger_row("baseline-disease", NA, or_null(what, "missing"), NA, flag = b$flag))
  ledger_row("baseline-disease", r$baseline_id, paste0(r$indicator, " (", r$population_group, ", ", r$country, ", ", r$year, ")"),
             r$value, r$low, r$high, r$source, r$url, b$flag)
}
ledger_exposure <- function(r) {
  ledger_row("baseline-exposure", r$exposure_id, paste0(r$service, ": ", r$level, " (", r$residence, ", ", r$country, ", ", r$year, ")"),
             r$value, NA, NA, r$source, r$url, r$flag)
}
