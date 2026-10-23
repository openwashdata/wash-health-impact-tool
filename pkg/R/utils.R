# Small helpers shared by the package. Nothing here holds a factor value.

or_null <- function(a, b) if (is.null(a)) b else a

# Set negative values to zero and keep names (pmax drops them).
floor0 <- function(x) {
  x[!is.na(x) & x < 0] <- 0
  x
}

# Bind a list of tibbles with the same columns; NULL entries are dropped.
rbind_rows <- function(x, empty = NULL) {
  x <- Filter(Negate(is.null), x)
  if (!length(x)) return(empty)
  tibble::as_tibble(do.call(rbind, lapply(x, as.data.frame, stringsAsFactors = FALSE)))
}

# Keep the first row for every combination of the key columns.
distinct_on <- function(x, cols) {
  x[!duplicated(x[cols]), , drop = FALSE]
}

# Extract the first match of a pattern or NA.
first_match <- function(x, pattern) {
  m <- regmatches(x, regexpr(pattern, x))
  if (length(m) == 0) NA_character_ else m
}

is_blank <- function(x) is.null(x) || length(x) == 0 || is.na(x) || !nzchar(trimws(as.character(x)))

# Parse a logical given as TRUE/FALSE, yes/no, 1/0; NA when blank.
parse_flag <- function(x) {
  if (is_blank(x)) return(NA)
  v <- tolower(trimws(as.character(x)))
  if (v %in% c("true", "yes", "y", "1", "t")) return(TRUE)
  if (v %in% c("false", "no", "n", "0", "f")) return(FALSE)
  NA
}

parse_number <- function(x) {
  if (is_blank(x)) return(NA_real_)
  suppressWarnings(as.numeric(trimws(as.character(x))))
}

parse_date <- function(x) {
  if (is_blank(x)) return(as.Date(NA))
  d <- suppressWarnings(as.Date(trimws(as.character(x)), format = "%Y-%m-%d"))
  d
}

slug <- function(x) {
  s <- tolower(gsub("[^A-Za-z0-9]+", "-", x))
  s <- gsub("^-+|-+$", "", s)
  if (!nzchar(s)) "report" else s
}

#' Format an estimate for a table
#'
#' Integers with a thin space above 100, one decimal between 1 and 100, three
#' decimals below 1, `"0"` for zero and `""` for NA. Used by the report, the
#' app and the print methods so that all tables read the same way.
#'
#' @param x A numeric vector.
#' @return A character vector.
#' @export
#' @examples
#' format_number(c(12345.6, 23.456, 0.1234, 0, NA))
format_number <- function(x) nice_number(x)

nice_number <- function(x) {
  out <- character(length(x))
  for (i in seq_along(x)) {
    v <- x[i]
    out[i] <- if (is.na(v)) "" else if (v == 0) "0" else if (abs(v) >= 100) format(round(v), big.mark = " ", trim = TRUE, scientific = FALSE) else if (abs(v) >= 1) sprintf("%.1f", v) else sprintf("%.3f", v)
  }
  out
}
