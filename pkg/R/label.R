# Confidence labels and the flags that move them.

CONFIDENCE_LEVELS <- c("high", "moderate", "low", "very low")

#' Confidence levels and flags
#'
#' `confidence_levels()` returns the labels from best to worst, ending with
#' `"not estimable"`. `confidence_flags()` returns the dictionary of flags an
#' estimate can carry, whether each one lowers the label by one step
#' (`effect = "downgrade"`) or is shown only (`effect = "note"`), and what it
#' means in plain words.
#'
#' @return `confidence_levels()` a character vector; `confidence_flags()` a
#'   tibble with `flag`, `effect` and `meaning`.
#' @export
#' @examples
#' confidence_levels()
#' confidence_flags()
confidence_levels <- function() c(CONFIDENCE_LEVELS, "not estimable")

#' @rdname confidence_levels
#' @export
confidence_flags <- function() {
  tibble::tibble(
    flag = c("use_not_verified", "regional_substitute", "decay_proxy", "decay_missing", "evidence_gap",
             "coverage_below_threshold", "coverage_from_jmp", "baseline_source_assumed", "interval_not_available",
             "later_years_unquantified", "output_not_verified",
             "reporting_bias", "interval_includes_no_effect", "coverage_unknown", "u5_share_missing",
             "no_promotion_contact", "use_is_target", "incentive_share_missing"),
    effect = c(rep("downgrade", 11), rep("note", 7)),
    meaning = c(
      "Use of the output was not verified; no use multiplier was applied.",
      "At least one baseline value came from the WHO regional row, not from the country.",
      "Follow-up decay after year one uses the filter value as a proxy for this product.",
      "No decay value exists for this pathway; later years keep the year-one effect.",
      "The pathway rests on a proxy effect row or has no pooled estimate (evidence gap).",
      "Community sanitation coverage after the installations is below the threshold; the household-targeted row applies.",
      "Community sanitation coverage was not given; the JMP country value for the residence type was used.",
      "The customers' baseline water source was not given and was assumed to be unimproved.",
      "The effect row has no confidence interval; the range could not be derived.",
      "Years after the first are counted without a quantified decay.",
      "The output quantity was not verified by a third party (ex-post run without verification).",
      "Diarrhoea cases in the source trials were caregiver-reported, which tends to overstate effects.",
      "The confidence interval of the effect includes no effect; the low estimate is shown as zero.",
      "Community sanitation coverage is unknown and no JMP value exists; the household-targeted row applies.",
      "The share of children under five is missing; child counts and cases could not be estimated.",
      "A hygiene product without a documented promotion contact carries no factor; reach only.",
      "Ex-ante run: the use rate is a target, not a verified value.",
      "No incentive-attributable share was given; attributable rows are empty."
    )
  )
}

#' Confidence label from a starting certainty and a set of flags
#'
#' Starts from the certainty of the effect row (or the pathway default) and
#' drops one step for every distinct downgrade flag (see [confidence_flags()]).
#' The label cannot drop below `"very low"`. A missing or unknown start gives
#' `"not estimable"`.
#'
#' @param start One of `"high"`, `"moderate"`, `"low"`, `"very low"`, or NA.
#' @param flags Character vector of flags.
#' @return One label.
#' @export
#' @examples
#' label_confidence("moderate", c("use_not_verified", "reporting_bias"))
#' label_confidence(NA)
label_confidence <- function(start, flags = character()) {
  if (length(start) != 1 || is.na(start) || !start %in% CONFIDENCE_LEVELS) return("not estimable")
  fl <- confidence_flags()
  downgrade <- fl$flag[fl$effect == "downgrade"]
  n <- sum(unique(flags) %in% downgrade)
  i <- min(match(start, CONFIDENCE_LEVELS) + n, length(CONFIDENCE_LEVELS))
  CONFIDENCE_LEVELS[i]
}

# The worst of several labels (used by the portfolio summary).
worst_label <- function(labels) {
  lv <- confidence_levels()
  labels <- labels[!is.na(labels)]
  if (!length(labels)) return(NA_character_)
  lv[max(match(labels, lv))]
}
