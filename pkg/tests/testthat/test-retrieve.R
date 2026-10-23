test_that("the factor tables load with the expected names and a version stamp", {
  tables <- factor_tables()
  expect_setequal(names(tables), c("effects", "adjustments", "baselines", "exposure", "pathways", "schema"))
  expect_match(factors_version(), "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9a-f]{7,}")
  expect_equal(attr(effects, "factors_version"), factors_version())
  expect_true(is.numeric(effects$central))
  expect_true(is.integer(baseline_disease$year))
  for (tbl in c("effects", "adjustments", "pathways", "baseline-disease", "baseline-exposure")) {
    obj <- switch(tbl, "baseline-disease" = tables$baselines, "baseline-exposure" = tables$exposure, tables[[tbl]])
    expect_setequal(names(obj), tables$schema$column[tables$schema$table == tbl])
  }
})

test_that("the package copy of the tables matches the stamped CSV files", {
  f <- system.file("extdata", "effects.csv", package = "washhealth")
  csv <- utils::read.csv(f, colClasses = "character", check.names = FALSE)
  expect_equal(csv$factor_id, effects$factor_id)
  expect_equal(as.numeric(csv$central), effects$central)
})

test_that("retrieval functions return rows or clear errors", {
  expect_equal(nrow(get_effect("F_POU_FILTER_FROM_UNIMP")), 1)
  expect_error(get_effect("F_NOPE"), "effect row not found")
  expect_error(get_adjustment("ADJ_NOPE"), "adjustment row not found")
  expect_error(get_pathway("P_NOPE"), "pathway not found")
  b <- get_baseline("Kenya", "household_size")
  expect_false(b$fallback)
  expect_true(b$value > 1)
  r <- get_baseline("Tanzania", "diarr_death_rate", "all ages", who_region = "AFR")
  expect_true(r$fallback)
  expect_match(r$flag, "regional substitute")
  m <- get_baseline("Kenya", "sth_prevalence")
  expect_true(is.na(m$value))
  expect_match(m$flag, "not pulled|missing")
  expect_true(is.na(get_exposure("Kenya", "water", "safely managed", "national")) || is.numeric(get_exposure("Kenya", "water", "safely managed", "national")))
  expect_null(get_exposure_row("Kenya", "water", "no such level"))
  expect_equal(who_region_of("Cambodia"), "WPR")
})

test_that("countries and output types are listed", {
  expect_length(countries(), 11)
  expect_true(all(c("Kenya", "Cambodia", "India") %in% countries()))
  ot <- output_types()
  expect_equal(nrow(ot), nrow(pathways))
  expect_true("household water filter" %in% ot$output_type)
})

test_that("format_number formats the way the reports do", {
  expect_equal(format_number(c(12345.6, 23.456, 0.1234, 0, NA)), c("12 346", "23.5", "0.123", "0", ""))
})
