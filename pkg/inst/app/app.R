# The openwashdata brand (colours, fonts, logo) comes from the bundled _brand.yml,
# the same file openwashdata/brand publishes; bslib reads it at start-up.
# Shiny runs app.R with the app folder as working directory; otherwise use the installed copy.
app_dir <- if (file.exists("_brand.yml")) "." else system.file("app", package = "washhealth")
shiny::addResourcePath("owd-logos", file.path(app_dir, "logos"))
# The brand needs the brand.yml package; without it the app runs on the plain Bootstrap theme.
app_theme <- if (requireNamespace("brand.yml", quietly = TRUE)) {
  bslib::bs_theme(version = 5, brand = file.path(app_dir, "_brand.yml"))
} else {
  message("Package brand.yml is not installed; the app runs without the openwashdata brand.")
  bslib::bs_theme(version = 5)
}
# washhealth Shiny app: ex-ante scenarios and ex-post estimates from the same
# factor tables. Launch with washhealth::run_app(). One file; every number
# comes from the package functions.

library(shiny)
library(washhealth)

has_bslib <- requireNamespace("bslib", quietly = TRUE)
tables <- factor_tables()
types <- output_types(tables)
type_choices <- stats::setNames(types$pathway_id, paste0(types$output_type, " (", types$unit_of_output, ")"))
country_choices <- c(countries(tables), "Other country (regional fallback)")
methodology_url <- getOption("washhealth.methodology_url", NULL)
flag_dict <- confidence_flags()

# ---- input panel used by both tabs ------------------------------------------------

input_panel <- function(id, mode) {
  ns <- function(x) paste0(id, "_", x)
  ante <- mode == "ex-ante"
  tagList(
    selectInput(ns("country"), "Country", country_choices, selected = "Kenya"),
    conditionalPanel(sprintf("input.%s == 'Other country (regional fallback)'", ns("country")),
                     textInput(ns("country_name"), "Country name", ""),
                     selectInput(ns("who_region"), "WHO region", c("AFR", "SEAR", "WPR"))),
    selectInput(ns("output_type"), "Output type", type_choices, selected = "P_POU_FILTER"),
    numericInput(ns("quantity"), if (ante) "Planned quantity (units)" else "Verified quantity (units)", 1000, min = 0, step = 1),
    selectInput(ns("residence"), "Setting", c("rural", "urban", "national"), selected = "rural"),
    dateRangeInput(ns("period"), if (ante) "Planning period" else "Reporting period", start = paste0(format(Sys.Date(), "%Y"), "-01-01"),
                   end = paste0(format(Sys.Date(), "%Y"), "-12-31")),
    sliderInput(ns("use_rate"), if (ante) "Target use rate (share of units in use)" else "Verified use rate (share of units in use)", 0, 1, 0.9, step = 0.01),
    checkboxInput(ns("use_known"), if (ante) "A use target is set" else "Use was verified", TRUE),
    selectInput(ns("baseline_source"), "Baseline water source of the customers",
                c("not known (assumed unimproved, flagged)" = "", "unimproved or surface water" = "unimproved",
                  "improved source off premises" = "improved_not_on_premises")),
    sliderInput(ns("incentive_share"), "Incentive-attributable share of the outputs", 0, 1, 0.5, step = 0.01),
    checkboxInput(ns("share_known"), "An incentive-attributable share is set (from the baseline trajectory)", TRUE),
    textInput(ns("baseline_method"), "Baseline trajectory method", if (ante) "pre-incentive trend" else ""),
    if (!ante) textInput(ns("verified_by"), "Verified by", "Third-party verifier"),
    if (!ante) dateInput(ns("verification_date"), "Verification date", Sys.Date()),
    tags$details(tags$summary("More inputs (coverage, water quality, persons per unit, STH, promotion)"),
      numericInput(ns("coverage"), "Community coverage of at least basic sanitation after the installations (share; empty = JMP value)", NA, min = 0, max = 1, step = 0.01),
      checkboxInput(ns("water_quality"), "Water at the tap verified free of E. coli (household connections)", FALSE),
      numericInput(ns("people_per_unit"), "Persons per unit (empty = country household size; required for institutions, water points, MHH)", NA, min = 0),
      numericInput(ns("sth"), "Local STH prevalence (share; empty = not estimated)", NA, min = 0, max = 1, step = 0.01),
      checkboxInput(ns("promotion"), "Hygiene product delivered with a promotion contact", FALSE)
    ),
    actionButton(ns("go"), if (ante) "Estimate scenario" else "Estimate from verified outputs", class = "btn-primary")
  )
}

output_panel <- function(id) {
  ns <- function(x) paste0(id, "_", x)
  tagList(
    uiOutput(ns("message")),
    h4("Estimated outcomes"),
    tableOutput(ns("results")),
    p(class = "text-muted small", "Rows without a range are counts taken from the verified outputs (units times persons per unit, and the under-five share). Ranges start where an effect size with a confidence interval enters the chain."),
    h4("Confidence label and its reasons"),
    uiOutput(ns("label")),
    h4("Factor rows used (the ledger)"),
    tableOutput(ns("ledger")),
    downloadButton(ns("dl_results"), "Download results (CSV)"),
    downloadButton(ns("dl_ledger"), "Download ledger (CSV)"),
    p(class = "text-muted small", style = "margin-top: 1em;",
      "All health numbers are estimates with ranges; outputs are verified, outcomes are modelled. Factor tables ", factors_version(),
      ", washhealth ", as.character(utils::packageVersion("washhealth")), ". Methods: ",
      if (!is.null(methodology_url) && nzchar(methodology_url)) tags$a(href = methodology_url, "methodology document") else "docs/methodology.qmd in the tool repository",
      " (CC BY 4.0).")
  )
}

tab_body <- function(id, mode, intro) {
  if (has_bslib) {
    bslib::layout_sidebar(sidebar = bslib::sidebar(width = 380, input_panel(id, mode)), p(intro), output_panel(id))
  } else {
    sidebarLayout(sidebarPanel(width = 4, input_panel(id, mode)), mainPanel(width = 8, p(intro), output_panel(id)))
  }
}

ante_intro <- "Ex-ante: planned outputs and a target use rate give the expected health outcomes of a transaction, in total and for the share attributable to the incentive. Use it for structuring, targets and expected health additionality."
post_intro <- "Ex-post: verified outputs from the verifier's report give the estimated health outcomes achieved, in total and for the incentive-attributable share, for reporting."

repo_url <- "https://github.com/openwashdata/wash-health-impact-tool"
# Shown above every tab: the tool is an experiment and its tables are not fully reviewed.
experimental_banner <- div(class = "alert alert-warning", role = "alert", style = "margin: 1em 1em 0;",
  strong("Experimental. "),
  "Built by an AI agent (Claude, Anthropic) under the instruction and supervision of Lars Sch\u00f6bitz. ",
  "The evidence review and the factor tables are not fully reviewed, so do not use the numbers for funding decisions. ",
  tags$a(href = paste0(repo_url, "#how-this-was-made-and-what-has-been-reviewed"), target = "_blank", "How this was made"))

ui <- if (has_bslib) {
  bslib::page_navbar(title = shiny::tags$span(shiny::tags$img(src = "owd-logos/OWD-logo-01.png", height = "32", alt = "openwashdata", style = "margin-right: 0.6em; vertical-align: middle;"), "washhealth: water and sanitation health impact estimates"), theme = app_theme,
                     header = experimental_banner,
                     bslib::nav_panel("Ex-ante (planning)", tab_body("ante", "ex-ante", ante_intro)),
                     bslib::nav_panel("Ex-post (reporting)", tab_body("post", "ex-post", post_intro)))
} else {
  navbarPage("washhealth: water and sanitation health impact estimates", header = experimental_banner,
             tabPanel("Ex-ante (planning)", tab_body("ante", "ex-ante", ante_intro)),
             tabPanel("Ex-post (reporting)", tab_body("post", "ex-post", post_intro)))
}

# ---- server ---------------------------------------------------------------------

build_transaction <- function(input, id, mode) {
  g <- function(x) input[[paste0(id, "_", x)]]
  other <- identical(g("country"), "Other country (regional fallback)")
  country <- if (other) g("country_name") else g("country")
  who_region <- if (other) g("who_region") else NA
  num_or_na <- function(v) if (is.null(v) || length(v) == 0 || is.na(v)) NA else v
  new_transaction(
    transaction_id = if (mode == "ex-ante") "SCENARIO" else "TRANSACTION", enterprise = "App run", country = country,
    output_type = g("output_type"), quantity = g("quantity"), period_start = format(g("period")[1], "%Y-%m-%d"),
    period_end = format(g("period")[2], "%Y-%m-%d"),
    verified_by = if (mode == "ex-post") g("verified_by") else NA,
    verification_date = if (mode == "ex-post") format(g("verification_date"), "%Y-%m-%d") else NA,
    use_rate = if (isTRUE(g("use_known"))) g("use_rate") else NA,
    baseline_source = if (nzchar(g("baseline_source"))) g("baseline_source") else NA,
    incentive_share = if (isTRUE(g("share_known"))) g("incentive_share") else NA,
    residence = g("residence"), community_coverage_after = num_or_na(g("coverage")),
    water_quality_verified = isTRUE(g("water_quality")), people_per_unit = num_or_na(g("people_per_unit")),
    sth_prevalence = num_or_na(g("sth")), promotion_contact = isTRUE(g("promotion")),
    who_region = who_region, baseline_method = g("baseline_method"), tables = tables
  )
}

serve_tab <- function(input, output, id, mode) {
  ns <- function(x) paste0(id, "_", x)
  state <- reactiveVal(NULL)
  observeEvent(input[[ns("go")]], {
    res <- tryCatch({
      tx <- build_transaction(input, id, mode)
      if (mode == "ex-ante") estimate_scenario(tx, tables = tables) else estimate_transaction(tx, tables = tables)
    }, error = function(e) e)
    state(res)
  })
  output[[ns("message")]] <- renderUI({
    r <- state()
    if (is.null(r)) return(p(class = "text-muted", "Fill in the inputs and press the button."))
    if (inherits(r, "error")) return(div(class = "alert alert-danger", tags$pre(conditionMessage(r))))
    NULL
  })
  output[[ns("results")]] <- renderTable({
    r <- state(); req(r, !inherits(r, "error"))
    d <- r$results[!grepl("per household-year", r$results$outcome), ]
    # A count has no range: show it once, in Central, and leave Low and High blank.
    is_count <- !is.na(d$low) & !is.na(d$high) & d$low == d$central & d$high == d$central
    data.frame(Scope = d$scope, Outcome = d$outcome, Group = d$population_group,
               Low = ifelse(is_count, "", format_number(d$low)),
               Central = format_number(d$central),
               High = ifelse(is_count, "", format_number(d$high)), Unit = d$result_unit, check.names = FALSE)
  }, striped = TRUE)
  output[[ns("label")]] <- renderUI({
    r <- state(); req(r, !inherits(r, "error"))
    est <- r$estimates[[1]]
    fr <- flag_dict[flag_dict$flag %in% est$flags, ]
    tagList(
      p(strong("Label: ", est$confidence), " (start: ", if (is.null(est$exposure_change)) "no conversion factor" else paste0("certainty of effect row ", est$exposure_change$effect_row), ")"),
      tags$ul(lapply(seq_len(nrow(fr)), function(j) tags$li(strong(fr$flag[j]), " (", fr$effect[j], "): ", fr$meaning[j]))),
      tags$ul(lapply(est$notes, tags$li))
    )
  })
  output[[ns("ledger")]] <- renderTable({
    r <- state(); req(r, !inherits(r, "error"))
    lg <- r$ledger
    data.frame(Table = lg$table, Row = lg$id, What = lg$what, Value = ifelse(is.na(lg$value), "", signif(lg$value, 4)),
               Source = lg$citation, Locator = lg$locator, Flag = lg$flag, check.names = FALSE)
  }, striped = TRUE)
  output[[ns("dl_results")]] <- downloadHandler(
    filename = function() paste0(format(Sys.Date(), "%Y-%m-%d"), "-washhealth-", mode, "-results.csv"),
    content = function(file) { r <- state(); req(r, !inherits(r, "error")); utils::write.csv(as.data.frame(r$results), file, row.names = FALSE, na = "") }
  )
  output[[ns("dl_ledger")]] <- downloadHandler(
    filename = function() paste0(format(Sys.Date(), "%Y-%m-%d"), "-washhealth-", mode, "-ledger.csv"),
    content = function(file) { r <- state(); req(r, !inherits(r, "error")); utils::write.csv(as.data.frame(r$ledger), file, row.names = FALSE, na = "") }
  )
  state
}

server <- function(input, output, session) {
  ante_state <- serve_tab(input, output, "ante", "ex-ante")
  post_state <- serve_tab(input, output, "post", "ex-post")
  # exported for shiny::testServer()
  session$userData$ante_state <- ante_state
  session$userData$post_state <- post_state
}

shinyApp(ui, server)
