# The report and the app run in a separate R process (Quarto) or source the app
# file with library(washhealth); both need the package installed in a library.
installed <- "washhealth" %in% rownames(utils::installed.packages())

test_that("the report template and the app folder ship with the package", {
  expect_true(file.exists(report_template_path()))
  expect_true(file.exists(file.path(system.file("app", package = "washhealth"), "app.R")))
  expect_true(is.character(quarto_bin()))
})

test_that("the app shows the experimental banner above the tabs", {
  app <- paste(readLines(file.path(system.file("app", package = "washhealth"), "app.R"), warn = FALSE), collapse = "\n")
  expect_match(app, "header = experimental_banner", fixed = TRUE)
  expect_match(app, "not fully reviewed", fixed = TRUE)
})

test_that("the transaction report renders for one enterprise", {
  skip_on_cran()
  skip_if_not(installed, "washhealth is not installed in a library")
  skip_if_not(nzchar(quarto_bin()), "Quarto not found")
  skip_if_not_installed("knitr")
  skip_if_not_installed("rmarkdown")
  tx <- example_transactions()
  out_dir <- file.path(tempdir(), "report-test")
  f <- render_transaction_report(tx[tx$enterprise == "Aqua Clara Kenya", ], output_dir = out_dir, file = "test-report.html")
  expect_true(file.exists(f))
  html <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_match(html, factors_version(), fixed = TRUE)
  expect_match(html, "Aqua Clara Kenya: estimated health outcomes", fixed = TRUE)
  expect_match(html, "Factor rows used", fixed = TRUE)
  expect_match(html, "Communication rules applied", fixed = TRUE)
  expect_false(grepl("prevented", html))
  unlink(out_dir, recursive = TRUE)
})

test_that("the app server logic runs a scenario and an ex-post estimate", {
  skip_on_cran()
  skip_if_not_installed("shiny")
  skip_if_not(installed, "washhealth is not installed in a library")
  app_dir <- system.file("app", package = "washhealth")
  shiny::testServer(app_dir, {
    session$setInputs(ante_country = "Kenya", ante_output_type = "P_POU_FILTER", ante_quantity = 2000, ante_residence = "rural",
                      ante_period = as.Date(c("2027-01-01", "2027-12-31")), ante_use_rate = 0.9, ante_use_known = TRUE,
                      ante_baseline_source = "unimproved", ante_incentive_share = 0.4, ante_share_known = TRUE,
                      ante_baseline_method = "pre-incentive trend", ante_coverage = NA, ante_water_quality = FALSE,
                      ante_people_per_unit = NA, ante_sth = NA, ante_promotion = FALSE)
    session$setInputs(ante_go = 1)
    r <- ante_state()
    expect_s3_class(r, "washhealth_results")
    expect_equal(r$mode, "ex-ante")
    expect_true(any(r$results$scope == "planned total"))
    expect_equal(r$estimates[[1]]$confidence, "moderate")
    session$setInputs(post_country = "Cambodia", post_output_type = "P_CONN_HH", post_quantity = 2500, post_residence = "rural",
                      post_period = as.Date(c("2025-01-01", "2025-12-31")), post_use_rate = 1, post_use_known = TRUE,
                      post_baseline_source = "", post_incentive_share = 0.5, post_share_known = TRUE, post_baseline_method = "",
                      post_verified_by = "Verifier", post_verification_date = as.Date("2026-02-01"), post_coverage = NA,
                      post_water_quality = FALSE, post_people_per_unit = NA, post_sth = NA, post_promotion = FALSE)
    session$setInputs(post_go = 1)
    p <- post_state()
    expect_s3_class(p, "washhealth_results")
    expect_equal(p$mode, "ex-post")
    expect_true("baseline_source_assumed" %in% p$estimates[[1]]$flags)
    # a validation error is shown, not thrown
    session$setInputs(post_quantity = -5)
    session$setInputs(post_go = 2)
    expect_true(inherits(post_state(), "error"))
  })
})
