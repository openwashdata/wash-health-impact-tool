# Build the package copy of the factor tables.
#
# The canonical tables live in data/factors/ at the repository root. This
# script copies them into the package with a version stamp and saves them as
# package data objects. Run it from anywhere:
#
#   /usr/local/bin/Rscript pkg/data-raw/factors.R
#
# It writes:
#   pkg/inst/extdata/<table>.csv          stamped copies of the six CSV files
#   pkg/inst/extdata/factors-version.txt  the stamp (date plus short git hash
#                                         of the last commit touching data/factors)
#   pkg/data/<object>.rda                 effects, adjustments, pathways,
#                                         baseline_disease, baseline_exposure,
#                                         factors_schema
#   pkg/R/data.R                          roxygen documentation of the six
#                                         objects, generated from the schema
#
# The package never reads data/factors/ at run time; it only reads its own copy.

script_file <- sub("--file=", "", grep("--file=", commandArgs(), value = TRUE)[1])
pkg <- normalizePath(file.path(dirname(script_file), ".."))
repo <- normalizePath(file.path(pkg, ".."))
src <- file.path(repo, "data", "factors")
stopifnot(dir.exists(src))

# ---- version stamp ----------------------------------------------------------

git <- function(...) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(repo), ...), stdout = TRUE, stderr = FALSE))
  if (length(out) == 0) "" else out[1]
}
# Only the table files move the stamp; the changelog beside them does not.
table_glob <- "data/factors/*.csv"
hash <- git("log", "-1", "--format=%h", "--", table_glob)
if (!nzchar(hash)) stop("no git history for data/factors/*.csv; commit the tables before building the package copy")
dirty <- nzchar(git("status", "--porcelain", "--", table_glob))
date <- git("log", "-1", "--format=%ad", "--date=short", "--", table_glob)
stamp <- paste0(date, "-", hash, if (dirty) "-dirty" else "")
if (dirty) warning("data/factors has uncommitted changes; the stamp carries the suffix -dirty")

# ---- copy the CSV files --------------------------------------------------------

files <- c("factors-schema.csv", "effects.csv", "adjustments.csv", "pathways.csv",
           "baseline-disease.csv", "baseline-exposure.csv")
extdata <- file.path(pkg, "inst", "extdata")
dir.create(extdata, recursive = TRUE, showWarnings = FALSE)
for (f in files) stopifnot(file.copy(file.path(src, f), file.path(extdata, f), overwrite = TRUE))
writeLines(stamp, file.path(extdata, "factors-version.txt"))

# ---- read and type the tables ---------------------------------------------------

rd <- function(f) {
  x <- utils::read.csv(file.path(src, f), colClasses = "character", encoding = "UTF-8",
                       check.names = FALSE, na.strings = character())
  tibble::as_tibble(x)
}
num <- function(x, cols) {
  for (col in cols) x[[col]] <- suppressWarnings(as.numeric(x[[col]]))
  x
}
int <- function(x, cols) {
  for (col in cols) x[[col]] <- suppressWarnings(as.integer(x[[col]]))
  x
}
stamp_attr <- function(x) { attr(x, "factors_version") <- stamp; x }

factors_schema <- stamp_attr(rd("factors-schema.csv"))
effects <- stamp_attr(num(rd("effects.csv"), c("central", "low", "high")))
adjustments <- stamp_attr(num(rd("adjustments.csv"), c("value", "low", "high")))
pathways <- stamp_attr(rd("pathways.csv"))
baseline_disease <- stamp_attr(int(num(rd("baseline-disease.csv"), c("value", "low", "high")), "year"))
baseline_exposure <- stamp_attr(int(num(rd("baseline-exposure.csv"), "value"), "year"))

# A quick consistency check against the schema: every column must be described.
schema_cols <- split(factors_schema$column, factors_schema$table)
check_cols <- function(tbl, name) {
  missing <- setdiff(names(tbl), schema_cols[[name]])
  extra <- setdiff(schema_cols[[name]], names(tbl))
  if (length(missing) || length(extra)) stop(name, ": columns not in schema: ", paste(missing, collapse = ", "),
                                              "; schema columns not in table: ", paste(extra, collapse = ", "))
}
check_cols(effects, "effects"); check_cols(adjustments, "adjustments"); check_cols(pathways, "pathways")
check_cols(baseline_disease, "baseline-disease"); check_cols(baseline_exposure, "baseline-exposure")

# ---- save the data objects -------------------------------------------------------

dir.create(file.path(pkg, "data"), showWarnings = FALSE)
for (obj in c("effects", "adjustments", "pathways", "baseline_disease", "baseline_exposure", "factors_schema")) {
  save(list = obj, file = file.path(pkg, "data", paste0(obj, ".rda")), compress = "xz", version = 2)
}

# ---- generate R/data.R from the schema -------------------------------------------------

esc <- function(s) gsub("%", "\\\\%", gsub("([{}])", "\\\\\\1", s))
describe <- function(name) {
  if (name == "factors-schema") {
    # the schema does not describe itself
    return(c("#'   \\item{table}{Name of the factor table the row belongs to (text)}",
             "#'   \\item{column}{Column name (text)}",
             "#'   \\item{type}{text, number, integer or date (text)}",
             "#'   \\item{description}{What the column holds and how the chain uses it (text)}"))
  }
  rows <- factors_schema[factors_schema$table == name, ]
  paste0("#'   \\item{", rows$column, "}{", esc(rows$description), " (", rows$type, ")}")
}
block <- function(obj, name, title, text) {
  n <- nrow(get(obj))
  c(paste0("#' ", title),
    "#'",
    paste0("#' ", text),
    "#'",
    paste0("#' Licence CC BY 4.0. Factor table version `", stamp, "` (see [factors_version()]). ",
           "The canonical file is `data/factors/", name, ".csv` in the tool repository; ",
           "a copy ships in `inst/extdata/`."),
    "#'",
    paste0("#' @format A tibble with ", n, " rows and ", ncol(get(obj)), " columns:"),
    "#' \\describe{",
    describe(name),
    "#' }",
    paste0("#' @source See the `source_citation`, `source` and `url` columns of each row."),
    paste0("\"", obj, "\""),
    "")
}
lines <- c(
  "# Generated by data-raw/factors.R from data/factors/factors-schema.csv. Do not edit by hand.",
  "",
  block("effects", "effects", "Effect rows: pooled relative risks and odds ratios",
        "One row per conversion factor (relative risk or odds ratio) selected in stage 2 from the stage 1 effect size extraction. The chain picks a row by the pathway rule and the user's inputs."),
  block("adjustments", "adjustments", "Adjustment rows: use references, decay, thresholds and method constants",
        "Use reference values, follow-up decay, the sanitation coverage threshold, the episode duration, the mortality rate conversion, the odds ratio to relative risk formula, the PAF counterfactual relative risks and the service ladder relative risks."),
  block("pathways", "pathways", "Pathways: enterprise output types and their rules",
        "One row per output type an enterprise can report, with the exposure change, the effect rule, the adjustment rows that apply, the outcomes reported and the starting confidence label."),
  block("baseline_disease", "baseline-disease", "Country disease baselines",
        "Per country (and WHO region as fallback): WHO 2019 attributable burden, attributable fractions, death and DALY rates, DHS two-week diarrhoea prevalence, household size, under-five share and mortality, derived population and rates."),
  block("baseline_exposure", "baseline-exposure", "Country exposure baselines (service ladders)",
        "Share of the population at each water, sanitation and hygiene service level, national, urban and rural, from the JMP 2025 release (via the openwashdata jmpdata package) and the WHO Global Health Observatory."),
  block("factors_schema", "factors-schema", "Column definitions of the five factor tables",
        "The data dictionary: one row per column of the effects, adjustments, pathways, baseline-disease and baseline-exposure tables.")
)
writeLines(lines, file.path(pkg, "R", "data.R"))

cat("factor tables built with stamp", stamp, "\n")
