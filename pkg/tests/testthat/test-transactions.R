write_tx <- function(df) {
  f <- tempfile(fileext = ".csv")
  utils::write.csv(df, f, row.names = FALSE, na = "")
  f
}
base_row <- function(...) {
  d <- data.frame(transaction_id = "TX-1", enterprise = "Co", country = "Kenya", output_type = "household water filter",
                  period_start = "2026-01-01", period_end = "2026-12-31", quantity = "1000", unit = "filters", verified_by = "V",
                  verification_date = "2027-01-10", use_rate = "0.9", baseline_source = "unimproved", incentive_share = "0.4",
                  notes = "", stringsAsFactors = FALSE)
  mods <- list(...)
  for (n in names(mods)) d[[n]] <- mods[[n]]
  d
}

test_that("the template and the examples read and validate", {
  tx <- read_transactions(transaction_template_path())
  expect_s3_class(tx, "washhealth_transactions")
  expect_equal(tx$pathway_id, "P_POU_FILTER")
  expect_equal(tx$service_years, 1)
  expect_s3_class(tx$period_start, "Date")
  ex <- example_transactions()
  expect_equal(nrow(ex), 5)
  expect_true(all(ex$pathway_id %in% pathways$pathway_id))
  cols <- transaction_columns()
  expect_equal(sum(cols$required), 14)
  expect_true(all(cols$column %in% names(tx)))
})

test_that("missing required columns stop with the list of columns", {
  d <- base_row(); d$quantity <- NULL; d$unit <- NULL
  expect_error(read_transactions(write_tx(d)), "missing required columns: quantity, unit")
  expect_error(as_transactions(list(a = 1)), "data frame")
  expect_error(read_transactions(tempfile()), "file not found")
})

test_that("value problems are collected into one message", {
  d <- base_row(country = "Atlantis", output_type = "solar panel", quantity = "many", use_rate = "90", period_end = "2025-12-31",
                incentive_share = "1.5", baseline_source = "river")
  err <- tryCatch(as_transactions(d), error = function(e) conditionMessage(e))
  expect_match(err, "7 problems")
  expect_match(err, "country 'Atlantis'")
  expect_match(err, "output_type 'solar panel'")
  expect_match(err, "quantity 'many'")
  expect_match(err, "use_rate must be a share")
  expect_match(err, "period_end is before period_start")
  expect_match(err, "incentive_share must be a share")
  expect_match(err, "baseline_source 'river'")
  expect_error(as_transactions(base_row(period_start = "01/01/2026")), "not a date")
  expect_error(as_transactions(base_row(verification_date = "soon")), "verification_date")
  expect_error(as_transactions(base_row(residence = "coastal")), "residence")
  expect_error(as_transactions(base_row(water_quality_verified = "maybe")), "TRUE or FALSE")
  expect_error(as_transactions(base_row(people_per_unit = "-3")), "people_per_unit")
  expect_error(as_transactions(base_row(output_type = "school or clinic connection")), "needs people_per_unit")
  expect_error(as_transactions(base_row(transaction_id = "")), "transaction_id is empty")
})

test_that("an unknown country works with a WHO region and synonyms are accepted", {
  tx <- as_transactions(base_row(country = "Tanzania", who_region = "afr", baseline_source = "surface water", residence = "Rural",
                                 water_quality_verified = "yes"))
  expect_equal(tx$who_region, "AFR")
  expect_equal(tx$baseline_source, "unimproved")
  expect_equal(tx$residence, "rural")
  expect_true(tx$water_quality_verified)
  expect_error(as_transactions(base_row(country = "Tanzania", who_region = "EUR")), "who_region 'EUR'")
})

test_that("the incentive share is derived from the baseline quantity when empty", {
  tx <- as_transactions(base_row(incentive_share = "", baseline_quantity = "600"))
  expect_equal(tx$incentive_share, 0.4)
  tx2 <- as_transactions(base_row(incentive_share = "0.25", baseline_quantity = "600"))
  expect_equal(tx2$incentive_share, 0.25)
  tx3 <- as_transactions(base_row(incentive_share = "", baseline_quantity = "2000"))
  expect_equal(tx3$incentive_share, 0)
})

test_that("new_transaction builds a valid row and unknown columns are kept with a message", {
  tx <- new_transaction("T", "Co", "Kenya", "household water filter", 10, "2026-01-01", "2026-06-30", use_rate = 0.5)
  expect_equal(nrow(tx), 1)
  expect_equal(tx$service_years, 0.5)
  expect_equal(tx$unit, "filters sold and in use")
  d <- base_row(); d$extra <- "x"
  expect_message(as_transactions(d), "not used by the chain: extra")
  expect_warning(as_transactions(rbind(base_row(), base_row())), "Duplicate rows")
})

test_that("ex-post runs need verification unless told otherwise", {
  d <- base_row(verified_by = "", verification_date = "")
  expect_error(estimate_transaction(d), "needs verified_by and verification_date")
  res <- estimate_transaction(d, require_verification = FALSE)
  expect_true(all(grepl("output_not_verified", res$results$flags)))
  expect_equal(unique(res$results$confidence), "low") # moderate minus one step for the missing verification
  ok <- estimate_transaction(base_row())
  expect_equal(unique(ok$results$confidence), "moderate")
})

test_that("results carry totals and attributable rows scaled by the incentive share", {
  res <- estimate_transaction(base_row())
  expect_s3_class(res, "washhealth_results")
  expect_equal(res$mode, "ex-post")
  r <- res$results
  expect_setequal(unique(r$scope), c("verified total", "incentive-attributable"))
  tot <- r[r$scope == "verified total" & r$outcome == "diarrhoea cases averted", ]
  att <- r[r$scope == "incentive-attributable" & r$outcome == "diarrhoea cases averted", ]
  expect_equal(att$central, tot$central * 0.4)
  expect_equal(att$low, tot$low * 0.4)
  expect_true(any(grepl("per household-year", r$outcome[r$scope == "verified total"])))
  expect_false(any(grepl("per household-year", r$outcome[r$scope == "incentive-attributable"])))
  expect_equal(res$factors_version, factors_version())
  expect_true(all(c("transaction_id", "output_type", "table", "id", "citation") %in% names(res$ledger)))
  expect_output(print(res), "ex-post")
})

test_that("a missing incentive share leaves the attributable rows empty with a flag", {
  res <- estimate_transaction(base_row(incentive_share = ""))
  att <- res$results[res$results$scope == "incentive-attributable", ]
  expect_true(all(is.na(att$central)))
  expect_true(all(grepl("incentive_share_missing", att$flags)))
  expect_true(any(grepl("attributable rows are empty", res$notes$note)))
})

test_that("ex-ante scenarios label planned totals and treat the use rate as a target", {
  plan <- new_transaction("PLAN", "Co", "Kenya", "household water filter", 2000, "2027-01-01", "2027-12-31", use_rate = 0.9, baseline_quantity = 1200)
  res <- estimate_scenario(plan)
  expect_equal(res$mode, "ex-ante")
  expect_setequal(unique(res$results$scope), c("planned total", "incentive-attributable"))
  expect_true(all(grepl("use_is_target", res$results$flags)))
  tot <- res$results[res$results$scope == "planned total" & res$results$outcome == "people reached", ]
  att <- res$results[res$results$scope == "incentive-attributable" & res$results$outcome == "people reached", ]
  expect_equal(att$central / tot$central, 0.4)
  # the scenario with the baseline quantity equals the difference of two runs (the chain is linear in units)
  full <- estimate_scenario(new_transaction("A", "Co", "Kenya", "household water filter", 2000, "2027-01-01", "2027-12-31", use_rate = 0.9))
  base <- estimate_scenario(new_transaction("B", "Co", "Kenya", "household water filter", 1200, "2027-01-01", "2027-12-31", use_rate = 0.9))
  cases <- function(x, scope) x$results$central[x$results$scope == scope & x$results$outcome == "diarrhoea cases averted"]
  expect_equal(cases(res, "incentive-attributable"), cases(full, "planned total") - cases(base, "planned total"))
})

test_that("the portfolio summary sums rows and takes the worst label", {
  res <- estimate_transaction(example_transactions())
  port <- summarise_portfolio(res)
  reach <- port[port$scope == "verified total" & port$outcome == "people reached", ]
  expect_equal(reach$central, sum(res$results$central[res$results$scope == "verified total" & res$results$outcome == "people reached"]))
  expect_equal(reach$n_transactions, 4)
  expect_equal(reach$confidence, "not estimable") # the institutional row is reach only
  cases <- port[port$scope == "verified total" & port$outcome == "diarrhoea cases averted", ]
  expect_equal(cases$confidence, "very low")
  expect_true(cases$low <= cases$central && cases$central <= cases$high)
  by_ent <- summarise_portfolio(res, by = c("enterprise", "scope", "outcome", "population_group"))
  expect_true(all(c("KWSH", "Tap Effect", "Aqua Clara Kenya", "ATEC") %in% by_ent$enterprise))
  expect_error(summarise_portfolio(res, by = "nope"), "not result columns")
})

test_that("every ledger citation resolves to a row in the tables", {
  res <- estimate_transaction(example_transactions())
  chk <- check_ledger(res)
  expect_equal(nrow(chk), nrow(res$ledger))
  expect_true(all(chk$found[!is.na(chk$found)]))
  expect_true(all(chk$citation_matches[!is.na(chk$citation_matches)]))
  expect_true(all(c("effects", "adjustments", "baseline-disease", "baseline-exposure") %in% chk$table))
  est <- estimate_output("P_POU_CHLOR", 10, "Tanzania", who_region = "AFR", people_per_unit = 5, sth_prevalence = 0.1)
  chk2 <- check_ledger(est)
  expect_true(all(chk2$found[!is.na(chk2$found)]))
  bad <- est$factors_used
  bad$citation[1] <- "someone else"
  expect_false(all(check_ledger(bad)$citation_matches, na.rm = TRUE))
})
