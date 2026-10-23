# The estimation chain. Every number used here is a row in the factor tables;
# the functions retrieve rows and do arithmetic on them. Each result returns
# the list of rows it used, with citations, so a reader can check every step.

# Pathways whose people_per_unit_rule names a required enterprise input.
REQUIRES_PEOPLE_PER_UNIT <- c("P_CONN_INST", "P_WATERPOINT", "P_MHH")

# Choose the effect row for a pathway from the user's inputs; returns the row plus flags.
select_effect <- function(pathway_id, baseline_source, water_quality_verified, community_coverage_after, promotion_contact, tables) {
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
    thr <- get_adjustment("ADJ_COV_SAN_THRESHOLD", tables)
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
  list(row = get_effect(id, tables), flags = flags)
}

reach_only <- function(pw, inputs, people, children, ledger, flags, notes, tables) {
  summary <- tibble::tibble(outcome = "people reached", population_group = "all ages", low = people, central = people, high = people, unit = "persons", route = "count")
  structure(list(pathway = pw, inputs = inputs, people = people, children_under_five = children, exposure_change = NULL,
                 summary = summary, per_household_year = NULL, factors_used = rbind_rows(ledger, empty_ledger()),
                 flags = unique(flags), confidence = "not estimable", notes = notes, factors_version = factors_version()),
            class = "washhealth_estimate")
}

#' Estimate health outcomes for one enterprise output
#'
#' The engine of the package. For one output type, a number of units and a
#' country it retrieves the matching factor rows and returns people reached,
#' diarrhoea cases averted in children under five, deaths and DALYs averted
#' (WHO population attributable fraction route, all ages and under five) and,
#' when a prevalence is supplied, soil-transmitted helminth infections averted.
#' Every result has a low, central and high value from the effect row's
#' confidence interval, the ledger of rows used and a confidence label.
#'
#' Pathways without a conversion factor (institutional connections, emptying
#' services, menstrual health products, hygiene products without promotion)
#' return people reached and the label `"not estimable"`.
#'
#' @param pathway_id Pathway id (for example `"P_POU_FILTER"`) or the output
#'   type label from [output_types()] (for example `"household water filter"`).
#' @param units Number of output units (households connected and active,
#'   filters in use, toilets installed, ...).
#' @param country Country name as in [countries()]; another country needs
#'   `who_region`.
#' @param residence `"national"`, `"rural"` or `"urban"`; selects the exposure
#'   rows used for the JMP coverage fallback and the WHO scenario comparison.
#' @param baseline_source `"unimproved"` (unimproved or surface water) or
#'   `"improved_not_on_premises"`; NA means assumed unimproved with a flag.
#' @param verified_use Share of units verified in use (0 to 1); NA means not
#'   verified (no multiplier, label drops one step).
#' @param years Years of service the output is counted for. Year one counts in
#'   full; later years count with the pathway's decay factor. A fraction (for
#'   example 0.5 for a six-month period) counts that share of year one.
#' @param community_coverage_after Share (0 to 1) of households in the service
#'   area with at least basic sanitation after the installations (sanitation
#'   pathways). NA means the JMP value for the country and residence is used
#'   with a flag.
#' @param water_quality_verified TRUE when routine testing shows the water is
#'   free of E. coli at the tap (household connection pathway).
#' @param people_per_unit Persons per unit when the enterprise reports it; NA
#'   means the country mean household size. Required for institutional
#'   connections and menstrual health outputs.
#' @param sth_prevalence Local STH prevalence (0 to 1) if known; NA means STH
#'   is not estimated.
#' @param promotion_contact TRUE when a hygiene product came with at least one
#'   promotion contact.
#' @param who_region `"AFR"`, `"SEAR"` or `"WPR"` for a country outside the
#'   baseline table.
#' @param tables The factor tables, see [factor_tables()].
#' @return An object of class `washhealth_estimate`: a list with `pathway`,
#'   `inputs`, `people`, `children_under_five`, `exposure_change`, `summary`
#'   (tibble of outcomes with `low`, `central`, `high`), `per_household_year`,
#'   `factors_used` (the ledger), `flags`, `confidence`, `notes` and
#'   `factors_version`.
#' @seealso [estimate_transaction()] and [estimate_scenario()] run this
#'   function over a table of transactions.
#' @export
#' @examples
#' est <- estimate_output("P_POU_FILTER", units = 1000, country = "Kenya", residence = "rural",
#'                        baseline_source = "unimproved", verified_use = 0.93)
#' est
#' est$factors_used[, c("table", "id", "value", "citation")]
estimate_output <- function(pathway_id, units, country, residence = "national", baseline_source = NA,
                            verified_use = NA, years = 1, community_coverage_after = NA, water_quality_verified = FALSE,
                            people_per_unit = NA, sth_prevalence = NA, promotion_contact = NA, who_region = NULL,
                            tables = factor_tables()) {
  stopifnot(is.numeric(units), length(units) == 1, !is.na(units), units >= 0,
            is.numeric(years), length(years) == 1, !is.na(years), years > 0)
  residence <- match.arg(residence, c("national", "rural", "urban"))
  if (!is.na(baseline_source) && !baseline_source %in% c("unimproved", "improved_not_on_premises")) {
    stop("baseline_source must be 'unimproved', 'improved_not_on_premises' or NA", call. = FALSE)
  }
  if (!is.na(verified_use) && (verified_use < 0 || verified_use > 1)) stop("verified_use must be a share between 0 and 1", call. = FALSE)
  pathway_id <- resolve_pathway(pathway_id, tables)
  pw <- get_pathway(pathway_id, tables)
  if (pathway_id %in% REQUIRES_PEOPLE_PER_UNIT && is.na(people_per_unit)) {
    stop("pathway ", pathway_id, " (", pw$output_type, ") needs people_per_unit: ", pw$people_per_unit_rule, call. = FALSE)
  }
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
    hh <- get_baseline(country, "household_size", "all ages", who_region, tables)
    if (is.na(hh$value)) stop("household size is not in the baseline table for ", country, "; pass people_per_unit", call. = FALSE)
    ledger[[length(ledger) + 1]] <- ledger_baseline(hh, "household_size")
    if (hh$fallback) flags <- c(flags, "regional_substitute")
    people_per_unit <- hh$value
  }
  people <- units * people_per_unit
  u5 <- get_baseline(country, "u5_share", "all ages", who_region, tables)
  if (is.na(u5$value)) {
    children <- NA_real_
    flags <- c(flags, "u5_share_missing")
  } else {
    children <- people * u5$value / 100
    ledger[[length(ledger) + 1]] <- ledger_baseline(u5, "u5_share")
    if (u5$fallback) flags <- c(flags, "regional_substitute")
  }
  inputs <- list(pathway_id = pathway_id, units = units, country = country, residence = residence, baseline_source = baseline_source,
                 verified_use = verified_use, years = years, community_coverage_after = community_coverage_after,
                 water_quality_verified = water_quality_verified, people_per_unit = people_per_unit,
                 sth_prevalence = sth_prevalence, promotion_contact = promotion_contact, who_region = who_region)

  # reach-only pathways
  if (pw$paf_component == "none" || pathway_id %in% c("P_CONN_INST", "P_FSM_EMPTYING")) {
    return(reach_only(pw, inputs, people, children, ledger, flags,
                      c(notes, "No health conversion factor exists for this output type; reach is reported."), tables))
  }

  # sanitation coverage: enterprise survey value, else the JMP value with a flag
  if (pathway_id %in% c("P_SAN_BASIC", "P_CBS") && is.na(community_coverage_after)) {
    x <- get_exposure_row(country, "sanitation", "at least basic", residence, tables)
    if (!is.null(x) && !is.na(x$value)) {
      community_coverage_after <- x$value / 100
      inputs$community_coverage_after <- community_coverage_after
      flags <- c(flags, "coverage_from_jmp")
      ledger[[length(ledger) + 1]] <- ledger_exposure(x)
      notes <- c(notes, paste0("Community sanitation coverage after the installations was not given; the JMP ", residence,
                               " value for ", country, " (", x$value, " percent at least basic, ", x$year, ") was used and the label dropped one step."))
    }
  }

  # effect row
  sel <- select_effect(pathway_id, baseline_source, water_quality_verified, community_coverage_after, promotion_contact, tables)
  flags <- c(flags, sel$flags)
  if ("coverage_unknown" %in% sel$flags) {
    notes <- c(notes, "Community sanitation coverage after the installations is unknown and no JMP value exists; the household-targeted row applies and the label is very low.")
    flags <- c(flags, "coverage_below_threshold")
  }
  if (is.null(sel$row)) {
    return(reach_only(pw, inputs, people, children, ledger, flags,
                      c(notes, "Hygiene product without a documented promotion contact carries no factor; reach is reported."), tables))
  }
  e <- sel$row
  ledger[[length(ledger) + 1]] <- ledger_effect(e)
  if (is.na(e$low) || is.na(e$high)) flags <- c(flags, "interval_not_available")
  if (!is.na(e$high) && e$high >= 1) flags <- c(flags, "interval_includes_no_effect")
  rr <- c(central = e$central, low = e$high, high = e$low) # low effect = upper RR bound
  reduction <- floor0(1 - rr)                                # floor at zero where the interval includes harm

  # use multiplier
  use_mult <- 1
  use_id <- first_match(pw$adjustment_ids, "ADJ_USE_[A-Z_]+")
  if (!is.na(use_id)) {
    a <- get_adjustment(use_id, tables)
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
  decay_id <- first_match(pw$adjustment_ids, "ADJ_DECAY_[A-Z_]+")
  if (years > 1 && !is.na(decay_id)) {
    d <- get_adjustment(decay_id, tables)
    ledger[[length(ledger) + 1]] <- ledger_adjust(d)
    if (is.na(d$value)) {
      flags <- c(flags, "decay_missing")
    } else {
      decay <- d$value
      if (decay_id == "ADJ_DECAY_POU" && pathway_id != "P_POU_FILTER") flags <- c(flags, "decay_proxy")
    }
  }
  year_weight <- min(years, 1) + max(years - 1, 0) * decay # year one in full, later years with decay

  # ---- cases route (children under five) ----
  dur <- get_adjustment("ADJ_EPISODE_DURATION_U5", tables)
  prev <- get_baseline(country, "diarr_prev2w_u5", "under five", who_region, tables)
  if (!is.na(prev$value) && !prev$fallback) {
    incidence <- prev$value / 100 * 365 / (14 + dur$value)
    ledger[[length(ledger) + 1]] <- ledger_baseline(prev, "diarr_prev2w_u5")
    ledger[[length(ledger) + 1]] <- ledger_adjust(dur)
    inc_note <- "incidence from the DHS two-week prevalence and the episode duration row"
  } else {
    inc <- get_baseline(country, "diarr_incidence_u5", "under five", who_region, tables)
    incidence <- inc$value
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
  paf <- get_baseline(country, paste0("paf_diarr_", comp), "all ages", who_region, tables)
  ledger[[length(ledger) + 1]] <- ledger_baseline(paf, paste0("paf_diarr_", comp))
  if (paf$fallback) flags <- c(flags, "regional_substitute")
  cf <- get_adjustment(paste0("ADJ_PAF_CF_", c(water = "WATER", sanitation = "SAN", hygiene = "HYG")[[comp]]), tables)
  ledger[[length(ledger) + 1]] <- ledger_adjust(cf)
  rr_from_abs <- 1
  if (comp == "water" && baseline_source == "improved_not_on_premises") {
    lvl <- get_effect("F_WAT_IMPNP_FROM_UNIMP", tables)
    rr_from_abs <- lvl$central
    ledger[[length(ledger) + 1]] <- ledger_effect(lvl)
  }
  paf_rows <- list()
  for (grp in c("all ages", "under five")) {
    n <- if (grp == "all ages") people else children
    for (ind in c("diarr_death_rate", "diarr_daly_rate")) {
      rate <- get_baseline(country, ind, grp, who_region, tables)
      ledger[[length(ledger) + 1]] <- ledger_baseline(rate, ind)
      if (rate$fallback) flags <- c(flags, "regional_substitute")
      per_person <- rate$value / 1e5 * rr_from_abs * reduction * use_mult * (1 - paf$value) / cf$value
      paf_rows[[length(paf_rows) + 1]] <- tibble::tibble(
        outcome = if (ind == "diarr_death_rate") "diarrhoea deaths averted" else "diarrhoea DALYs averted",
        population_group = grp, low = n * per_person[["low"]] * year_weight, central = n * per_person[["central"]] * year_weight,
        high = n * per_person[["high"]] * year_weight, unit = if (ind == "diarr_death_rate") "deaths" else "DALYs",
        route = "PAF route (WHO method re-implemented)")
    }
  }

  # ---- STH (secondary) ----
  sth_row <- NULL
  if (!is.na(sth_prevalence)) {
    s <- get_effect("F_STH_WASH_ANY", tables)
    conv <- get_adjustment("ADJ_OR_TO_RR", tables)
    ledger[[length(ledger) + 1]] <- ledger_effect(s)
    ledger[[length(ledger) + 1]] <- ledger_adjust(conv)
    or <- c(central = s$central, low = s$high, high = s$low)
    rr_sth <- or / (1 - sth_prevalence + sth_prevalence * or)
    red_sth <- floor0(1 - rr_sth)
    sth_row <- tibble::tibble(outcome = "STH infections averted (prevalent cases)", population_group = "all ages",
                              low = people * sth_prevalence * red_sth[["low"]], central = people * sth_prevalence * red_sth[["central"]],
                              high = people * sth_prevalence * red_sth[["high"]], unit = "infections",
                              route = "OR applied to the supplied prevalence; low confidence")
    notes <- c(notes, "STH: Cochrane 2022 odds ratio applied to the prevalence you supplied; the interval includes no effect; effect is additional to deworming.")
  } else {
    sth_b <- get_baseline(country, "sth_prevalence", "all ages", who_region, tables)
    notes <- c(notes, paste0("STH not estimated: ", sth_b$flag))
  }

  summary <- rbind_rows(list(
    tibble::tibble(outcome = "people reached", population_group = "all ages", low = people, central = people, high = people, unit = "persons", route = "count"),
    tibble::tibble(outcome = "children under five reached", population_group = "under five", low = children, central = children, high = children, unit = "persons", route = "count"),
    tibble::tibble(outcome = "diarrhoea cases averted", population_group = "under five", low = cases_total[["low"]], central = cases_total[["central"]], high = cases_total[["high"]],
                   unit = "episodes", route = paste0("enterprise baseline x relative risk; ", inc_note)),
    rbind_rows(paf_rows),
    sth_row
  ))
  per_household_year <- tibble::tibble(outcome = "diarrhoea cases averted per household-year (year 1)", population_group = "under five",
                                       low = per_hh_year[["low"]], central = per_hh_year[["central"]], high = per_hh_year[["high"]],
                                       unit = "episodes per household-year", route = "rate")

  confidence <- label_confidence(e$certainty, flags)
  if ("interval_includes_no_effect" %in% flags) notes <- c(notes, "The confidence interval of the effect includes no effect; the low estimate is shown as zero.")
  if ("use_not_verified" %in% flags) notes <- c(notes, "Use was not verified; no use multiplier was applied and the label dropped one step.")
  if ("baseline_source_assumed" %in% flags) notes <- c(notes, "Customers were assumed to have used an unimproved source before; ask the enterprise for the baseline source.")
  if (years > 1 && "decay_proxy" %in% flags) notes <- c(notes, "Follow-up decay after year one uses the filter value as a proxy.")
  if (years > 1 && "decay_missing" %in% flags) notes <- c(notes, "No decay value exists for this pathway; later years keep the year-one effect and the label dropped one step.")
  notes <- c(notes, "Diarrhoea cases rest on caregiver-reported outcomes in the source trials (reporting bias flag).")

  structure(list(
    pathway = pw,
    inputs = inputs,
    people = people, children_under_five = children,
    exposure_change = list(from = if (comp == "water") baseline_source else e$exposure_from, to = e$exposure_to, effect_row = e$factor_id,
                           relative_risk = unname(rr[["central"]]), risk_reduction = unname(reduction[["central"]]),
                           use_multiplier = use_mult, decay = decay, year_weight = year_weight),
    summary = summary, per_household_year = per_household_year,
    factors_used = distinct_on(rbind_rows(ledger, empty_ledger()), c("table", "id")),
    flags = unique(flags), confidence = confidence, notes = notes, factors_version = factors_version()
  ), class = "washhealth_estimate")
}

#' @export
print.washhealth_estimate <- function(x, ...) {
  cat("Pathway:", x$pathway$pathway_id, "-", x$pathway$output_type, "\n")
  cat("Country:", x$inputs$country, "| units:", x$inputs$units, "| years:", x$inputs$years, "\n")
  cat("Confidence label:", x$confidence, "| flags:", paste(x$flags, collapse = ", "), "\n")
  cat("Factor tables:", x$factors_version, "\n")
  s <- x$summary
  for (col in c("low", "central", "high")) s[[col]] <- signif(s[[col]], 3)
  print(s, n = 20)
  invisible(x)
}

#' Direct mortality sensitivity band
#'
#' All-cause under-five deaths averted from the pooled mortality odds ratios
#' (Kremer et al. 2023; Sharma Waddington et al. 2023), plus the diarrhoea
#' death cross-check. For sensitivity only; never reported alone.
#'
#' @inheritParams estimate_output
#' @return A list with `band` (tibble, one row per band row), `children`,
#'   `death_rate_per_child_year`, `factors_used` and `note`.
#' @export
#' @examples
#' estimate_mortality_band("P_POU_FILTER", units = 1000, country = "Kenya")$band
estimate_mortality_band <- function(pathway_id, units, country, people_per_unit = NA, years = 1, community_coverage_after = NA,
                                    who_region = NULL, tables = factor_tables()) {
  pathway_id <- resolve_pathway(pathway_id, tables)
  if (is.na(people_per_unit)) people_per_unit <- get_baseline(country, "household_size", "all ages", who_region, tables)$value
  u5 <- get_baseline(country, "u5_share", "all ages", who_region, tables)
  children <- units * people_per_unit * u5$value / 100
  u5mr <- get_baseline(country, "u5mr", "under five", who_region, tables)
  conv <- get_adjustment("ADJ_U5MR_TO_RATE", tables)
  death_rate <- u5mr$value / 1000 * conv$value # all-cause deaths per child-year
  diarr_rate <- get_baseline(country, "diarr_death_rate", "under five", who_region, tables)
  thr <- get_adjustment("ADJ_COV_SAN_THRESHOLD", tables)$value
  band_ids <- switch(pathway_id,
    P_POU_FILTER = , P_POU_CHLOR = , P_POU_SODIS = , P_INLINE_CHLOR = c("F_MORT_POU_KREMER", "F_MORT_POU_SW"),
    P_CONN_HH = , P_WATERPOINT = "F_MORT_WATSUP",
    P_SAN_BASIC = , P_CBS = , P_SAN_SEWER = if (!is.na(community_coverage_after) && community_coverage_after >= thr) "F_MORT_SAN_COMMUNITY" else "F_MORT_SAN_HHTARGET",
    P_HYG_PRODUCT = "F_MORT_HYG",
    character())
  rows <- lapply(band_ids, function(id) {
    e <- get_effect(id, tables)
    or <- c(central = e$central, low = e$high, high = e$low)
    red <- floor0(1 - or) # OR close to RR at the low annual death risk (ADJ_OR_TO_RR)
    tibble::tibble(band_row = id, outcome = "all-cause under-five deaths averted (direct route)",
                   low = children * death_rate * red[["low"]] * years, central = children * death_rate * red[["central"]] * years,
                   high = children * death_rate * red[["high"]] * years, citation = e$source_citation, certainty = e$certainty)
  })
  d <- get_effect("F_MORT_DIARR_ANYWASH", tables)
  or <- c(central = d$central, low = d$high, high = d$low)
  red <- floor0(1 - or)
  cross <- tibble::tibble(band_row = d$factor_id, outcome = "diarrhoea deaths averted under five (direct route cross-check)",
                          low = children * diarr_rate$value / 1e5 * red[["low"]] * years,
                          central = children * diarr_rate$value / 1e5 * red[["central"]] * years,
                          high = children * diarr_rate$value / 1e5 * red[["high"]] * years, citation = d$source_citation, certainty = d$certainty)
  list(band = rbind_rows(c(rows, list(cross))), children = children, death_rate_per_child_year = death_rate,
       factors_used = rbind_rows(list(ledger_baseline(u5mr, "u5mr"), ledger_adjust(conv), ledger_baseline(diarr_rate, "diarr_death_rate"))),
       note = "Sensitivity band only. Odds ratios from trials with mortality data; the annual death rate is approximated from the under-five mortality rate (ADJ_U5MR_TO_RATE). Not for public reporting on its own.")
}

#' Service ladder relative risks and exposure distributions
#'
#' `ladder_rr()` gives the absolute relative risk of each service level versus
#' the unimproved level, read from the effect rows. `exposure_distribution()`
#' gives the share of a country's population at each level (national, rural or
#' urban) and the weighted mean relative risk.
#'
#' @inheritParams estimate_output
#' @param service `"water"`, `"sanitation"` or `"hygiene"`.
#' @return `ladder_rr()` a named numeric vector. `exposure_distribution()` a
#'   list with `p` (shares), `rr` and `sum_p_rr`.
#' @export
#' @examples
#' ladder_rr("water")
#' exposure_distribution("Cambodia", "water", "rural")$sum_p_rr
ladder_rr <- function(service, tables = factor_tables()) {
  switch(service,
    water = c("surface water" = 1, "unimproved" = 1,
              "limited (more than 30 minutes)" = get_effect("F_WAT_IMPNP_FROM_UNIMP", tables)$central,
              "basic (not safely managed)" = get_effect("F_WAT_IMPNP_FROM_UNIMP", tables)$central,
              "safely managed" = get_effect("F_WAT_PREMHQ_FROM_UNIMP", tables)$central),
    sanitation = c("open defecation" = 1, "limited or unimproved" = 1,
                   "basic (not safely managed)" = get_effect("F_SAN_BASIC_FROM_UNIMP", tables)$central,
                   "safely managed" = get_effect("F_SAN_SEWER_FROM_UNIMP", tables)$central),
    hygiene = c("limited or no facility" = 1, "basic" = get_effect("F_HYG_HW_PROMOTION", tables)$central),
    stop("service must be water, sanitation or hygiene", call. = FALSE)
  )
}

#' @rdname ladder_rr
#' @export
exposure_distribution <- function(country, service, residence = "national", tables = factor_tables()) {
  rr <- ladder_rr(service, tables)
  p <- vapply(names(rr), function(l) get_exposure(country, service, l, residence, tables), numeric(1))
  names(p) <- names(rr)
  if (service == "water") {
    basic_all <- get_exposure(country, "water", "at least basic", residence, tables)
    sm <- p[["safely managed"]]
    if (is.na(sm)) { p[["safely managed"]] <- 0; p[["basic (not safely managed)"]] <- basic_all } else p[["basic (not safely managed)"]] <- basic_all - sm
  }
  if (service == "sanitation" && is.na(p[["safely managed"]])) {
    p[["safely managed"]] <- 0
    p[["basic (not safely managed)"]] <- get_exposure(country, "sanitation", "at least basic", residence, tables)
  }
  p <- p / 100
  p[is.na(p)] <- 0
  if (sum(p) == 0) stop("no exposure rows for ", country, " (", service, ", ", residence, ")", call. = FALSE)
  list(p = p / sum(p), rr = rr, sum_p_rr = sum(p / sum(p) * rr))
}

#' WHO-style scenario comparison at country scale
#'
#' Repeats WHO's attributable burden calculation: moves `people` from one
#' service level to another in the country's exposure distribution and takes
#' the difference in attributable deaths and DALYs. Also returns the
#' attributable fraction as re-implemented here next to WHO's published value,
#' as a check on the method. This is a check on the per-person PAF route of
#' [estimate_output()], not a replacement.
#'
#' @inheritParams ladder_rr
#' @inheritParams estimate_output
#' @param from_level,to_level Level names as in [ladder_rr()].
#' @param people Number of people moved.
#' @param to_rr Optional relative risk of the destination (overrides the ladder
#'   value, for example the effect row for a connection on premises).
#' @return A list with `result` (deaths and DALYs averted, all ages and under
#'   five), `paf_reimplemented`, `paf_after`, `paf_who`, `sum_p_rr_before`,
#'   `exposure_shares`, `ladder_rr`, `share_moved` and `note`.
#' @export
#' @examples
#' compare_who_scenario("Cambodia", "water", "unimproved", "basic (not safely managed)",
#'                      people = 10000, residence = "rural")$result
compare_who_scenario <- function(country, service, from_level, to_level, people, residence = "national", to_rr = NULL,
                                 who_region = NULL, tables = factor_tables()) {
  dist <- exposure_distribution(country, service, residence, tables)
  pop <- get_baseline(country, "population", "all ages", who_region, tables)
  cf <- get_adjustment(paste0("ADJ_PAF_CF_", c(water = "WATER", sanitation = "SAN", hygiene = "HYG")[[service]]), tables)
  paf_who <- get_baseline(country, paste0("paf_diarr_", service), "all ages", who_region, tables)
  share <- people / pop$value
  p_after <- dist$p
  p_after[[from_level]] <- p_after[[from_level]] - share
  rr_to <- if (!is.null(to_rr)) to_rr else dist$rr[[to_level]]
  sum_after <- sum(p_after * dist$rr) + share * rr_to
  paf_before <- 1 - cf$value / dist$sum_p_rr
  paf_after <- 1 - cf$value / sum_after
  out <- lapply(c("all ages", "under five"), function(grp) {
    deaths <- get_baseline(country, "diarr_deaths_total", grp, who_region, tables)
    dalys <- get_baseline(country, "diarr_dalys_total", grp, who_region, tables)
    tibble::tibble(population_group = grp,
                   deaths_averted = deaths$value * (dist$sum_p_rr - sum_after) / dist$sum_p_rr,
                   dalys_averted = dalys$value * (dist$sum_p_rr - sum_after) / dist$sum_p_rr)
  })
  list(result = rbind_rows(out), paf_reimplemented = paf_before, paf_after = paf_after, paf_who = paf_who$value,
       sum_p_rr_before = dist$sum_p_rr, exposure_shares = dist$p, ladder_rr = dist$rr, share_moved = share,
       note = paste0("Scenario difference at national scale (", residence, " exposure shares applied to the whole population as a check). ",
                     "The re-implemented PAF differs from WHO's because WHO uses survey-level exposure categories (point-of-use treatment, piped on premises, sewer connections, handwashing practice) that the JMP ladder does not separate."))
}

#' Bind the summaries of several estimates into one table
#'
#' @param ... Objects returned by [estimate_output()], or one list of them.
#' @return A tibble with the pathway, output type, country, units and
#'   confidence label in front of each summary row.
#' @export
#' @examples
#' a <- estimate_output("P_POU_FILTER", 100, "Kenya", baseline_source = "unimproved", verified_use = 0.9)
#' b <- estimate_output("P_CONN_INST", 2, "Kenya", people_per_unit = 400)
#' bind_estimates(a, b)
bind_estimates <- function(...) {
  ests <- list(...)
  if (length(ests) == 1 && !inherits(ests[[1]], "washhealth_estimate")) ests <- ests[[1]]
  rows <- lapply(ests, function(x) {
    s <- x$summary
    tibble::tibble(pathway = x$pathway$pathway_id, output_type = x$pathway$output_type, country = x$inputs$country,
                   units = x$inputs$units, confidence = x$confidence, s)
  })
  rbind_rows(rows)
}
