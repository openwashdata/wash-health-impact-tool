test_that("the factor export writes one flat CSV per table plus a data dictionary and a version sheet", {
  dir <- file.path(tempdir(), "factors-csv")
  files <- export_factors(dir)
  expect_setequal(basename(files), c("effects.csv", "adjustments.csv", "pathways.csv", "baseline_disease.csv", "baseline_disease_wide.csv",
                                     "baseline_exposure.csv", "baseline_exposure_wide.csv", "factor_cards.csv", "data_dictionary.csv", "version.csv"))
  wide <- utils::read.csv(file.path(dir, "baseline_disease_wide.csv"), check.names = FALSE)
  expect_true(all(c("country", "population_group", "household_size", "diarr_death_rate", "paf_diarr_water") %in% names(wide)))
  expect_equal(wide$household_size[wide$country == "Kenya" & wide$population_group == "all ages"], get_baseline("Kenya", "household_size")$value)
  xw <- utils::read.csv(file.path(dir, "baseline_exposure_wide.csv"), check.names = FALSE)
  expect_equal(xw[xw$country == "Cambodia" & xw$residence == "rural", "sanitation: at least basic"], get_exposure("Cambodia", "sanitation", "at least basic", "rural"))
  dict <- utils::read.csv(file.path(dir, "data_dictionary.csv"), check.names = FALSE)
  for (tbl in c("baseline_disease_wide", "baseline_exposure_wide", "factor_cards", "version")) {
    cols <- names(utils::read.csv(file.path(dir, paste0(tbl, ".csv")), check.names = FALSE))
    expect_true(all(cols %in% dict$column[dict$table == tbl]), info = tbl)
  }
  ver <- utils::read.csv(file.path(dir, "version.csv"))
  expect_equal(ver$value[ver$item == "factors_version"], factors_version())
  eff <- utils::read.csv(file.path(dir, "effects.csv"), check.names = FALSE)
  expect_equal(nrow(eff), nrow(effects))
})

test_that("factor cards resolve to effect rows and cover every pathway", {
  cards <- factor_cards()
  expect_setequal(unique(cards$pathway_id), pathways$pathway_id)
  with_row <- cards[!is.na(cards$effect_row), ]
  expect_true(all(with_row$effect_row %in% effects$factor_id))
  expect_equal(with_row$central, effects$central[match(with_row$effect_row, effects$factor_id)])
  conn <- cards[cards$pathway_id == "P_CONN_HH", ]
  expect_equal(nrow(conn), 4) # two baseline sources x water quality verified or not
  san <- cards[cards$pathway_id == "P_SAN_BASIC", ]
  expect_setequal(san$effect_row, c("F_SAN_BASIC_FROM_UNIMP", "F_SAN_BASIC_HHTARGET"))
  expect_true(all(cards$certainty[cards$pathway_id %in% c("P_CONN_INST", "P_FSM_EMPTYING", "P_MHH")] == "not estimable"))
})

test_that("the xlsx export writes one workbook when writexl is installed", {
  skip_if_not_installed("writexl")
  f <- file.path(tempdir(), "factors.xlsx")
  out <- export_factors(f, format = "xlsx")
  expect_true(file.exists(out))
  expect_gt(file.size(out), 10000)
})

test_that("results export writes results, ledger, notes, transactions, portfolio and run", {
  res <- estimate_transaction(example_transactions())
  dir <- file.path(tempdir(), "results-csv")
  files <- export_results(res, dir)
  expect_setequal(basename(files), c("results.csv", "ledger.csv", "notes.csv", "transactions.csv", "portfolio.csv", "run.csv"))
  r <- utils::read.csv(file.path(dir, "results.csv"))
  expect_equal(nrow(r), nrow(res$results))
  run <- utils::read.csv(file.path(dir, "run.csv"))
  expect_equal(run$value[run$item == "factors_version"], factors_version())
  skip_if_not_installed("writexl")
  f <- export_results(res, file.path(tempdir(), "results.xlsx"), format = "xlsx")
  expect_true(file.exists(f))
})
