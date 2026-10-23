root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
source(file.path(root, "R", "estimate.R"))
tables <- load_factors(file.path(root, "data", "factors"))

ordered <- function(s) all(s$low <= s$central + 1e-9 & s$central <= s$high + 1e-9, na.rm = TRUE)

test_that("every pathway runs and returns an ordered low, central, high", {
  for (pid in tables$pathways$pathway_id) {
    est <- estimate_output(tables, pid, units = 100, country = "Kenya", baseline_source = "unimproved",
                           verified_use = 0.8, community_coverage_after = 0.7, promotion_contact = TRUE, people_per_unit = NA)
    expect_s3_class(est, "whit_estimate")
    expect_true(nrow(est$summary) >= 1, info = pid)
    expect_true(ordered(est$summary), info = pid)
    expect_true(est$confidence %in% c(CONFIDENCE_LEVELS, "not estimable"), info = pid)
  }
})

test_that("reach-only pathways report people and no health conversion", {
  for (pid in c("P_CONN_INST", "P_FSM_EMPTYING", "P_MHH")) {
    est <- estimate_output(tables, pid, units = 10, country = "Cambodia", people_per_unit = 300)
    expect_equal(est$people, 3000)
    expect_equal(est$confidence, "not estimable")
    expect_false(any(grepl("averted", est$summary$outcome)))
  }
})

test_that("a missing country falls back to the regional rows with a flag", {
  est <- estimate_output(tables, "P_POU_FILTER", units = 100, country = "Tanzania", who_region = "AFR", people_per_unit = 5,
                         baseline_source = "unimproved", verified_use = 0.9)
  expect_true("regional_substitute" %in% est$flags)
  expect_true(any(grepl("regional substitute", est$factors_used$flag)))
  expect_true(all(is.finite(est$summary$central)))
  expect_true(ordered(est$summary))
  expect_error(estimate_output(tables, "P_POU_FILTER", units = 1, country = "Atlantis", people_per_unit = 5), "who_region")
})

test_that("the factor list returned matches the rows used", {
  est <- estimate_output(tables, "P_POU_CHLOR", units = 500, country = "Kenya", baseline_source = "improved_not_on_premises",
                         verified_use = 0.5, years = 3, sth_prevalence = 0.2)
  ids <- est$factors_used$id
  expect_true(all(c("F_POU_CHLOR_FROM_IMPNP", "F_WAT_IMPNP_FROM_UNIMP", "ADJ_USE_CHLOR_REF", "ADJ_DECAY_POU", "ADJ_EPISODE_DURATION_U5",
                    "ADJ_PAF_CF_WATER", "F_STH_WASH_ANY", "ADJ_OR_TO_RR") %in% ids))
  expect_false("F_POU_CHLOR_FROM_UNIMP" %in% ids)
  used_baselines <- est$factors_used %>% filter(table == "baseline-disease") %>% pull(what)
  expect_true(any(grepl("household_size", used_baselines)))
  expect_true(any(grepl("paf_diarr_water", used_baselines)))
  expect_true(any(grepl("diarr_death_rate \\(under five", used_baselines)))
  expect_equal(nrow(est$factors_used), nrow(distinct(est$factors_used, table, id)))
  expect_true(all(nzchar(est$factors_used$citation[est$factors_used$table == "effects"])))
})

test_that("use and decay multipliers follow the rows", {
  a <- estimate_output(tables, "P_POU_CHLOR", units = 100, country = "Kenya", baseline_source = "unimproved", verified_use = 0.31)
  b <- estimate_output(tables, "P_POU_CHLOR", units = 100, country = "Kenya", baseline_source = "unimproved", verified_use = 0.62)
  c <- estimate_output(tables, "P_POU_CHLOR", units = 100, country = "Kenya", baseline_source = "unimproved", verified_use = 0.9)
  expect_equal(a$exposure_change$use_multiplier, 0.5)
  expect_equal(b$exposure_change$use_multiplier, 1)
  expect_equal(c$exposure_change$use_multiplier, 1)
  d <- estimate_output(tables, "P_POU_FILTER", units = 100, country = "Kenya", baseline_source = "unimproved", verified_use = 0.9, years = 3)
  expect_equal(d$exposure_change$year_weight, 1 + 2 * 0.62)
  e <- estimate_output(tables, "P_POU_FILTER", units = 100, country = "Kenya", baseline_source = "unimproved")
  expect_true("use_not_verified" %in% e$flags)
  expect_equal(e$confidence, "low") # moderate minus one step
})

test_that("the sanitation coverage threshold switches the effect row", {
  hi <- estimate_output(tables, "P_SAN_BASIC", units = 100, country = "Kenya", community_coverage_after = 0.8, verified_use = 1)
  lo <- estimate_output(tables, "P_SAN_BASIC", units = 100, country = "Kenya", community_coverage_after = 0.2, verified_use = 1)
  expect_equal(hi$exposure_change$effect_row, "F_SAN_BASIC_FROM_UNIMP")
  expect_equal(lo$exposure_change$effect_row, "F_SAN_BASIC_HHTARGET")
  expect_true("coverage_below_threshold" %in% lo$flags)
  expect_equal(lo$confidence, "very low")
  expect_true(hi$summary$central[hi$summary$outcome == "diarrhoea cases averted"] > lo$summary$central[lo$summary$outcome == "diarrhoea cases averted"])
})

test_that("label_confidence drops one step per downgrade flag and floors at very low", {
  expect_equal(label_confidence("moderate", character()), "moderate")
  expect_equal(label_confidence("moderate", c("use_not_verified")), "low")
  expect_equal(label_confidence("moderate", c("use_not_verified", "regional_substitute", "evidence_gap")), "very low")
  expect_equal(label_confidence("moderate", c("reporting_bias")), "moderate")
  expect_equal(label_confidence("very low", c("use_not_verified")), "very low")
  expect_equal(label_confidence(NA, character()), "not estimable")
})

test_that("mortality band and scenario difference run and agree in direction with the PAF route", {
  est <- estimate_output(tables, "P_CONN_HH", units = 2500, country = "Cambodia", baseline_source = "unimproved", verified_use = 1, residence = "rural")
  band <- estimate_mortality_band(tables, "P_CONN_HH", units = 2500, country = "Cambodia")
  expect_true(all(band$band$low <= band$band$central & band$band$central <= band$band$high))
  sc <- estimate_scenario_difference(tables, "Cambodia", "water", "unimproved", "basic (not safely managed)", people = est$people, residence = "rural",
                                     to_rr = get_effect(tables, "F_WAT_PREM_FROM_UNIMP")$central)
  paf_deaths <- est$summary$central[est$summary$outcome == "diarrhoea deaths averted" & est$summary$population_group == "all ages"]
  sc_deaths <- sc$result$deaths_averted[sc$result$population_group == "all ages"]
  expect_true(sc_deaths > 0)
  expect_true(abs(log(sc_deaths / paf_deaths)) < log(3)) # same order of magnitude; the normalisations differ by design
  expect_true(sc$paf_reimplemented > 0 && sc$paf_reimplemented < 1)
})
