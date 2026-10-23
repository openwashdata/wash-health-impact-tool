# Build data/factors/baseline-disease.csv and data/factors/baseline-exposure.csv
# from data/country-baselines.csv (WHO GHO and DHS pulls), the openwashdata
# jmpdata package (JMP 2025 release, CC BY 4.0) for the water ladder, and the
# regional values typed in from WHO 2023 Annex 3 to 5 and Fischer Walker 2012.
#
# Every value is either retrieved (flag "country value" or "regional substitute")
# or derived by stated arithmetic on retrieved rows (flag "derived", with the
# derivation written in the derivation column). Nothing is invented; where a
# value is missing the row says so.
#
# Run: /usr/local/bin/Rscript scripts/10_build_baseline_tables.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(stringr)
})

root <- normalizePath(file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE)[1])), ".."))
cb <- read_csv(file.path(root, "data", "country-baselines.csv"), show_col_types = FALSE,
               col_types = cols(.default = col_character()))
# WSH_SANITATION_OD comes with an empty NumericValue and a rounded display value; use the display value then
cb <- cb %>% mutate(year = as.integer(year), value = coalesce(suppressWarnings(as.numeric(value)), suppressWarnings(as.numeric(value_display))),
                    low = suppressWarnings(as.numeric(low)), high = suppressWarnings(as.numeric(high)))

countries <- tibble::tribble(
  ~country, ~iso3, ~who_region, ~region_name,
  "Bangladesh", "BGD", "SEAR", "South-East Asia",
  "Cambodia", "KHM", "WPR", "Western Pacific",
  "Ghana", "GHA", "AFR", "Africa",
  "India", "IND", "SEAR", "South-East Asia",
  "Kenya", "KEN", "AFR", "Africa",
  "Madagascar", "MDG", "AFR", "Africa",
  "Malawi", "MWI", "AFR", "Africa",
  "Rwanda", "RWA", "AFR", "Africa",
  "Senegal", "SEN", "AFR", "Africa",
  "South Africa", "ZAF", "AFR", "Africa",
  "Uganda", "UGA", "AFR", "Africa"
)

latest <- function(code, dim_pattern = NULL) {
  x <- cb %>% filter(indicator_code == code)
  if (!is.null(dim_pattern)) x <- x %>% filter(str_detect(dimension, dim_pattern))
  x %>% group_by(iso3) %>% slice_max(year, n = 1, with_ties = FALSE) %>% ungroup()
}

gho_url <- function(code) paste0("https://www.who.int/data/gho/data/indicators/indicator-details/GHO/", tolower(code))

# ---- retrieved rows -------------------------------------------------------

mk <- function(x, ind_, grp_, unit_, flag_, deriv_ = "") {
  x %>% transmute(iso3, indicator = ind_, population_group = grp_, value, low, high,
                  unit = unit_, year, source, url, flag = flag_, derivation = deriv_)
}

rows <- list()

# WHO attributable burden and PAFs (2019)
rows$deaths_all <- mk(latest("WSH_10", "YEARSALL"), "diarr_deaths_wash_attributable", "all ages", "deaths", "country value; WHO 2019 estimate")
rows$deaths_u5  <- mk(latest("WSH_10", "UNDER5"), "diarr_deaths_wash_attributable", "under five", "deaths", "country value; WHO 2019 estimate")
rows$dalys_all  <- mk(latest("WSH_30", "YEARSALL"), "diarr_dalys_wash_attributable", "all ages", "DALYs", "country value; WHO 2019 estimate")
rows$dalys_u5   <- mk(latest("WSH_30", "UNDER5"), "diarr_dalys_wash_attributable", "under five", "DALYs", "country value; WHO 2019 estimate")
rows$paf        <- mk(latest("WSH_20"), "paf_diarr_wash", "all ages", "fraction", "country value; WHO 2019 estimate")
rows$paf_wat    <- mk(latest("WSH_20_WAT"), "paf_diarr_water", "all ages", "fraction", "country value; WHO 2019 estimate")
rows$paf_san    <- mk(latest("WSH_20_SAN"), "paf_diarr_sanitation", "all ages", "fraction", "country value; WHO 2019 estimate")
rows$paf_hyg    <- mk(latest("WSH_20_HYG"), "paf_diarr_hygiene", "all ages", "fraction", "country value; WHO 2019 estimate")
rows$wash_deaths <- mk(latest("WSH_1"), "wash_deaths_all_causes", "all ages", "deaths", "country value; WHO 2019 estimate (SDG 3.9.2 numerator)")
rows$wash_rate   <- mk(latest("SDGWSHBOD"), "wash_mortality_rate", "all ages", "per 100 000", "country value; WHO 2019 estimate (SDG 3.9.2)")
rows$u5mr        <- mk(latest("MDG_0000000007"), "u5mr", "under five", "per 1000 live births", "country value; WHO estimate")

# DHS survey values
dhs_flag <- function(x, extra) paste0("country value; ", str_remove(x$dimension, "survey="), "; ", extra)
d1 <- latest("DHS_CH_DIAR_C_DIA"); rows$prev <- mk(d1, "diarr_prev2w_u5", "under five", "percent", dhs_flag(d1, "caregiver-reported two-week recall"))
d2 <- latest("DHS_HC_MEMB_H_MNM"); rows$hh <- mk(d2, "household_size", "all ages", "persons", dhs_flag(d2, "mean number of usual members"))
d3 <- latest("DHS_HC_AGEG_P_004"); rows$u5s <- mk(d3, "u5_share", "all ages", "percent", dhs_flag(d3, "de facto household population aged 0 to 4"))
d4 <- latest("DHS_CM_ECMR_C_U5M"); rows$u5mr_dhs <- mk(d4, "u5mr_dhs", "under five", "per 1000 live births", dhs_flag(d4, "ten years before the survey"))

retrieved <- bind_rows(rows)

# ---- derived rows ---------------------------------------------------------

wide <- retrieved %>% select(iso3, indicator, population_group, value) %>%
  mutate(key = paste(indicator, population_group, sep = "|")) %>%
  select(iso3, key, value) %>% pivot_wider(names_from = key, values_from = value)

derived <- wide %>% transmute(
  iso3,
  population = `wash_deaths_all_causes|all ages` / `wash_mortality_rate|all ages` * 1e5,
  population_u5 = population * `u5_share|all ages` / 100,
  deaths_total_all = `diarr_deaths_wash_attributable|all ages` / `paf_diarr_wash|all ages`,
  deaths_total_u5 = `diarr_deaths_wash_attributable|under five` / `paf_diarr_wash|all ages`,
  dalys_total_all = `diarr_dalys_wash_attributable|all ages` / `paf_diarr_wash|all ages`,
  dalys_total_u5 = `diarr_dalys_wash_attributable|under five` / `paf_diarr_wash|all ages`,
  death_rate_all = deaths_total_all / population * 1e5,
  death_rate_u5 = deaths_total_u5 / population_u5 * 1e5,
  daly_rate_all = dalys_total_all / population * 1e5,
  daly_rate_u5 = dalys_total_u5 / population_u5 * 1e5
)

who_src <- "WHO Global Health Observatory (derived)"
dv <- function(col, ind_, grp_, unit_, deriv_) {
  derived %>% transmute(iso3, indicator = ind_, population_group = grp_, value = .data[[col]], low = NA_real_, high = NA_real_,
                        unit = unit_, year = 2019L, source = who_src, url = gho_url("wsh_10"), flag = "derived from WHO 2019 rows", derivation = deriv_)
}
derived_rows <- bind_rows(
  dv("population", "population", "all ages", "persons", "wash_deaths_all_causes / wash_mortality_rate x 100000 (both WHO 2019)"),
  dv("population_u5", "population", "under five", "persons", "population (all ages) x u5_share / 100 (DHS share; survey year differs from 2019)"),
  dv("deaths_total_all", "diarr_deaths_total", "all ages", "deaths", "diarr_deaths_wash_attributable / paf_diarr_wash"),
  dv("deaths_total_u5", "diarr_deaths_total", "under five", "deaths", "diarr_deaths_wash_attributable (under five) / paf_diarr_wash (WHO applies one PAF to all ages)"),
  dv("dalys_total_all", "diarr_dalys_total", "all ages", "DALYs", "diarr_dalys_wash_attributable / paf_diarr_wash"),
  dv("dalys_total_u5", "diarr_dalys_total", "under five", "DALYs", "diarr_dalys_wash_attributable (under five) / paf_diarr_wash"),
  dv("death_rate_all", "diarr_death_rate", "all ages", "per 100 000 per year", "diarr_deaths_total / population x 100000"),
  dv("death_rate_u5", "diarr_death_rate", "under five", "per 100 000 per year", "diarr_deaths_total (under five) / population (under five) x 100000"),
  dv("daly_rate_all", "diarr_daly_rate", "all ages", "per 100 000 per year", "diarr_dalys_total / population x 100000"),
  dv("daly_rate_u5", "diarr_daly_rate", "under five", "per 100 000 per year", "diarr_dalys_total (under five) / population (under five) x 100000")
)

# STH: no country value pulled
sth_rows <- countries %>% transmute(iso3, indicator = "sth_prevalence", population_group = "all ages", value = NA_real_, low = NA_real_, high = NA_real_,
                                    unit = "percent", year = NA_integer_, source = "not pulled", url = "https://espen.afro.who.int/",
                                    flag = "missing: no country STH prevalence pulled (WHO PCT databank and ESPEN hold school-age values); supply a local value to the chain",
                                    derivation = "")

# ---- regional rows (typed in from the sources) ----------------------------

# WHO 2023 burden report, Annex 3 (regional PAFs, LMIC members of the region) and Annex 4 and 5 (population, all diarrhoea deaths and DALYs, whole WHO region)
# Fischer Walker 2012 Table 2 (episodes per child-year, 0 to 59 months, 2010)
who_report <- "WHO 2023. Burden of disease attributable to unsafe drinking-water, sanitation and hygiene, 2019 update"
who_url <- "https://www.who.int/publications/i/item/9789240075610"
fw <- "Fischer Walker CL et al. 2012. BMC Public Health 12:220"
fw_url <- "https://doi.org/10.1186/1471-2458-12-220"

regional <- tibble::tribble(
  ~iso3, ~indicator, ~population_group, ~value, ~low, ~high, ~unit, ~year, ~source, ~url, ~flag, ~derivation,
  "AFR", "paf_diarr_water", "all ages", 0.42, 0.38, 0.46, "fraction", 2019L, who_report, who_url, "regional substitute (Africa, LMIC members); Annex 3 Table A3.1", "",
  "AFR", "paf_diarr_sanitation", "all ages", 0.42, 0.39, 0.47, "fraction", 2019L, who_report, who_url, "regional substitute (Africa, LMIC members); Annex 3 Table A3.2", "",
  "AFR", "paf_diarr_hygiene", "all ages", 0.28, 0.23, 0.31, "fraction", 2019L, who_report, who_url, "regional substitute (Africa, LMIC members); Annex 3 Table A3.3", "",
  "AFR", "paf_diarr_wash", "all ages", 0.76, 0.72, 0.79, "fraction", 2019L, who_report, who_url, "regional substitute (Africa, LMIC members); Annex 3 Table A3.4", "",
  "SEAR", "paf_diarr_water", "all ages", 0.29, 0.19, 0.42, "fraction", 2019L, who_report, who_url, "regional substitute (South-East Asia, LMIC members); Annex 3 Table A3.1", "",
  "SEAR", "paf_diarr_sanitation", "all ages", 0.36, 0.30, 0.44, "fraction", 2019L, who_report, who_url, "regional substitute (South-East Asia, LMIC members); Annex 3 Table A3.2", "",
  "SEAR", "paf_diarr_hygiene", "all ages", 0.24, 0.18, 0.30, "fraction", 2019L, who_report, who_url, "regional substitute (South-East Asia, LMIC members); Annex 3 Table A3.3", "",
  "SEAR", "paf_diarr_wash", "all ages", 0.66, 0.57, 0.74, "fraction", 2019L, who_report, who_url, "regional substitute (South-East Asia, LMIC members); Annex 3 Table A3.4", "",
  "WPR", "paf_diarr_water", "all ages", 0.20, 0.15, 0.31, "fraction", 2019L, who_report, who_url, "regional substitute (Western Pacific, LMIC members); Annex 3 Table A3.1", "",
  "WPR", "paf_diarr_sanitation", "all ages", 0.28, 0.23, 0.33, "fraction", 2019L, who_report, who_url, "regional substitute (Western Pacific, LMIC members); Annex 3 Table A3.2", "",
  "WPR", "paf_diarr_hygiene", "all ages", 0.26, 0.23, 0.31, "fraction", 2019L, who_report, who_url, "regional substitute (Western Pacific, LMIC members); Annex 3 Table A3.3", "",
  "WPR", "paf_diarr_wash", "all ages", 0.58, 0.52, 0.64, "fraction", 2019L, who_report, who_url, "regional substitute (Western Pacific, LMIC members); Annex 3 Table A3.4", "",
  "AFR", "population", "all ages", 1091759000, NA, NA, "persons", 2019L, who_report, who_url, "regional substitute (whole WHO region); Annex 4 Table A4.1", "",
  "AFR", "population", "under five", 170238000, NA, NA, "persons", 2019L, who_report, who_url, "regional substitute (whole WHO region); Annex 4 Table A4.1", "",
  "AFR", "diarr_deaths_total", "all ages", 496278, NA, NA, "deaths", 2019L, who_report, who_url, "regional substitute; Annex 4 Table A4.1 (all diarrhoeal deaths)", "",
  "AFR", "diarr_deaths_total", "under five", 222873, NA, NA, "deaths", 2019L, who_report, who_url, "regional substitute; Annex 4 Table A4.1 (all diarrhoeal deaths)", "",
  "AFR", "diarr_dalys_total", "all ages", 34094348, NA, NA, "DALYs", 2019L, who_report, who_url, "regional substitute; Annex 5 Table A5.1 (all diarrhoeal DALYs)", "",
  "AFR", "diarr_dalys_total", "under five", 20371351, NA, NA, "DALYs", 2019L, who_report, who_url, "regional substitute; Annex 5 Table A5.1 (all diarrhoeal DALYs)", "",
  "SEAR", "population", "all ages", 2001946000, NA, NA, "persons", 2019L, who_report, who_url, "regional substitute (whole WHO region); Annex 4 Table A4.1", "",
  "SEAR", "population", "under five", 169700000, NA, NA, "persons", 2019L, who_report, who_url, "regional substitute (whole WHO region); Annex 4 Table A4.1", "",
  "SEAR", "diarr_deaths_total", "all ages", 792010, NA, NA, "deaths", 2019L, who_report, who_url, "regional substitute; Annex 4 Table A4.1 (all diarrhoeal deaths)", "",
  "SEAR", "diarr_deaths_total", "under five", 79322, NA, NA, "deaths", 2019L, who_report, who_url, "regional substitute; Annex 4 Table A4.1 (all diarrhoeal deaths)", "",
  "SEAR", "diarr_dalys_total", "all ages", 28512513, NA, NA, "DALYs", 2019L, who_report, who_url, "regional substitute; Annex 5 Table A5.1 (all diarrhoeal DALYs)", "",
  "SEAR", "diarr_dalys_total", "under five", 7293132, NA, NA, "DALYs", 2019L, who_report, who_url, "regional substitute; Annex 5 Table A5.1 (all diarrhoeal DALYs)", "",
  "WPR", "population", "all ages", 1922672000, NA, NA, "persons", 2019L, who_report, who_url, "regional substitute (whole WHO region); Annex 4 Table A4.1", "",
  "WPR", "population", "under five", 119791000, NA, NA, "persons", 2019L, who_report, who_url, "regional substitute (whole WHO region); Annex 4 Table A4.1", "",
  "WPR", "diarr_deaths_total", "all ages", 31677, NA, NA, "deaths", 2019L, who_report, who_url, "regional substitute; Annex 4 Table A4.1 (all diarrhoeal deaths)", "",
  "WPR", "diarr_deaths_total", "under five", 11731, NA, NA, "deaths", 2019L, who_report, who_url, "regional substitute; Annex 4 Table A4.1 (all diarrhoeal deaths)", "",
  "WPR", "diarr_dalys_total", "all ages", 3091021, NA, NA, "DALYs", 2019L, who_report, who_url, "regional substitute; Annex 5 Table A5.1 (all diarrhoeal DALYs)", "",
  "WPR", "diarr_dalys_total", "under five", 1266611, NA, NA, "DALYs", 2019L, who_report, who_url, "regional substitute; Annex 5 Table A5.1 (all diarrhoeal DALYs)", "",
  "AFR", "diarr_incidence_u5", "under five", 3.3, 2.2, 5.1, "episodes per child-year", 2010L, fw, fw_url, "regional substitute (WHO Africa region, LMIC); modelled 2010 value; Table 2", "",
  "SEAR", "diarr_incidence_u5", "under five", 2.4, 1.5, 3.3, "episodes per child-year", 2010L, fw, fw_url, "regional substitute (WHO South-East Asia region, LMIC); modelled 2010 value; Table 2", "",
  "WPR", "diarr_incidence_u5", "under five", 2.3, 1.3, 2.6, "episodes per child-year", 2010L, fw, fw_url, "regional substitute (WHO Western Pacific region, LMIC); modelled 2010 value; Table 2", "",
  "GLOBAL", "diarr_incidence_u5", "under five", 2.9, 2.3, 3.4, "episodes per child-year", 2010L, fw, fw_url, "global LMIC value; modelled 2010 value; Table 2", ""
)

# regional rates derived from the regional totals
reg_wide <- regional %>% filter(indicator %in% c("population", "diarr_deaths_total", "diarr_dalys_total")) %>%
  select(iso3, indicator, population_group, value) %>% pivot_wider(names_from = indicator, values_from = value)
reg_u5 <- regional %>% filter(indicator == "population") %>% select(iso3, population_group, value) %>%
  pivot_wider(names_from = population_group, values_from = value) %>%
  transmute(iso3, indicator = "u5_share", population_group = "all ages", value = `under five` / `all ages` * 100, low = NA_real_, high = NA_real_,
            unit = "percent", year = 2019L, source = paste(who_report, "(derived)"), url = who_url,
            flag = "regional substitute; derived", derivation = "population (under five) / population (all ages) x 100 (Annex 4)")
regional_rates <- bind_rows(
  reg_u5,
  reg_wide %>% transmute(iso3, indicator = "diarr_death_rate", population_group, value = diarr_deaths_total / population * 1e5, low = NA_real_, high = NA_real_,
                         unit = "per 100 000 per year", year = 2019L, source = paste(who_report, "(derived)"), url = who_url,
                         flag = "regional substitute; derived", derivation = "diarr_deaths_total / population x 100000 (Annex 4)"),
  reg_wide %>% transmute(iso3, indicator = "diarr_daly_rate", population_group, value = diarr_dalys_total / population * 1e5, low = NA_real_, high = NA_real_,
                         unit = "per 100 000 per year", year = 2019L, source = paste(who_report, "(derived)"), url = who_url,
                         flag = "regional substitute; derived", derivation = "diarr_dalys_total / population x 100000 (Annex 5)")
)

# per-country copy of the regional incidence (the only incidence baseline; flagged as a regional substitute)
inc_country <- countries %>% inner_join(regional %>% filter(indicator == "diarr_incidence_u5"), by = c("who_region" = "iso3")) %>%
  transmute(iso3, indicator, population_group, value, low, high, unit, year, source, url,
            flag = paste0("regional substitute (", region_name, "); modelled 2010 value; no country incidence series exists in the WHO GHO or DHS pulls"), derivation = "")

regions <- tibble(iso3 = c("AFR", "SEAR", "WPR", "GLOBAL"), country = c("Region: Africa", "Region: South-East Asia", "Region: Western Pacific", "Global LMIC"), who_region = c("AFR", "SEAR", "WPR", "GLOBAL"))

disease <- bind_rows(
  bind_rows(retrieved, derived_rows, sth_rows, inc_country) %>% left_join(countries %>% select(iso3, country, who_region), by = "iso3"),
  bind_rows(regional, regional_rates) %>% left_join(regions, by = "iso3")
) %>%
  mutate(value = round(value, 4)) %>%
  arrange(country, indicator, population_group) %>%
  mutate(baseline_id = sprintf("B%04d", row_number())) %>%
  select(baseline_id, country, iso3, who_region, indicator, population_group, value, low, high, unit, year, source, url, flag, derivation)

write_csv(disease, file.path(root, "data", "factors", "baseline-disease.csv"), na = "")
cat("baseline-disease.csv rows:", nrow(disease), "\n")

# ---- exposure table -------------------------------------------------------

jmp <- jmpdata::jmpindicators %>% filter(iso3 %in% countries$iso3, service == "water", !is.na(percent))
jmp_latest <- jmp %>% group_by(iso3, residence, var_short) %>% slice_max(year, n = 1, with_ties = FALSE) %>% ungroup()
jmp_levels <- c(wat_bas = "at least basic", wat_lim = "limited (more than 30 minutes)", wat_unimp = "unimproved", wat_sur = "surface water",
                wat_premises = "accessible on premises", wat_available = "available when needed", wat_pip = "piped", wat_npip = "non-piped")
exp_water <- jmp_latest %>% filter(var_short %in% names(jmp_levels)) %>%
  transmute(iso3, service = "water", level = unname(jmp_levels[var_short]), residence, value = round(percent, 2), unit = "percent", year,
            source = "WHO/UNICEF JMP 2025 release via openwashdata jmpdata 0.1.0 (CC BY 4.0)", url = "https://github.com/openwashdata/jmpdata",
            flag = "retrieved")

gho_res <- function(code, service_, level_) {
  cb %>% filter(indicator_code == code, str_detect(dimension, "RESIDENCEAREATYPE")) %>%
    mutate(residence = case_when(str_detect(dimension, "_TOTL") ~ "national", str_detect(dimension, "_URB") ~ "urban", str_detect(dimension, "_RUR") ~ "rural")) %>%
    filter(!is.na(value)) %>% group_by(iso3, residence) %>% slice_max(year, n = 1, with_ties = FALSE) %>% ungroup() %>%
    transmute(iso3, service = service_, level = level_, residence, value = round(value, 2), unit = "percent", year, source = "WHO Global Health Observatory (JMP data)", url = gho_url(code), flag = "retrieved")
}
exp_gho <- bind_rows(
  gho_res("WSH_WATER_SAFELY_MANAGED", "water", "safely managed"),
  gho_res("WSH_SANITATION_BASIC", "sanitation", "at least basic"),
  gho_res("WSH_SANITATION_SAFELY_MANAGED", "sanitation", "safely managed"),
  gho_res("WSH_SANITATION_OD", "sanitation", "open defecation"),
  gho_res("WSH_HYGIENE_BASIC", "hygiene", "basic")
)

# derived rungs
san_w <- exp_gho %>% filter(service == "sanitation") %>% select(iso3, residence, level, value, year) %>%
  pivot_wider(names_from = level, values_from = c(value, year))
exp_derived <- bind_rows(
  san_w %>% transmute(iso3, service = "sanitation", level = "limited or unimproved", residence, value = round(100 - `value_at least basic` - `value_open defecation`, 2), unit = "percent",
                      year = pmax(`year_at least basic`, `year_open defecation`), source = "WHO Global Health Observatory (derived)", url = gho_url("WSH_SANITATION_BASIC"),
                      flag = "derived: 100 - at least basic - open defecation; the two rungs cannot be separated from the GHO series"),
  san_w %>% filter(!is.na(`value_safely managed`)) %>% transmute(iso3, service = "sanitation", level = "basic (not safely managed)", residence, value = round(`value_at least basic` - `value_safely managed`, 2), unit = "percent",
                      year = pmax(`year_at least basic`, `year_safely managed`), source = "WHO Global Health Observatory (derived)", url = gho_url("WSH_SANITATION_SAFELY_MANAGED"),
                      flag = "derived: at least basic - safely managed"),
  exp_gho %>% filter(service == "hygiene") %>% transmute(iso3, service, level = "limited or no facility", residence, value = round(100 - value, 2), unit, year, source = "WHO Global Health Observatory (derived)", url, flag = "derived: 100 - basic")
)

# missing markers
all_combos <- expand_grid(iso3 = countries$iso3, service = c("water", "sanitation", "hygiene"), residence = "national")
need <- tibble::tribble(~service, ~level, "water", "safely managed", "sanitation", "safely managed", "hygiene", "basic")
have <- bind_rows(exp_water, exp_gho, exp_derived)
missing <- all_combos %>% inner_join(need, by = "service", relationship = "many-to-many") %>% anti_join(have, by = c("iso3", "service", "level", "residence")) %>%
  transmute(iso3, service, level, residence, value = NA_real_, unit = "percent", year = NA_integer_, source = "WHO Global Health Observatory", url = "https://www.who.int/data/gho", flag = "missing: no JMP estimate for this level")

exposure <- bind_rows(have, missing) %>% left_join(countries %>% select(iso3, country), by = "iso3") %>%
  arrange(country, service, residence, level) %>% mutate(exposure_id = sprintf("X%04d", row_number())) %>%
  select(exposure_id, country, iso3, service, level, residence, value, unit, year, source, url, flag)
write_csv(exposure, file.path(root, "data", "factors", "baseline-exposure.csv"), na = "")
cat("baseline-exposure.csv rows:", nrow(exposure), "\n")
