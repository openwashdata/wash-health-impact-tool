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

test_that("superseded rows are kept but never retrieved", {
  tables <- factor_tables()
  expect_true(all(c("superseded_by") %in% names(tables$effects)))
  expect_equal(nrow(current_rows(tables$effects)), nrow(tables$effects)) # no superseded rows yet
  # supersede the filter row: new value, same id, later valid_from; the old row points at the new date
  e <- tables$effects
  old <- e[e$factor_id == "F_POU_FILTER_FROM_UNIMP", ]
  new <- old; new$central <- 0.55; new$valid_from <- "2027-01-01"; new$notes <- "test replacement"
  e$superseded_by[e$factor_id == "F_POU_FILTER_FROM_UNIMP"] <- "2027-01-01"
  tables$effects <- rbind(e, new)
  expect_equal(get_effect("F_POU_FILTER_FROM_UNIMP", tables)$central, 0.55)
  est <- estimate_output("P_POU_FILTER", 100, "Kenya", baseline_source = "unimproved", verified_use = 0.9, tables = tables)
  expect_equal(est$exposure_change$relative_risk, 0.55)
  # two current rows for one id is an error, and an id with only superseded rows is an error
  tables$effects$superseded_by[tables$effects$factor_id == "F_POU_FILTER_FROM_UNIMP"] <- ""
  expect_error(get_effect("F_POU_FILTER_FROM_UNIMP", tables), "2 current rows")
  tables$effects$superseded_by[tables$effects$factor_id == "F_POU_FILTER_FROM_UNIMP"] <- "2028-01-01"
  expect_error(get_effect("F_POU_FILTER_FROM_UNIMP", tables), "only as superseded rows")
  tables$effects <- factor_tables()$effects # restore before the pathway part
  p <- tables$pathways
  p$superseded_by[p$pathway_id == "P_MHH"] <- "2027-01-01"
  tables$pathways <- p
  expect_false("P_MHH" %in% output_types(tables)$pathway_id)
  expect_false("P_MHH" %in% factor_cards(tables)$pathway_id)
  expect_equal(nrow(current_rows(data.frame(a = 1:2))), 2)
})

test_that("retrieval functions return rows or clear errors", {
  expect_equal(nrow(get_effect("F_POU_FILTER_FROM_UNIMP")), 1)
  expect_error(get_effect("F_NOPE"), "effect row not found")
  expect_error(get_adjustment("ADJ_NOPE"), "adjustment row not found")
  expect_error(get_pathway("P_NOPE"), "pathway row not found")
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
