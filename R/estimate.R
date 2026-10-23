# Estimation chain of the WASH health impact tool (stage 2, function set, not yet a package).
#
# Every number the chain uses is a row in data/factors/*.csv. The functions here
# retrieve rows and do arithmetic on them; they never hold a factor of their own.
# Each result returns the list of rows it used, with citations, so a reader can
# check every step.
#
# Source with: source("R/estimate.R"); tables <- load_factors("data/factors")

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(purrr)
  library(stringr)
})

# ---- loading ----------------------------------------------------------------

load_factors <- function(dir = "data/factors") {
  rd <- function(f) read_csv(file.path(dir, f), show_col_types = FALSE, col_types = cols(.default = col_character()))
  num <- function(x, cols) mutate(x, across(all_of(cols), ~ suppressWarnings(as.numeric(.x))))
  list(
    effects = num(rd("effects.csv"), c("central", "low", "high")),
    adjustments = num(rd("adjustments.csv"), c("value", "low", "high")),
    baselines = num(rd("baseline-disease.csv"), c("value", "low", "high")) %>% mutate(year = as.integer(year)),
    exposure = num(rd("baseline-exposure.csv"), c("value")) %>% mutate(year = as.integer(year)),
    pathways = rd("pathways.csv"),
    schema = rd("factors-schema.csv")
  )
}

CONFIDENCE_LEVELS <- c("high", "moderate", "low", "very low")

# ---- retrieval ----------------------------------------------------------------

#' Find the WHO region of a country from the baseline table, or use the one given.
who_region_of <- function(tables, country, who_region = NULL) {
  r <- tables$baselines %>% filter(country == !!country, !is.na(who_region)) %>% pull(who_region) %>% unique()
  if (length(r) >= 1) return(r[1])
  if (!is.null(who_region)) return(who_region)
  stop("Country '", country, "' is not in baseline-disease.csv; pass who_region = 'AFR', 'SEAR' or 'WPR' for the regional fallback.")
}

#' Retrieve one baseline value for a country, falling back to the regional row with a flag.
get_baseline <- function(tables, country, indicator, population_group = "all ages", who_region = NULL) {
  b <- tables$baselines
  row <- b %>% filter(country == !!country, indicator == !!indicator, population_group == !!population_group)
  fallback <- FALSE
  if (nrow(row) == 0 || all(is.na(row$value))) {
    region <- who_region_of(tables, country, who_region)
    row <- b %>% filter(iso3 == region, indicator == !!indicator, population_group == !!population_group)
    fallback <- TRUE
  }
  if (nrow(row) == 0 || all(is.na(row$value))) {
    return(list(value = NA_real_, low = NA_real_, high = NA_real_, row = NULL, fallback = fallback,
                flag = paste0("missing: no country or regional value for ", indicator, " (", population_group, ")")))
  }
  row <- row[1, ]
  list(value = row$value, low = row$low, high = row$high, row = row, fallback = fallback,
       flag = if (fallback) paste0("regional substitute used for ", indicator, " (", population_group, "): ", row$flag) else row$flag)
}

get_effect <- function(tables, factor_id) {
  row <- tables$effects %>% filter(factor_id == !!factor_id)
  if (nrow(row) != 1) stop("effect row not found: ", factor_id)
  row
}

get_adjustment <- function(tables, adjustment_id) {
  row <- tables$adjustments %>% filter(adjustment_id == !!adjustment_id)
  if (nrow(row) != 1) stop("adjustment row not found: ", adjustment_id)
  row
}

get_pathway <- function(tables, pathway_id) {
  row <- tables$pathways %>% filter(pathway_id == !!pathway_id)
  if (nrow(row) != 1) stop("pathway not found: ", pathway_id)
  row
}

#' Retrieve the share of the population at one service level (percent), national, urban or rural.
get_exposure <- function(tables, country, service, level, residence = "national") {
  row <- tables$exposure %>% filter(country == !!country, service == !!service, level == !!level, residence == !!residence)
  if (nrow(row) == 0) return(NA_real_)
  row$value[1]
}

# ---- the factor ledger --------------------------------------------------------

ledger_row <- function(table, id, what, value, low = NA, high = NA, citation = "", locator = "", flag = "") {
  tibble(table = table, id = id, what = what, value = as.numeric(value), low = as.numeric(low), high = as.numeric(high),
         citation = citation, locator = locator, flag = flag)
}
ledger_effect <- function(e) ledger_row("effects", e$factor_id, paste0(e$measure, " ", e$exposure_from, " -> ", e$exposure_to, " (", e$outcome, ")"),
                                        e$central, e$low, e$high, e$source_citation, e$locator, e$certainty)
ledger_adjust <- function(a) ledger_row("adjustments", a$adjustment_id, a$parameter, a$value, a$low, a$high, a$source_citation, a$locator, a$evidence_grade)
ledger_baseline <- function(b, what = NULL) {
  r <- b$row
  if (is.null(r)) return(ledger_row("baseline-disease", NA, what %||% "missing", NA, flag = b$flag))
  ledger_row("baseline-disease", r$baseline_id, paste0(r$indicator, " (", r$population_group, ", ", r$country, ", ", r$year, ")"),
             r$value, r$low, r$high, r$source, r$url, b$flag)
}
`%||%` <- function(a, b) if (is.null(a)) b else a
floor0 <- function(x) { x[!is.na(x) & x < 0] <- 0; x } # keeps names, unlike pmax(0, x)

# ---- confidence labels --------------------------------------------------------

#' Confidence label rule set: start from the pathway or effect certainty and drop one step per downgrade flag.
#' Downgrade flags: use_not_verified, regional_substitute, decay_proxy, decay_missing, evidence_gap,
#' coverage_below_threshold, baseline_source_assumed, interval_not_available, later_years_unquantified.
#' Note flags (no downgrade): reporting_bias, interval_includes_no_effect.
label_confidence <- function(start, flags = character()) {
  downgrade_flags <- c("use_not_verified", "regional_substitute", "decay_proxy", "decay_missing", "evidence_gap",
                       "coverage_below_threshold", "baseline_source_assumed", "interval_not_available", "later_years_unquantified")
  if (is.na(start) || !start %in% CONFIDENCE_LEVELS) return("not estimable")
  n <- sum(unique(flags) %in% downgrade_flags)
  i <- min(match(start, CONFIDENCE_LEVELS) + n, length(CONFIDENCE_LEVELS))
  CONFIDENCE_LEVELS[i]
}

# ---- effect row selection -----------------------------------------------------

#' Choose the effect row for a pathway from the user's inputs; returns the row plus flags.
select_effect <- function(tables, pathway_id, baseline_source, water_quality_verified, community_coverage_after, promotion_contact) {
  flags <- character()
  from_improved <- identical(baseline_source, "improved_not_on_premises")
  id <- switch(pathway_id,
    P_CONN_HH = if (isTRUE(water_quality_verified)) { if (from_improved) "F_WAT_PREMHQ_FROM_IMPNP" else "F_WAT_PREMHQ_FROM_UNIMP" } else { if (from_improved) "F_WAT_PREM_FROM_IMPNP" else "F_WAT_PREM_FROM_UNIMP" },
    P_WATERPOINT = "F_WAT_IMPNP_FROM_UNIMP",
    P_POU_FILTER = if (from_improved) "F_POU_FILTER_FROM_IMPNP" else "F_POU_FILTER_FROM_UNIMP",
    P_POU_CHLOR = , P_INLINE_CHLOR = if (from_improved) "F_POU_CHLOR_FROM_IMPNP" else "F_POU_CHLOR_FROM_UNIMP",
    P_POU_SODIS = if (from_improved) "F_POU_SODIS_FROM_IMPNP" else "F_POU_SODIS_FROM_UNIMP",
    P_SAN_BASIC = , P_CBS = NULL,
    P_SAN_SEWER = "F_SAN_SEWER_FROM_UNIMP",
    P_HYG_PRODUCT = "F_HYG_HW_PROMOTION",
    NULL
  )
  if (pathway_id %in% c("P_SAN_BASIC", "P_CBS")) {
    thr <- get_adjustment(tables, "ADJ_COV_SAN_THRESHOLD")
    if (is.na(community_coverage_after)) {
      flags <- c(flags, "coverage_unknown")
      id <- "F_SAN_BASIC_HHTARGET"
    } else if (community_coverage_after >= thr$value) {
      id <- "F_SAN_BASIC_FROM_UNIMP"
    } else {
      id <- "F_SAN_BASIC_HHTARGET"
      flags <- c(flags, "coverage_below_threshold")
    }
  }
  if (pathway_id == "P_HYG_PRODUCT" && !isTRUE(promotion_contact)) {
    id <- NULL
    flags <- c(flags, "no_promotion_contact")
  }
  if (is.null(id)) return(list(row = NULL, flags = flags))
  list(row = get_effect(tables, id), flags = flags)
}

# ---- the main function --------------------------------------------------------

#' Estimate health outcomes for one enterprise output.
#'
#' @param tables result of load_factors()
#' @param pathway_id row of pathways.csv (for example "P_CONN_HH")
#' @param units number of output units verified (households connected and active, filters in use, toilets installed ...)
#' @param country country name as in baseline-disease.csv; an unknown country needs who_region
#' @param residence "national", "rural" or "urban" (selects the exposure rows for the scenario comparison)
#' @param baseline_source "unimproved" (unimproved or surface water) or "improved_not_on_premises"; NA = assumed unimproved with a flag
#' @param verified_use share of units verified in use (0 to 1); NA = not verified
#' @param years number of years the output is counted for (decay applies from year 2)
#' @param community_coverage_after share of households in the service area with at least basic sanitation after the installations (sanitation pathways)
#' @param water_quality_verified TRUE when routine testing shows water free of E. coli at the tap (connection pathway)
#' @param people_per_unit persons per unit when the enterprise reports it; NA = country mean household size
#' @param sth_prevalence local STH prevalence (0 to 1) if known; NA = STH not estimated
#' @param promotion_contact TRUE when a hygiene product came with at least one promotion contact
#' @param who_region "AFR", "SEAR" or "WPR" for countries outside the baseline table
#' @return a list of class "whit_estimate": pathway, inputs, people, summary (tibble of outcomes with low, central, high),
#'   per_household_year, factors_used (ledger), flags, confidence, notes
estimate_output <- function(tables, pathway_id, units, country, residence = "national", baseline_source = NA,
                            verified_use = NA, years = 1, community_coverage_after = NA, water_quality_verified = FALSE,
                            people_per_unit = NA, sth_prevalence = NA, promotion_contact = NA, who_region = NULL) {
  stopifnot(is.numeric(units), units >= 0, years >= 1)
  pw <- get_pathway(tables, pathway_id)
  flags <- character()
  notes <- character()
  ledger <- list()
  if (pw$evidence_gap_flag == "yes") {
    flags <- c(flags, "evidence_gap")
    notes <- c(notes, paste0("Evidence gap: ", pw$notes))
  }
  if (is.na(baseline_source)) {
    baseline_source <- "unimproved"
    if (pw$paf_component == "water") flags <- c(flags, "baseline_source_assumed")
  }

  # people reached
  if (is.na(people_per_unit)) {
    hh <- get_baseline(tables, country, "household_size", "all ages", who_region)
    if (is.na(hh$value)) stop("household size is not in the baseline table for ", country, "; pass people_per_unit")
    ledger[[length(ledger) + 1]] <- ledger_baseline(hh, "household_size")
    if (hh$fallback) flags <- c(flags, "regional_substitute")
    people_per_unit <- hh$value
  }
  people <- units * people_per_unit
  u5 <- get_baseline(tables, country, "u5_share", "all ages", who_region)
  if (is.na(u5$value)) { children <- NA_real_; flags <- c(flags, "u5_share_missing") } else {
    children <- people * u5$value / 100
    ledger[[length(ledger) + 1]] <- ledger_baseline(u5, "u5_share")
    if (u5$fallback) flags <- c(flags, "regional_substitute")
  }

  # reach-only pathways
  if (pw$paf_component == "none" || pathway_id %in% c("P_CONN_INST", "P_FSM_EMPTYING")) {
    summary <- tibble(outcome = "people reached", population_group = "all ages", low = people, central = people, high = people, unit = "persons", route = "count")
    return(structure(list(pathway = pw, inputs = list(units = units, country = country, years = years), people = people, children_under_five = children,
                          summary = summary, per_household_year = NULL, factors_used = bind_rows(ledger), flags = unique(flags),
                          confidence = "not estimable", notes = c(notes, "No health conversion factor exists for this output type; reach is reported.")),
                     class = "whit_estimate"))
  }

  # effect row
  sel <- select_effect(tables, pathway_id, baseline_source, water_quality_verified, community_coverage_after, promotion_contact)
  flags <- c(flags, sel$flags)
  if ("coverage_unknown" %in% sel$flags) {
    notes <- c(notes, "Community sanitation coverage after the installations was not given; the household-targeted row applies and the label is very low.")
    flags <- c(flags, "coverage_below_threshold")
  }
  if (is.null(sel$row)) {
    summary <- tibble(outcome = "people reached", population_group = "all ages", low = people, central = people, high = people, unit = "persons", route = "count")
    return(structure(list(pathway = pw, inputs = list(units = units, country = country, years = years), people = people, children_under_five = children,
                          summary = summary, per_household_year = NULL, factors_used = bind_rows(ledger), flags = unique(flags),
                          confidence = "not estimable", notes = c(notes, "Hygiene product without a documented promotion contact carries no factor.")),
                     class = "whit_estimate"))
  }
  e <- sel$row
  ledger[[length(ledger) + 1]] <- ledger_effect(e)
  if (is.na(e$low) || is.na(e$high)) flags <- c(flags, "interval_not_available")
  if (!is.na(e$high) && e$high >= 1) flags <- c(flags, "interval_includes_no_effect")
  rr <- c(central = e$central, low = e$high, high = e$low) # low effect = upper RR bound
  reduction <- floor0(1 - rr)                                # floor at zero where the interval includes harm

  # use multiplier
  use_mult <- 1
  use_id <- str_extract(pw$adjustment_ids, "ADJ_USE_[A-Z_]+")
  if (!is.na(use_id)) {
    a <- get_adjustment(tables, use_id)
    ledger[[length(ledger) + 1]] <- ledger_adjust(a)
    if (use_id == "ADJ_USE_HYG") {
      use_mult <- 1
    } else if (is.na(verified_use)) {
      flags <- c(flags, "use_not_verified")
    } else if (is.na(a$value)) {
      use_mult <- verified_use
    } else {
      use_mult <- min(1, verified_use / a$value)
    }
  }

  # decay multiplier for years after the first
  decay <- 1
  decay_id <- str_extract(pw$adjustment_ids, "ADJ_DECAY_[A-Z_]+")
  if (years > 1 && !is.na(decay_id)) {
    d <- get_adjustment(tables, decay_id)
    ledger[[length(ledger) + 1]] <- ledger_adjust(d)
    if (is.na(d$value)) {
      flags <- c(flags, "decay_missing")
    } else {
      decay <- d$value
      if (decay_id == "ADJ_DECAY_POU" && pathway_id != "P_POU_FILTER") flags <- c(flags, "decay_proxy")
    }
  }
  year_weight <- 1 + (years - 1) * decay # sum over years of the yearly multiplier

  # ---- cases route (children under five) ----
  dur <- get_adjustment(tables, "ADJ_EPISODE_DURATION_U5")
  prev <- get_baseline(tables, country, "diarr_prev2w_u5", "under five", who_region)
  if (!is.na(prev$value) && !prev$fallback) {
    incidence <- prev$value / 100 * 365 / (14 + dur$value)
    inc_low <- inc_high <- NA_real_
    ledger[[length(ledger) + 1]] <- ledger_baseline(prev, "diarr_prev2w_u5")
    ledger[[length(ledger) + 1]] <- ledger_adjust(dur)
    inc_note <- "incidence from the DHS two-week prevalence and the episode duration row"
  } else {
    inc <- get_baseline(tables, country, "diarr_incidence_u5", "under five", who_region)
    incidence <- inc$value; inc_low <- inc$low; inc_high <- inc$high
    ledger[[length(ledger) + 1]] <- ledger_baseline(inc, "diarr_incidence_u5")
    flags <- c(flags, "regional_substitute")
    inc_note <- "incidence from the regional modelled value (no DHS prevalence)"
  }
  flags <- c(flags, "reporting_bias")
  cases_per_child_year <- incidence * reduction * use_mult
  cases_total <- children * cases_per_child_year * year_weight
  per_hh_year <- people_per_unit * (u5$value / 100) * cases_per_child_year

  # ---- PAF route (deaths and DALYs, all ages and under five) ----
  comp <- pw$paf_component
  paf <- get_baseline(tables, country, paste0("paf_diarr_", comp), "all ages", who_region)
  ledger[[length(ledger) + 1]] <- ledger_baseline(paf, paste0("paf_diarr_", comp))
  if (paf$fallback) flags <- c(flags, "regional_substitute")
  cf <- get_adjustment(tables, paste0("ADJ_PAF_CF_", c(water = "WATER", sanitation = "SAN", hygiene = "HYG")[[comp]]))
  ledger[[length(ledger) + 1]] <- ledger_adjust(cf)
  sum_p_rr <- cf$value / (1 - paf$value)
  rr_from_abs <- 1
  if (comp == "water" && baseline_source == "improved_not_on_premises") {
    lvl <- get_effect(tables, "F_WAT_IMPNP_FROM_UNIMP")
    rr_from_abs <- lvl$central
    ledger[[length(ledger) + 1]] <- ledger_effect(lvl)
  }
  paf_rows <- list()
  for (grp in c("all ages", "under five")) {
    n <- if (grp == "all ages") people else children
    for (ind in c("diarr_death_rate", "diarr_daly_rate")) {
      rate <- get_baseline(tables, country, ind, grp, who_region)
      ledger[[length(ledger) + 1]] <- ledger_baseline(rate, ind)
      if (rate$fallback) flags <- c(flags, "regional_substitute")
      per_person <- rate$value / 1e5 * rr_from_abs * reduction * use_mult * (1 - paf$value) / cf$value
      paf_rows[[length(paf_rows) + 1]] <- tibble(
        outcome = if (ind == "diarr_death_rate") "diarrhoea deaths averted" else "diarrhoea DALYs averted",
        population_group = grp, low = n * per_person[["low"]] * year_weight, central = n * per_person[["central"]] * year_weight,
        high = n * per_person[["high"]] * year_weight, unit = if (ind == "diarr_death_rate") "deaths" else "DALYs", route = "PAF route (WHO method re-implemented)")
    }
  }

  # ---- STH (secondary) ----
  sth_row <- NULL
  if (!is.na(sth_prevalence)) {
    s <- get_effect(tables, "F_STH_WASH_ANY")
    conv <- get_adjustment(tables, "ADJ_OR_TO_RR")
    ledger[[length(ledger) + 1]] <- ledger_effect(s)
    ledger[[length(ledger) + 1]] <- ledger_adjust(conv)
    or <- c(central = s$central, low = s$high, high = s$low)
    rr_sth <- or / (1 - sth_prevalence + sth_prevalence * or)
    red_sth <- floor0(1 - rr_sth)
    sth_row <- tibble(outcome = "STH infections averted (prevalent cases)", population_group = "all ages",
                      low = people * sth_prevalence * red_sth[["low"]], central = people * sth_prevalence * red_sth[["central"]],
                      high = people * sth_prevalence * red_sth[["high"]], unit = "infections", route = "OR applied to the supplied prevalence; low confidence")
    notes <- c(notes, "STH: Cochrane 2022 odds ratio applied to the prevalence you supplied; the interval includes no effect; effect is additional to deworming.")
  } else {
    sth_b <- get_baseline(tables, country, "sth_prevalence", "all ages", who_region)
    notes <- c(notes, paste0("STH not estimated: ", sth_b$flag))
  }

  summary <- bind_rows(
    tibble(outcome = "people reached", population_group = "all ages", low = people, central = people, high = people, unit = "persons", route = "count"),
    tibble(outcome = "children under five reached", population_group = "under five", low = children, central = children, high = children, unit = "persons", route = "count"),
    tibble(outcome = "diarrhoea cases averted", population_group = "under five", low = cases_total[["low"]], central = cases_total[["central"]], high = cases_total[["high"]],
           unit = "episodes", route = paste0("enterprise baseline x relative risk; ", inc_note)),
    bind_rows(paf_rows),
    sth_row
  )
  per_household_year <- tibble(outcome = "diarrhoea cases averted per household-year (year 1)", population_group = "under five",
                               low = per_hh_year[["low"]], central = per_hh_year[["central"]], high = per_hh_year[["high"]], unit = "episodes per household-year")

  start <- e$certainty
  confidence <- label_confidence(start, flags)
  if ("interval_includes_no_effect" %in% flags) notes <- c(notes, "The confidence interval of the effect includes no effect; the low estimate is shown as zero.")
  if ("use_not_verified" %in% flags) notes <- c(notes, "Use was not verified; no use multiplier was applied and the label dropped one step.")
  if ("baseline_source_assumed" %in% flags) notes <- c(notes, "Customers were assumed to have used an unimproved source before; ask the enterprise for the baseline source.")
  if (years > 1 && "decay_proxy" %in% flags) notes <- c(notes, "Follow-up decay after year one uses the filter value as a proxy.")
  if (years > 1 && "decay_missing" %in% flags) notes <- c(notes, "No decay value exists for this pathway; later years keep the year-one effect and the label dropped one step.")
  notes <- c(notes, "Diarrhoea cases rest on caregiver-reported outcomes in the source trials (reporting bias flag).")

  structure(list(
    pathway = pw,
    inputs = list(units = units, country = country, residence = residence, baseline_source = baseline_source, verified_use = verified_use, years = years,
                  community_coverage_after = community_coverage_after, water_quality_verified = water_quality_verified, people_per_unit = people_per_unit,
                  sth_prevalence = sth_prevalence, promotion_contact = promotion_contact),
    people = people, children_under_five = children,
    exposure_change = list(from = if (comp == "water") baseline_source else e$exposure_from, to = e$exposure_to, effect_row = e$factor_id,
                           relative_risk = unname(rr[["central"]]), risk_reduction = unname(reduction[["central"]]), use_multiplier = use_mult, decay = decay, year_weight = year_weight),
    summary = summary, per_household_year = per_household_year,
    factors_used = bind_rows(ledger) %>% distinct(table, id, .keep_all = TRUE),
    flags = unique(flags), confidence = confidence, notes = notes
  ), class = "whit_estimate")
}

print.whit_estimate <- function(x, ...) {
  cat("Pathway:", x$pathway$pathway_id, "-", x$pathway$output_type, "\n")
  cat("Country:", x$inputs$country, "| units:", x$inputs$units, "| years:", x$inputs$years, "\n")
  cat("Confidence label:", x$confidence, "| flags:", paste(x$flags, collapse = ", "), "\n")
  print(x$summary %>% mutate(across(c(low, central, high), ~ signif(.x, 3))), n = 20)
  invisible(x)
}

# ---- direct mortality sensitivity band ----------------------------------------

#' Direct mortality route (sensitivity band): all-cause under-five deaths averted from pooled mortality odds ratios.
#' Returns one row per band row that applies to the pathway, plus the diarrhoea-death cross-check.
estimate_mortality_band <- function(tables, pathway_id, units, country, people_per_unit = NA, years = 1, community_coverage_after = NA, who_region = NULL) {
  pw <- get_pathway(tables, pathway_id)
  if (is.na(people_per_unit)) people_per_unit <- get_baseline(tables, country, "household_size", "all ages", who_region)$value
  u5 <- get_baseline(tables, country, "u5_share", "all ages", who_region)
  children <- units * people_per_unit * u5$value / 100
  u5mr <- get_baseline(tables, country, "u5mr", "under five", who_region)
  conv <- get_adjustment(tables, "ADJ_U5MR_TO_RATE")
  death_rate <- u5mr$value / 1000 * conv$value # all-cause deaths per child-year
  diarr_rate <- get_baseline(tables, country, "diarr_death_rate", "under five", who_region)
  band_ids <- switch(pathway_id,
    P_POU_FILTER = , P_POU_CHLOR = , P_POU_SODIS = , P_INLINE_CHLOR = c("F_MORT_POU_KREMER", "F_MORT_POU_SW"),
    P_CONN_HH = , P_WATERPOINT = "F_MORT_WATSUP",
    P_SAN_BASIC = , P_CBS = , P_SAN_SEWER = if (!is.na(community_coverage_after) && community_coverage_after >= get_adjustment(tables, "ADJ_COV_SAN_THRESHOLD")$value) "F_MORT_SAN_COMMUNITY" else "F_MORT_SAN_HHTARGET",
    P_HYG_PRODUCT = "F_MORT_HYG",
    character())
  rows <- map(band_ids, function(id) {
    e <- get_effect(tables, id)
    or <- c(central = e$central, low = e$high, high = e$low)
    red <- floor0(1 - or) # OR close to RR at the low annual death risk (ADJ_OR_TO_RR)
    tibble(band_row = id, outcome = "all-cause under-five deaths averted (direct route)", low = children * death_rate * red[["low"]] * years,
           central = children * death_rate * red[["central"]] * years, high = children * death_rate * red[["high"]] * years,
           citation = e$source_citation, certainty = e$certainty)
  }) %>% bind_rows()
  d <- get_effect(tables, "F_MORT_DIARR_ANYWASH")
  or <- c(central = d$central, low = d$high, high = d$low)
  red <- floor0(1 - or)
  cross <- tibble(band_row = d$factor_id, outcome = "diarrhoea deaths averted under five (direct route cross-check)",
                  low = children * diarr_rate$value / 1e5 * red[["low"]] * years, central = children * diarr_rate$value / 1e5 * red[["central"]] * years,
                  high = children * diarr_rate$value / 1e5 * red[["high"]] * years, citation = d$source_citation, certainty = d$certainty)
  list(band = bind_rows(rows, cross), children = children, death_rate_per_child_year = death_rate,
       factors_used = bind_rows(ledger_baseline(u5mr, "u5mr"), ledger_adjust(conv), ledger_baseline(diarr_rate, "diarr_death_rate")),
       note = "Sensitivity band only. Odds ratios from trials with mortality data; the annual death rate is approximated from the under-five mortality rate (ADJ_U5MR_TO_RATE). Not for public reporting on its own.")
}

# ---- WHO scenario-difference comparison ----------------------------------------

#' Absolute relative risks by service level versus the unimproved level (from ADJ_LADDER_RR_* rows, read from effects.csv).
ladder_rr <- function(tables, service) {
  switch(service,
    water = c("surface water" = 1, "unimproved" = 1, "limited (more than 30 minutes)" = get_effect(tables, "F_WAT_IMPNP_FROM_UNIMP")$central,
              "basic (not safely managed)" = get_effect(tables, "F_WAT_IMPNP_FROM_UNIMP")$central, "safely managed" = get_effect(tables, "F_WAT_PREMHQ_FROM_UNIMP")$central),
    sanitation = c("open defecation" = 1, "limited or unimproved" = 1, "basic (not safely managed)" = get_effect(tables, "F_SAN_BASIC_FROM_UNIMP")$central,
                   "safely managed" = get_effect(tables, "F_SAN_SEWER_FROM_UNIMP")$central),
    hygiene = c("limited or no facility" = 1, "basic" = get_effect(tables, "F_HYG_HW_PROMOTION")$central)
  )
}

#' Exposure distribution of a country for one service (shares summing to about 1), national, rural or urban.
exposure_distribution <- function(tables, country, service, residence = "national") {
  rr <- ladder_rr(tables, service)
  p <- map_dbl(names(rr), ~ get_exposure(tables, country, service, .x, residence))
  names(p) <- names(rr)
  if (service == "water") {
    basic_all <- get_exposure(tables, country, "water", "at least basic", residence)
    sm <- p[["safely managed"]]
    if (is.na(sm)) { p[["safely managed"]] <- 0; p[["basic (not safely managed)"]] <- basic_all } else p[["basic (not safely managed)"]] <- basic_all - sm
  }
  if (service == "sanitation" && is.na(p[["safely managed"]])) {
    p[["safely managed"]] <- 0
    p[["basic (not safely managed)"]] <- get_exposure(tables, country, "sanitation", "at least basic", residence)
  }
  p <- p / 100
  p[is.na(p)] <- 0
  list(p = p / sum(p), rr = rr, sum_p_rr = sum(p / sum(p) * rr))
}

#' WHO-style scenario difference: move `people` from one service level to another in the national
#' exposure distribution and take the difference in attributable burden. Also returns the PAF as
#' re-implemented here next to the WHO published PAF for the country.
estimate_scenario_difference <- function(tables, country, service, from_level, to_level, people, residence = "national", to_rr = NULL, who_region = NULL) {
  dist <- exposure_distribution(tables, country, service, residence)
  pop <- get_baseline(tables, country, "population", "all ages", who_region)
  cf <- get_adjustment(tables, paste0("ADJ_PAF_CF_", c(water = "WATER", sanitation = "SAN", hygiene = "HYG")[[service]]))
  paf_who <- get_baseline(tables, country, paste0("paf_diarr_", service), "all ages", who_region)
  share <- people / pop$value
  p_after <- dist$p
  p_after[[from_level]] <- p_after[[from_level]] - share
  rr_to <- if (!is.null(to_rr)) to_rr else dist$rr[[to_level]]
  sum_after <- sum(p_after * dist$rr) + share * rr_to
  paf_before <- 1 - cf$value / dist$sum_p_rr
  paf_after <- 1 - cf$value / sum_after
  out <- map(c("all ages", "under five"), function(grp) {
    deaths <- get_baseline(tables, country, "diarr_deaths_total", grp, who_region)
    dalys <- get_baseline(tables, country, "diarr_dalys_total", grp, who_region)
    tibble(population_group = grp,
           deaths_averted = deaths$value * (dist$sum_p_rr - sum_after) / dist$sum_p_rr,
           dalys_averted = dalys$value * (dist$sum_p_rr - sum_after) / dist$sum_p_rr)
  }) %>% bind_rows()
  list(result = out, paf_reimplemented = paf_before, paf_after = paf_after, paf_who = paf_who$value, sum_p_rr_before = dist$sum_p_rr,
       exposure_shares = dist$p, ladder_rr = dist$rr, share_moved = share,
       note = paste0("Scenario difference at national scale (", residence, " exposure shares applied to the whole population as a check). ",
                     "The re-implemented PAF differs from WHO's because WHO uses survey-level exposure categories (point-of-use treatment, piped on premises, sewer connections, handwashing practice) that the JMP ladder does not separate."))
}

# ---- portfolio helper ---------------------------------------------------------

#' Bind the summaries of several estimates into one table with the confidence label per output.
bind_estimates <- function(...) {
  ests <- list(...)
  map(ests, function(x) x$summary %>% mutate(pathway = x$pathway$pathway_id, output_type = x$pathway$output_type, country = x$inputs$country,
                                               units = x$inputs$units, confidence = x$confidence, .before = 1)) %>% bind_rows()
}
