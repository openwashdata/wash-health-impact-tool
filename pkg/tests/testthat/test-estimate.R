tables <- factor_tables()
ordered <- function(s) all(s$low <= s$central + 1e-9 & s$central <= s$high + 1e-9, na.rm = TRUE)
needs_ppu <- c("P_CONN_INST", "P_WATERPOINT", "P_MHH")

test_that("every pathway runs and returns an ordered low, central, high", {
  for (pid in tables$pathways$pathway_id) {
    est <- estimate_output(pid, units = 100, country = "Kenya", baseline_source = "unimproved", verified_use = 0.8,
                           community_coverage_after = 0.7, promotion_contact = TRUE,
                           people_per_unit = if (pid %in% needs_ppu) 50 else NA)
    expect_s3_class(est, "washhealth_estimate")
    expect_true(nrow(est$summary) >= 1, info = pid)
    expect_true(ordered(est$summary), info = pid)
    expect_true(est$confidence %in% confidence_levels(), info = pid)
    expect_equal(est$factors_version, factors_version())
  }
})

test_that("the output type label works in place of the pathway id", {
  a <- estimate_output("P_POU_FILTER", 100, "Kenya", baseline_source = "unimproved", verified_use = 0.9)
  b <- estimate_output("household water filter", 100, "Kenya", baseline_source = "unimproved", verified_use = 0.9)
  expect_equal(a$summary, b$summary)
  expect_error(estimate_output("solar panel", 100, "Kenya"), "not in the pathway table")
})

test_that("pathways with a required persons-per-unit input refuse to use the household size", {
  for (pid in needs_ppu) expect_error(estimate_output(pid, 10, "Kenya"), "needs people_per_unit")
})

test_that("reach-only pathways report people and no health conversion", {
  for (pid in c("P_CONN_INST", "P_FSM_EMPTYING", "P_MHH")) {
    est <- estimate_output(pid, units = 10, country = "Cambodia", people_per_unit = 300)
    expect_equal(est$people, 3000)
    expect_equal(est$confidence, "not estimable")
    expect_false(any(grepl("averted", est$summary$outcome)))
    expect_null(est$exposure_change)
  }
})

test_that("a missing country falls back to the regional rows with a flag", {
  est <- estimate_output("P_POU_FILTER", units = 100, country = "Tanzania", who_region = "AFR", people_per_unit = 5,
                         baseline_source = "unimproved", verified_use = 0.9)
  expect_true("regional_substitute" %in% est$flags)
  expect_true(any(grepl("regional substitute", est$factors_used$flag)))
  expect_true(all(is.finite(est$summary$central)))
  expect_true(ordered(est$summary))
  expect_error(estimate_output("P_POU_FILTER", units = 1, country = "Atlantis", people_per_unit = 5), "who_region")
  expect_error(estimate_output("P_POU_FILTER", units = 1, country = "Atlantis", people_per_unit = 5, who_region = "EUR"), "no regional rows")
})

test_that("the factor list returned matches the rows used", {
  est <- estimate_output("P_POU_CHLOR", units = 500, country = "Kenya", baseline_source = "improved_not_on_premises",
                         verified_use = 0.5, years = 3, sth_prevalence = 0.2)
  ids <- est$factors_used$id
  expect_true(all(c("F_POU_CHLOR_FROM_IMPNP", "F_WAT_IMPNP_FROM_UNIMP", "ADJ_USE_CHLOR_REF", "ADJ_DECAY_POU", "ADJ_EPISODE_DURATION_U5",
                    "ADJ_PAF_CF_WATER", "F_STH_WASH_ANY", "ADJ_OR_TO_RR") %in% ids))
  expect_false("F_POU_CHLOR_FROM_UNIMP" %in% ids)
  used_baselines <- est$factors_used$what[est$factors_used$table == "baseline-disease"]
  expect_true(any(grepl("household_size", used_baselines)))
  expect_true(any(grepl("paf_diarr_water", used_baselines)))
  expect_true(any(grepl("diarr_death_rate \\(under five", used_baselines)))
  expect_equal(nrow(est$factors_used), nrow(unique(est$factors_used[c("table", "id")])))
  expect_true(all(nzchar(est$factors_used$citation[est$factors_used$table == "effects"])))
})

test_that("use and decay multipliers follow the rows", {
  a <- estimate_output("P_POU_CHLOR", units = 100, country = "Kenya", baseline_source = "unimproved", verified_use = 0.31)
  b <- estimate_output("P_POU_CHLOR", units = 100, country = "Kenya", baseline_source = "unimproved", verified_use = 0.62)
  c <- estimate_output("P_POU_CHLOR", units = 100, country = "Kenya", baseline_source = "unimproved", verified_use = 0.9)
  expect_equal(a$exposure_change$use_multiplier, 0.5)
  expect_equal(b$exposure_change$use_multiplier, 1)
  expect_equal(c$exposure_change$use_multiplier, 1)
  d <- estimate_output("P_POU_FILTER", units = 100, country = "Kenya", baseline_source = "unimproved", verified_use = 0.9, years = 3)
  expect_equal(d$exposure_change$year_weight, 1 + 2 * 0.62)
  e <- estimate_output("P_POU_FILTER", units = 100, country = "Kenya", baseline_source = "unimproved")
  expect_true("use_not_verified" %in% e$flags)
  expect_equal(e$confidence, "low") # moderate minus one step
})

test_that("a fraction of a year counts that share of year one", {
  full <- estimate_output("P_POU_FILTER", 100, "Kenya", baseline_source = "unimproved", verified_use = 0.9, years = 1)
  half <- estimate_output("P_POU_FILTER", 100, "Kenya", baseline_source = "unimproved", verified_use = 0.9, years = 0.5)
  expect_equal(half$exposure_change$year_weight, 0.5)
  cases <- function(x) x$summary$central[x$summary$outcome == "diarrhoea cases averted"]
  expect_equal(cases(half), cases(full) / 2)
  expect_error(estimate_output("P_POU_FILTER", 100, "Kenya", years = 0), "years")
})

test_that("the sanitation coverage threshold switches the effect row", {
  hi <- estimate_output("P_SAN_BASIC", units = 100, country = "Kenya", community_coverage_after = 0.8, verified_use = 1)
  lo <- estimate_output("P_SAN_BASIC", units = 100, country = "Kenya", community_coverage_after = 0.2, verified_use = 1)
  expect_equal(hi$exposure_change$effect_row, "F_SAN_BASIC_FROM_UNIMP")
  expect_equal(lo$exposure_change$effect_row, "F_SAN_BASIC_HHTARGET")
  expect_true("coverage_below_threshold" %in% lo$flags)
  expect_equal(lo$confidence, "very low")
  expect_true(hi$summary$central[hi$summary$outcome == "diarrhoea cases averted"] > lo$summary$central[lo$summary$outcome == "diarrhoea cases averted"])
})

test_that("missing sanitation coverage falls back to the JMP value with a flag and a ledger row", {
  est <- estimate_output("P_CBS", units = 500, country = "Cambodia", residence = "rural", verified_use = 0.9)
  expect_true("coverage_from_jmp" %in% est$flags)
  jmp <- get_exposure("Cambodia", "sanitation", "at least basic", "rural")
  expect_equal(est$inputs$community_coverage_after, jmp / 100)
  expect_true(any(est$factors_used$table == "baseline-exposure"))
  expect_true(est$exposure_change$effect_row %in% c("F_SAN_BASIC_FROM_UNIMP", "F_SAN_BASIC_HHTARGET"))
  given <- estimate_output("P_CBS", units = 500, country = "Cambodia", residence = "rural", verified_use = 0.9, community_coverage_after = jmp / 100)
  expect_equal(given$summary$central, est$summary$central)
  expect_false("coverage_from_jmp" %in% given$flags)
})

test_that("label_confidence drops one step per downgrade flag and floors at very low", {
  expect_equal(label_confidence("moderate", character()), "moderate")
  expect_equal(label_confidence("moderate", c("use_not_verified")), "low")
  expect_equal(label_confidence("moderate", c("use_not_verified", "regional_substitute", "evidence_gap")), "very low")
  expect_equal(label_confidence("moderate", c("reporting_bias")), "moderate")
  expect_equal(label_confidence("very low", c("use_not_verified")), "very low")
  expect_equal(label_confidence(NA, character()), "not estimable")
  expect_equal(label_confidence("moderate", c("use_not_verified", "use_not_verified")), "low")
})

test_that("every flag the engine sets is in the flag dictionary", {
  fl <- confidence_flags()
  expect_setequal(fl$effect, c("downgrade", "note"))
  seen <- character()
  seen <- c(seen, estimate_output("P_CBS", 10, "Cambodia", residence = "rural")$flags)
  seen <- c(seen, estimate_output("P_POU_CHLOR", 10, "Tanzania", who_region = "AFR", people_per_unit = 5, years = 2)$flags)
  seen <- c(seen, estimate_output("P_SAN_BASIC", 10, "Kenya", community_coverage_after = 0.1)$flags)
  seen <- c(seen, estimate_output("P_HYG_PRODUCT", 10, "Kenya")$flags)
  seen <- c(seen, estimate_output("P_CONN_HH", 10, "Kenya")$flags)
  expect_true(all(unique(seen) %in% fl$flag))
})

test_that("mortality band and WHO scenario comparison run and agree in direction with the PAF route", {
  est <- estimate_output("P_CONN_HH", units = 2500, country = "Cambodia", baseline_source = "unimproved", verified_use = 1, residence = "rural")
  band <- estimate_mortality_band("P_CONN_HH", units = 2500, country = "Cambodia")
  expect_true(all(band$band$low <= band$band$central & band$band$central <= band$band$high))
  sc <- compare_who_scenario("Cambodia", "water", "unimproved", "basic (not safely managed)", people = est$people, residence = "rural",
                             to_rr = get_effect("F_WAT_PREM_FROM_UNIMP")$central)
  paf_deaths <- est$summary$central[est$summary$outcome == "diarrhoea deaths averted" & est$summary$population_group == "all ages"]
  sc_deaths <- sc$result$deaths_averted[sc$result$population_group == "all ages"]
  expect_true(sc_deaths > 0)
  expect_true(abs(log(sc_deaths / paf_deaths)) < log(3)) # same order of magnitude; the normalisations differ by design
  expect_true(sc$paf_reimplemented > 0 && sc$paf_reimplemented < 1)
})

test_that("the worked example values of stage 2 are reproduced", {
  ack <- estimate_output("P_POU_FILTER", units = 1000, country = "Kenya", residence = "rural", baseline_source = "unimproved", verified_use = 0.93)
  cases <- ack$summary[ack$summary$outcome == "diarrhoea cases averted", ]
  expect_equal(round(cases$central), 681)
  expect_equal(round(cases$low), 545)
  expect_equal(round(cases$high), 803)
  expect_equal(ack$confidence, "moderate")
  expect_equal(round(ack$people), 3700)
  kwsh <- estimate_output("P_CONN_HH", units = 2500, country = "Cambodia", residence = "rural", baseline_source = "unimproved", verified_use = 1)
  expect_equal(round(kwsh$summary$central[kwsh$summary$outcome == "diarrhoea cases averted"]), 272)
  expect_equal(kwsh$confidence, "very low")
})

test_that("bind_estimates and the print method work", {
  a <- estimate_output("P_POU_FILTER", 100, "Kenya", baseline_source = "unimproved", verified_use = 0.9)
  b <- estimate_output("P_CONN_INST", 2, "Kenya", people_per_unit = 400)
  bound <- bind_estimates(a, b)
  expect_equal(nrow(bound), nrow(a$summary) + nrow(b$summary))
  expect_equal(nrow(bind_estimates(list(a, b))), nrow(bound))
  expect_output(print(a), "Confidence label: moderate")
})
