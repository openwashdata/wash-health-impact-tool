# The transaction input schema, its validation, and the runners that turn a
# table of transactions into results (ex-post) or scenarios (ex-ante).

REQUIRED_COLUMNS <- c("transaction_id", "enterprise", "country", "output_type", "period_start", "period_end",
                      "quantity", "unit", "verified_by", "verification_date", "use_rate", "baseline_source",
                      "incentive_share", "notes")
OPTIONAL_COLUMNS <- c("residence", "community_coverage_after", "water_quality_verified", "people_per_unit",
                      "sth_prevalence", "promotion_contact", "who_region", "baseline_quantity", "baseline_method")

#' The transaction input schema
#'
#' `transaction_columns()` describes every column of the transaction table:
#' the 14 required columns of the template and the optional columns the chain
#' can use. `transaction_template_path()` returns the path of the CSV template
#' shipped with the package; `example_transactions()` returns the worked
#' examples (KWSH, Tap Effect, Aqua Clara, ATEC; counts partly illustrative).
#'
#' @return `transaction_columns()` a tibble with `column`, `required`, `type`,
#'   `description` and `allowed`; `transaction_template_path()` a path;
#'   `example_transactions()` a validated transaction table.
#' @export
#' @examples
#' transaction_columns()[, c("column", "required", "type")]
#' transaction_template_path()
#' example_transactions()[, c("transaction_id", "output_type", "quantity")]
transaction_columns <- function() {
  tibble::tibble(
    column = c(REQUIRED_COLUMNS, OPTIONAL_COLUMNS),
    required = c(rep(TRUE, length(REQUIRED_COLUMNS)), rep(FALSE, length(OPTIONAL_COLUMNS))),
    type = c("text", "text", "text", "text", "date", "date", "number", "text", "text", "date", "share", "text", "share", "text",
             "text", "share", "logical", "number", "share", "logical", "text", "number", "text"),
    description = c(
      "Identifier of the transaction (contract or SIINC id); one transaction may have several output rows",
      "Enterprise name",
      "Country of the customers; one of countries(), or any country with who_region set",
      "Output type: a pathway id or the output type label from output_types()",
      "First day of the reporting or planning period (YYYY-MM-DD)",
      "Last day of the period (YYYY-MM-DD); the period length sets the years of service counted",
      "Number of output units in the period (verified ex-post; planned ex-ante)",
      "Unit of the output as reported (free text; the pathway's unit_of_output is the reference)",
      "Who verified the quantity (ex-post: required)",
      "Date of the verification (YYYY-MM-DD; ex-post: required)",
      "Share of units verified in use (0 to 1); empty means not verified (label drops one step). Ex-ante: the target share",
      "Baseline water source of the customers: unimproved or improved_not_on_premises; empty means assumed unimproved with a flag",
      "Share (0 to 1) of the outputs attributable to the incentive, set ex-ante from the baseline trajectory; empty means attributable rows stay empty",
      "Free text: data sources, assumptions, what is illustrative",
      "national, rural or urban (default national)",
      "Share (0 to 1) of households in the service area with at least basic sanitation after the installations; empty means the JMP value with a flag",
      "TRUE when water at the tap is verified free of E. coli (household connections)",
      "Persons per unit when the enterprise reports it; required for institutional connections and MHH outputs",
      "Local STH prevalence (0 to 1) if known",
      "TRUE when a hygiene product came with at least one promotion contact",
      "AFR, SEAR or WPR for a country outside the baseline table",
      "Units the enterprise would have delivered without the incentive (baseline trajectory); sets incentive_share when that is empty",
      "How the baseline trajectory was set: pre-incentive trend, comparable-enterprise benchmark or contract target (with a reason)"
    ),
    allowed = c("", "", "countries() or any with who_region", "output_types()", "YYYY-MM-DD", "YYYY-MM-DD", ">= 0", "",
                "", "YYYY-MM-DD", "0 to 1", "unimproved | improved_not_on_premises", "0 to 1", "",
                "national | rural | urban", "0 to 1", "TRUE | FALSE", "> 0", "0 to 1", "TRUE | FALSE", "AFR | SEAR | WPR", ">= 0", "")
  )
}

#' @rdname transaction_columns
#' @export
transaction_template_path <- function() system.file("extdata", "transaction-template.csv", package = "washhealth")

#' @rdname transaction_columns
#' @export
example_transactions <- function() read_transactions(system.file("extdata", "transactions-examples.csv", package = "washhealth"))

#' Read and validate a transaction table
#'
#' `read_transactions()` reads a CSV file in the template format (see
#' [transaction_template_path()]) and validates it. `as_transactions()` does
#' the same for a data frame already in memory. Validation checks the required
#' columns, known output types and countries, dates, and that shares lie
#' between 0 and 1. All problems are reported in one message.
#'
#' @param path Path to a CSV file.
#' @param x A data frame with the template columns, or a path.
#' @param tables The factor tables, see [factor_tables()].
#' @return A tibble of class `washhealth_transactions` with typed columns, the
#'   optional columns filled in, and two derived columns: `pathway_id` and
#'   `service_years` (period length in years, rounded to two decimals so that a
#'   calendar year counts as 1).
#' @export
#' @examples
#' tx <- read_transactions(transaction_template_path())
#' tx[, c("transaction_id", "pathway_id", "quantity", "service_years")]
read_transactions <- function(path, tables = factor_tables()) {
  if (!file.exists(path)) stop("file not found: ", path, call. = FALSE)
  df <- utils::read.csv(path, colClasses = "character", encoding = "UTF-8", check.names = FALSE,
                        na.strings = character(), strip.white = TRUE)
  validate_transactions(df, tables)
}

#' @rdname read_transactions
#' @export
as_transactions <- function(x, tables = factor_tables()) {
  if (inherits(x, "washhealth_transactions")) return(x)
  if (is.character(x) && length(x) == 1) return(read_transactions(x, tables))
  if (!is.data.frame(x)) stop("transactions must be a data frame or a path to a CSV file", call. = FALSE)
  validate_transactions(x, tables)
}

#' Build a one-row transaction table
#'
#' A convenience for scripts and the app: builds one row in the template
#' format from named arguments and validates it.
#'
#' @param transaction_id,enterprise,country,output_type,quantity,period_start,period_end
#'   Required fields, see [transaction_columns()].
#' @param unit,verified_by,verification_date,use_rate,baseline_source,incentive_share,notes
#'   Template fields; empty or NA when unknown.
#' @param residence,community_coverage_after,water_quality_verified,people_per_unit,sth_prevalence,promotion_contact,who_region,baseline_quantity,baseline_method
#'   Optional fields.
#' @param tables The factor tables, see [factor_tables()].
#' @return A validated one-row transaction table.
#' @export
#' @examples
#' new_transaction("TX-1", "Example Co", "Kenya", "household water filter", 1000,
#'                 "2026-01-01", "2026-12-31", use_rate = 0.9, incentive_share = 0.4,
#'                 verified_by = "Verifier", verification_date = "2027-01-15")
new_transaction <- function(transaction_id, enterprise, country, output_type, quantity, period_start, period_end,
                            unit = NA, verified_by = NA, verification_date = NA, use_rate = NA, baseline_source = NA,
                            incentive_share = NA, notes = NA, residence = "national", community_coverage_after = NA,
                            water_quality_verified = NA, people_per_unit = NA, sth_prevalence = NA, promotion_contact = NA,
                            who_region = NA, baseline_quantity = NA, baseline_method = NA, tables = factor_tables()) {
  chr <- function(v) if (is.null(v) || length(v) == 0 || is.na(v)) "" else as.character(v)
  df <- data.frame(
    transaction_id = chr(transaction_id), enterprise = chr(enterprise), country = chr(country), output_type = chr(output_type),
    period_start = chr(period_start), period_end = chr(period_end), quantity = chr(quantity), unit = chr(unit),
    verified_by = chr(verified_by), verification_date = chr(verification_date), use_rate = chr(use_rate),
    baseline_source = chr(baseline_source), incentive_share = chr(incentive_share), notes = chr(notes),
    residence = chr(residence), community_coverage_after = chr(community_coverage_after),
    water_quality_verified = chr(water_quality_verified), people_per_unit = chr(people_per_unit),
    sth_prevalence = chr(sth_prevalence), promotion_contact = chr(promotion_contact), who_region = chr(who_region),
    baseline_quantity = chr(baseline_quantity), baseline_method = chr(baseline_method), stringsAsFactors = FALSE
  )
  validate_transactions(df, tables)
}

validate_transactions <- function(df, tables = factor_tables()) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  names(df) <- trimws(names(df))
  problems <- character()
  missing_cols <- setdiff(REQUIRED_COLUMNS, names(df))
  if (length(missing_cols)) {
    stop("Transaction table is missing required columns: ", paste(missing_cols, collapse = ", "),
         ". The template is at transaction_template_path().", call. = FALSE)
  }
  for (col in OPTIONAL_COLUMNS) if (!col %in% names(df)) df[[col]] <- ""
  unknown <- setdiff(names(df), c(REQUIRED_COLUMNS, OPTIONAL_COLUMNS))
  if (length(unknown)) message("Columns kept but not used by the chain: ", paste(unknown, collapse = ", "))
  if (nrow(df) == 0) stop("Transaction table has no rows", call. = FALSE)
  for (col in c(REQUIRED_COLUMNS, OPTIONAL_COLUMNS)) {
    v <- df[[col]]
    v[is.na(v)] <- ""
    df[[col]] <- trimws(as.character(v))
  }

  known_countries <- countries(tables)
  regions <- unique(tables$baselines$iso3[grepl("^Region:", tables$baselines$country)])
  types <- output_types(tables)
  n <- nrow(df)
  out <- tibble::tibble(
    transaction_id = df$transaction_id, enterprise = df$enterprise, country = df$country, output_type = df$output_type,
    period_start = as.Date(rep(NA, n)), period_end = as.Date(rep(NA, n)), quantity = rep(NA_real_, n), unit = df$unit,
    verified_by = df$verified_by, verification_date = as.Date(rep(NA, n)), use_rate = rep(NA_real_, n),
    baseline_source = rep(NA_character_, n), incentive_share = rep(NA_real_, n), notes = df$notes,
    residence = rep("national", n), community_coverage_after = rep(NA_real_, n), water_quality_verified = rep(NA, n),
    people_per_unit = rep(NA_real_, n), sth_prevalence = rep(NA_real_, n), promotion_contact = rep(NA, n),
    who_region = rep(NA_character_, n), baseline_quantity = rep(NA_real_, n), baseline_method = df$baseline_method,
    pathway_id = rep(NA_character_, n), service_years = rep(NA_real_, n)
  )
  share <- function(i, col, label) {
    v <- parse_number(df[[col]][i])
    if (is_blank(df[[col]][i])) return(NA_real_)
    if (is.na(v)) { problems <<- c(problems, sprintf("row %d: %s '%s' is not a number", i, col, df[[col]][i])); return(NA_real_) }
    if (v < 0 || v > 1) { problems <<- c(problems, sprintf("row %d: %s must be a share between 0 and 1, not %s (a percentage must be divided by 100)", i, col, df[[col]][i])); return(NA_real_) }
    v
  }
  for (i in seq_len(n)) {
    where <- sprintf("row %d", i)
    if (is_blank(df$transaction_id[i])) problems <- c(problems, paste0(where, ": transaction_id is empty"))
    if (is_blank(df$enterprise[i])) problems <- c(problems, paste0(where, ": enterprise is empty"))
    # country
    if (is_blank(df$country[i])) {
      problems <- c(problems, paste0(where, ": country is empty"))
    } else if (!df$country[i] %in% known_countries) {
      if (is_blank(df$who_region[i])) {
        problems <- c(problems, sprintf("%s: country '%s' is not in the baseline table (known: %s); add who_region (%s) for the regional fallback",
                                        where, df$country[i], paste(known_countries, collapse = ", "), paste(regions, collapse = ", ")))
      } else if (!toupper(df$who_region[i]) %in% regions) {
        problems <- c(problems, sprintf("%s: who_region '%s' is not one of %s", where, df$who_region[i], paste(regions, collapse = ", ")))
      } else out$who_region[i] <- toupper(df$who_region[i])
    }
    # output type
    pid <- tryCatch(resolve_pathway(df$output_type[i], tables), error = function(e) NA_character_)
    if (is.na(pid)) {
      problems <- c(problems, sprintf("%s: output_type '%s' is not known; use one of: %s", where, df$output_type[i], paste(types$output_type, collapse = "; ")))
    } else out$pathway_id[i] <- pid
    # period
    ps <- parse_date(df$period_start[i]); pe <- parse_date(df$period_end[i])
    if (is.na(ps)) problems <- c(problems, sprintf("%s: period_start '%s' is not a date (YYYY-MM-DD)", where, df$period_start[i]))
    if (is.na(pe)) problems <- c(problems, sprintf("%s: period_end '%s' is not a date (YYYY-MM-DD)", where, df$period_end[i]))
    if (!is.na(ps) && !is.na(pe)) {
      if (pe < ps) problems <- c(problems, sprintf("%s: period_end is before period_start", where))
      out$period_start[i] <- ps; out$period_end[i] <- pe
      out$service_years[i] <- round(as.numeric(pe - ps + 1) / 365.25, 2) # a calendar year counts as 1
    }
    # quantity
    q <- parse_number(df$quantity[i])
    if (is.na(q)) problems <- c(problems, sprintf("%s: quantity '%s' is not a number", where, df$quantity[i]))
    else if (q < 0) problems <- c(problems, sprintf("%s: quantity must be zero or more", where))
    else out$quantity[i] <- q
    if (is_blank(df$unit[i]) && !is.na(pid)) out$unit[i] <- types$unit_of_output[types$pathway_id == pid]
    # verification date
    if (!is_blank(df$verification_date[i])) {
      vd <- parse_date(df$verification_date[i])
      if (is.na(vd)) problems <- c(problems, sprintf("%s: verification_date '%s' is not a date (YYYY-MM-DD)", where, df$verification_date[i]))
      else out$verification_date[i] <- vd
    }
    # shares
    out$use_rate[i] <- share(i, "use_rate", "use_rate")
    out$incentive_share[i] <- share(i, "incentive_share", "incentive_share")
    out$community_coverage_after[i] <- share(i, "community_coverage_after", "community_coverage_after")
    out$sth_prevalence[i] <- share(i, "sth_prevalence", "sth_prevalence")
    # baseline source
    if (!is_blank(df$baseline_source[i])) {
      bs <- tolower(gsub("[ -]+", "_", df$baseline_source[i]))
      if (bs %in% c("unimproved", "surface_water", "unimproved_or_surface_water")) out$baseline_source[i] <- "unimproved"
      else if (bs %in% c("improved_not_on_premises", "improved_off_premises", "improved")) out$baseline_source[i] <- "improved_not_on_premises"
      else problems <- c(problems, sprintf("%s: baseline_source '%s' must be 'unimproved' or 'improved_not_on_premises' (or empty)", where, df$baseline_source[i]))
    }
    # residence
    if (!is_blank(df$residence[i])) {
      r <- tolower(df$residence[i])
      if (!r %in% c("national", "rural", "urban")) problems <- c(problems, sprintf("%s: residence '%s' must be national, rural or urban", where, df$residence[i]))
      else out$residence[i] <- r
    }
    # logicals
    for (col in c("water_quality_verified", "promotion_contact")) {
      if (!is_blank(df[[col]][i])) {
        f <- parse_flag(df[[col]][i])
        if (is.na(f)) problems <- c(problems, sprintf("%s: %s '%s' must be TRUE or FALSE", where, col, df[[col]][i]))
        else out[[col]][i] <- f
      }
    }
    # people per unit
    if (!is_blank(df$people_per_unit[i])) {
      p <- parse_number(df$people_per_unit[i])
      if (is.na(p) || p <= 0) problems <- c(problems, sprintf("%s: people_per_unit '%s' must be a number above zero", where, df$people_per_unit[i]))
      else out$people_per_unit[i] <- p
    }
    if (!is.na(pid) && pid %in% REQUIRES_PEOPLE_PER_UNIT && is.na(out$people_per_unit[i])) {
      problems <- c(problems, sprintf("%s: output type '%s' needs people_per_unit (users per institution or water point, or girls and women reached per unit)", where, df$output_type[i]))
    }
    # baseline quantity -> incentive share
    if (!is_blank(df$baseline_quantity[i])) {
      b <- parse_number(df$baseline_quantity[i])
      if (is.na(b) || b < 0) problems <- c(problems, sprintf("%s: baseline_quantity '%s' must be a number of zero or more", where, df$baseline_quantity[i]))
      else {
        out$baseline_quantity[i] <- b
        if (is.na(out$incentive_share[i]) && !is.na(out$quantity[i]) && out$quantity[i] > 0) {
          out$incentive_share[i] <- max(0, 1 - b / out$quantity[i])
        }
      }
    }
  }
  if (length(problems)) {
    stop("Transaction table has ", length(problems), " problem", if (length(problems) > 1) "s" else "", ":\n",
         paste0("- ", problems, collapse = "\n"), call. = FALSE)
  }
  dup <- duplicated(out[c("transaction_id", "pathway_id", "period_start", "period_end")])
  if (any(dup)) warning("Duplicate rows (same transaction, output type and period): ", paste(unique(out$transaction_id[dup]), collapse = ", "), call. = FALSE)
  class(out) <- c("washhealth_transactions", class(out))
  out
}

# ---- runners ------------------------------------------------------------------

#' Estimate health outcomes for a table of transactions
#'
#' `estimate_transaction()` is the ex-post run: it takes verified outputs and
#' returns estimated outcomes for each row, in total and for the
#' incentive-attributable share. `estimate_scenario()` is the ex-ante run: the
#' same table with planned quantities and a target use rate; results are
#' labelled as planned. Both call [estimate_output()] once per row and keep
#' the ledger of factor rows for every row.
#'
#' @param transactions A transaction table ([read_transactions()],
#'   [as_transactions()], [new_transaction()]), a data frame in the template
#'   format, or a path to a CSV file.
#' @param require_verification Ex-post only. When TRUE (the default) every row
#'   needs `verified_by` and `verification_date`; when FALSE a missing
#'   verification adds the flag `output_not_verified` and lowers the label.
#' @param tables The factor tables, see [factor_tables()].
#' @return An object of class `washhealth_results`: a list with `results` (one
#'   row per transaction, scope and outcome with `low`, `central`, `high`,
#'   `confidence` and `flags`), `ledger` (every factor row used, with
#'   citations), `notes`, `transactions`, `estimates` (the
#'   [estimate_output()] objects), `mode`, `factors_version`,
#'   `package_version` and `run_time`.
#' @seealso [summarise_portfolio()], [export_results()],
#'   [render_transaction_report()], [check_ledger()]
#' @export
#' @examples
#' res <- estimate_transaction(example_transactions())
#' res
#' summarise_portfolio(res)
#'
#' plan <- new_transaction("PLAN-1", "Example Co", "Kenya", "household water filter", 2000,
#'                         "2027-01-01", "2027-12-31", use_rate = 0.9, baseline_quantity = 1200)
#' estimate_scenario(plan)$results[, c("scope", "outcome", "population_group", "central")]
estimate_transaction <- function(transactions, require_verification = TRUE, tables = factor_tables()) {
  run_rows(as_transactions(transactions, tables), mode = "ex-post", require_verification = require_verification, tables = tables)
}

#' @rdname estimate_transaction
#' @export
estimate_scenario <- function(transactions, tables = factor_tables()) {
  run_rows(as_transactions(transactions, tables), mode = "ex-ante", require_verification = FALSE, tables = tables)
}

run_rows <- function(tx, mode, require_verification, tables) {
  scope_total <- if (mode == "ex-post") "verified total" else "planned total"
  results <- list(); ledger <- list(); notes <- list(); estimates <- list()
  for (i in seq_len(nrow(tx))) {
    r <- tx[i, ]
    extra_flags <- character()
    extra_notes <- character()
    if (mode == "ex-post") {
      if (is_blank(r$verified_by) || is.na(r$verification_date)) {
        if (require_verification) {
          stop("row ", i, " (", r$transaction_id, "): an ex-post run needs verified_by and verification_date; ",
               "use estimate_scenario() for planned outputs or require_verification = FALSE", call. = FALSE)
        }
        extra_flags <- c(extra_flags, "output_not_verified")
        extra_notes <- c(extra_notes, "The output quantity was not verified by a third party; the label dropped one step.")
      }
    } else if (!is.na(r$use_rate)) {
      extra_flags <- c(extra_flags, "use_is_target")
      extra_notes <- c(extra_notes, "Ex-ante run: the use rate is a target to be verified, not a verified value.")
    }
    est <- estimate_output(r$pathway_id, units = r$quantity, country = r$country, residence = r$residence,
                           baseline_source = r$baseline_source, verified_use = r$use_rate, years = r$service_years,
                           community_coverage_after = r$community_coverage_after,
                           water_quality_verified = isTRUE(r$water_quality_verified), people_per_unit = r$people_per_unit,
                           sth_prevalence = r$sth_prevalence, promotion_contact = r$promotion_contact,
                           who_region = if (is.na(r$who_region)) NULL else r$who_region, tables = tables)
    confidence <- est$confidence
    if ("output_not_verified" %in% extra_flags) confidence <- step_down(confidence)
    if (is.na(r$incentive_share)) {
      extra_flags <- c(extra_flags, "incentive_share_missing")
      extra_notes <- c(extra_notes, "No incentive-attributable share was given; the attributable rows are empty.")
    }
    flags <- unique(c(est$flags, extra_flags))
    est$flags <- flags; est$confidence <- confidence; est$notes <- c(est$notes, extra_notes)
    estimates[[i]] <- est
    hd <- tibble::tibble(transaction_id = r$transaction_id, enterprise = r$enterprise, country = r$country,
                         output_type = est$pathway$output_type, pathway_id = r$pathway_id,
                         period_start = r$period_start, period_end = r$period_end, quantity = r$quantity, unit = r$unit)
    s <- rbind_rows(list(est$summary, est$per_household_year))
    body <- function(scope, mult, rows) {
      tibble::tibble(hd[rep(1, nrow(rows)), ], scope = scope, outcome = rows$outcome, population_group = rows$population_group,
                     low = rows$low * mult, central = rows$central * mult, high = rows$high * mult, result_unit = rows$unit,
                     route = rows$route, confidence = confidence, flags = paste(flags, collapse = "; "))
    }
    total <- body(scope_total, 1, s)
    attributable <- body("incentive-attributable", if (is.na(r$incentive_share)) NA_real_ else r$incentive_share, est$summary)
    results[[i]] <- rbind_rows(list(total, attributable))
    lg <- est$factors_used
    ledger[[i]] <- tibble::tibble(transaction_id = rep(r$transaction_id, nrow(lg)), output_type = rep(est$pathway$output_type, nrow(lg)), lg)
    notes[[i]] <- tibble::tibble(transaction_id = r$transaction_id, output_type = est$pathway$output_type, note = est$notes)
  }
  structure(list(results = rbind_rows(results), ledger = rbind_rows(ledger), notes = rbind_rows(notes), transactions = tx,
                 estimates = estimates, mode = mode, factors_version = factors_version(),
                 package_version = as.character(utils::packageVersion("washhealth")), run_time = Sys.time()),
            class = "washhealth_results")
}

step_down <- function(label) {
  if (!label %in% CONFIDENCE_LEVELS) return(label)
  CONFIDENCE_LEVELS[min(match(label, CONFIDENCE_LEVELS) + 1, length(CONFIDENCE_LEVELS))]
}

#' @export
print.washhealth_results <- function(x, ...) {
  cat("washhealth results (", x$mode, "): ", length(unique(x$results$transaction_id)), " transaction(s), ",
      nrow(x$transactions), " output row(s); factor tables ", x$factors_version, "\n", sep = "")
  r <- x$results[!grepl("per household-year", x$results$outcome), c("transaction_id", "output_type", "scope", "outcome", "population_group", "low", "central", "high", "confidence")]
  for (col in c("low", "central", "high")) r[[col]] <- signif(r[[col]], 3)
  print(r, n = 40)
  invisible(x)
}

#' Add results up across transactions
#'
#' Sums the low, central and high values of every outcome across the rows of a
#' results object, by scope, outcome and population group (or any other set of
#' result columns). Low and high values are summed as they are, which treats
#' the transactions as fully correlated; the range is therefore wide rather
#' than narrow. The confidence label of a sum is the worst label among its
#' rows. Per household-year rates are left out.
#'
#' @param x A `washhealth_results` object.
#' @param by Columns of `x$results` to group by.
#' @return A tibble with the grouping columns, `n_outputs`, `n_transactions`,
#'   `n_missing` (rows with no value, for example attributable rows without a
#'   share), `low`, `central`, `high`, `result_unit` and `confidence`.
#' @export
#' @examples
#' res <- estimate_transaction(example_transactions())
#' summarise_portfolio(res)
#' summarise_portfolio(res, by = c("enterprise", "scope", "outcome", "population_group"))
summarise_portfolio <- function(x, by = c("scope", "outcome", "population_group")) {
  stopifnot(inherits(x, "washhealth_results"))
  r <- x$results[!grepl("per household-year", x$results$outcome), , drop = FALSE]
  missing_by <- setdiff(by, names(r))
  if (length(missing_by)) stop("not result columns: ", paste(missing_by, collapse = ", "), call. = FALSE)
  key <- do.call(paste, c(r[by], sep = "\r"))
  groups <- split(seq_len(nrow(r)), factor(key, levels = unique(key)))
  rows <- lapply(groups, function(idx) {
    g <- r[idx, , drop = FALSE]
    tibble::tibble(g[1, by, drop = FALSE], n_outputs = nrow(g), n_transactions = length(unique(g$transaction_id)),
                   n_missing = sum(is.na(g$central)), low = sum(g$low, na.rm = TRUE), central = sum(g$central, na.rm = TRUE),
                   high = sum(g$high, na.rm = TRUE), result_unit = g$result_unit[1], confidence = worst_label(g$confidence))
  })
  rbind_rows(rows)
}

#' Check that every ledger row resolves to a factor table row
#'
#' For each row of the ledger (`factors_used` of an estimate, or `ledger` of a
#' results object) looks up the id in the named table and compares the
#' citation. Use it before publishing numbers, and after a factor table update
#' to see which past results touch changed rows.
#'
#' @param x A `washhealth_estimate` or `washhealth_results` object, or a
#'   ledger tibble.
#' @param tables The factor tables, see [factor_tables()].
#' @return A tibble with `table`, `id`, `found` (TRUE, FALSE, or NA for a
#'   missing-value marker without an id) and `citation_matches`.
#' @export
#' @examples
#' est <- estimate_output("P_POU_FILTER", 100, "Kenya",
#'   baseline_source = "unimproved", verified_use = 0.9)
#' chk <- check_ledger(est)
#' all(chk$found & chk$citation_matches, na.rm = TRUE)
check_ledger <- function(x, tables = factor_tables()) {
  lg <- if (inherits(x, "washhealth_estimate")) x$factors_used else if (inherits(x, "washhealth_results")) x$ledger else x
  lookup <- list(
    "effects" = list(tbl = tables$effects, id = "factor_id", cite = "source_citation"),
    "adjustments" = list(tbl = tables$adjustments, id = "adjustment_id", cite = "source_citation"),
    "baseline-disease" = list(tbl = tables$baselines, id = "baseline_id", cite = "source"),
    "baseline-exposure" = list(tbl = tables$exposure, id = "exposure_id", cite = "source")
  )
  found <- logical(nrow(lg)); cites <- logical(nrow(lg))
  for (i in seq_len(nrow(lg))) {
    if (is.na(lg$id[i])) { found[i] <- NA; cites[i] <- NA; next }
    l <- lookup[[lg$table[i]]]
    if (is.null(l)) { found[i] <- FALSE; cites[i] <- FALSE; next }
    j <- match(lg$id[i], l$tbl[[l$id]])
    found[i] <- !is.na(j)
    cites[i] <- !is.na(j) && identical(as.character(l$tbl[[l$cite]][j]), as.character(lg$citation[i]))
  }
  tibble::tibble(table = lg$table, id = lg$id, found = found, citation_matches = cites)
}
