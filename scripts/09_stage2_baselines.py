"""Stage 2 rebuild of data/country-baselines.csv from the raw GHO and DHS responses.

Supersedes 06_gho_baselines.py and 06b_dhs_baselines.py for the baseline file:
it keeps their indicator lists, adds three indicators the factor tables need
(GHO WSH_SANITATION_OD; DHS HC_MEMB_H_MNM mean household size and HC_AGEG_P_004
share of the population aged 0 to 4), fetches only what is missing from
data-raw/, and writes every GHO dimension into the dimension column (stage 1
dropped the AGEGROUP dimension, which left two identical-looking rows for the
all-ages and under-five burden values, and kept only the national residence
rows of the coverage series; urban and rural rows are now kept too).

Run: python3 -I scripts/09_stage2_baselines.py
Network use: open APIs only, no key, no email address, logged in
queries/request-log.csv.
"""
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

GHO_API = "https://ghoapi.azureedge.net/api/"
DHS_API = "https://api.dhsprogram.com/rest/dhs/data"
GHO_RAW = oa.DATA_RAW / "gho"
DHS_RAW = oa.DATA_RAW / "dhs"

COUNTRIES = {
    "BGD": "Bangladesh", "KHM": "Cambodia", "GHA": "Ghana", "IND": "India", "KEN": "Kenya",
    "MDG": "Madagascar", "MWI": "Malawi", "RWA": "Rwanda", "SEN": "Senegal", "ZAF": "South Africa",
    "UGA": "Uganda",
}
DHS_COUNTRIES = {"BD": "BGD", "KH": "KHM", "GH": "GHA", "IA": "IND", "KE": "KEN", "MD": "MDG", "MW": "MWI", "RW": "RWA", "SN": "SEN", "ZA": "ZAF", "UG": "UGA"}

GHO_INDICATORS = {
    "WSH_1": ("WASH attributable deaths, all ages (SDG 3.9.2)", "deaths"),
    "WSH_2": ("WASH attributable deaths, under 5", "thousand deaths"),
    "WSH_3": ("WASH attributable deaths per 100 000, all ages", "per 100 000"),
    "WSH_4": ("WASH attributable deaths per 100 000, under 5", "per 100 000"),
    "WSH_5": ("WASH attributable DALYs, all ages", "thousand DALYs"),
    "WSH_6": ("WASH attributable DALYs, under 5", "thousand DALYs"),
    "WSH_7": ("WASH attributable DALYs per 100 000, all ages", "per 100 000"),
    "WSH_8": ("WASH attributable DALYs per 100 000, under 5", "per 100 000"),
    "WSH_10": ("Diarrhoea deaths from inadequate WASH", "deaths"),
    "WSH_10_WAT": ("Diarrhoea deaths from inadequate water", "deaths"),
    "WSH_10_SAN": ("Diarrhoea deaths from inadequate sanitation", "deaths"),
    "WSH_10_HYG": ("Diarrhoea deaths from inadequate hygiene", "deaths"),
    "WSH_20": ("Attributable fraction of diarrhoea to inadequate WASH", "fraction"),
    "WSH_20_WAT": ("Attributable fraction of diarrhoea to inadequate water", "fraction"),
    "WSH_20_SAN": ("Attributable fraction of diarrhoea to inadequate sanitation", "fraction"),
    "WSH_20_HYG": ("Attributable fraction of diarrhoea to inadequate hygiene", "fraction"),
    "WSH_30": ("Diarrhoea DALYs from inadequate WASH", "DALYs"),
    "WSH_30_WAT": ("Diarrhoea DALYs from inadequate water", "DALYs"),
    "WSH_30_SAN": ("Diarrhoea DALYs from inadequate sanitation", "DALYs"),
    "WSH_30_HYG": ("Diarrhoea DALYs from inadequate hygiene", "DALYs"),
    "SDGWSHBOD": ("Mortality rate attributed to unsafe WASH (SDG 3.9.2)", "per 100 000"),
    "WSH_WATER_BASIC": ("Population using at least basic drinking water", "percent"),
    "WSH_WATER_SAFELY_MANAGED": ("Population using safely managed drinking water", "percent"),
    "WSH_SANITATION_BASIC": ("Population using at least basic sanitation", "percent"),
    "WSH_SANITATION_SAFELY_MANAGED": ("Population using safely managed sanitation", "percent"),
    "WSH_SANITATION_OD": ("Population practising open defecation", "percent"),
    "WSH_HYGIENE_BASIC": ("Population with basic handwashing facilities at home", "percent"),
    "MDG_0000000007": ("Under-five mortality rate", "per 1000 live births"),
    "WHS2_167": ("Share of under-five deaths due to diarrhoea", "percent"),
    "NUTSTUNTINGPREV": ("Stunting prevalence under 5, model based", "percent"),
    "HWWS_1": ("Handwashing with soap after using the toilet", "percent"),
}
DHS_INDICATORS = {
    "CH_DIAR_C_DIA": ("Children under five with diarrhoea in the two weeks before the survey", "percent"),
    "CH_DIAT_C_ORT": ("Children with diarrhoea given oral rehydration therapy", "percent"),
    "WS_SRCE_H_IMP": ("Households using an improved water source", "percent"),
    "WS_TLET_H_IMP": ("Households using an improved sanitation facility (not shared)", "percent"),
    "WS_HNDW_H_SWT": ("Households with a handwashing place with soap and water", "percent"),
    "CN_NUTS_C_HA2": ("Children under five stunted (height for age below -2 SD)", "percent"),
    "CM_ECMR_C_U5M": ("Under-five mortality rate (10 years before survey)", "per 1000 live births"),
    "HC_MEMB_H_MNM": ("Mean number of household members", "persons"),
    "HC_AGEG_P_004": ("Share of the de facto household population aged 0 to 4", "percent"),
}
FIELDS = ["country", "iso3", "indicator_code", "indicator", "dimension", "year", "value", "value_display", "low", "high", "unit", "source", "url"]


def fetch_gho(code):
    raw = GHO_RAW / (code + ".json")
    if raw.exists():
        return json.loads(raw.read_text()).get("value", [])
    url = GHO_API + code + "?$filter=" + urllib.parse.quote("SpatialDim in ('%s')" % "','".join(COUNTRIES))
    req = urllib.request.Request(url, headers={"User-Agent": oa.USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read()
    raw.write_bytes(body)
    oa._log(url, 200, 0, "gho stage2")
    time.sleep(0.5)
    return json.loads(body).get("value", [])


def fetch_dhs(ind):
    raw = DHS_RAW / (ind + ".json")
    if raw.exists():
        return json.loads(raw.read_text()).get("Data", [])
    params = {"indicatorIds": ind, "countryIds": ",".join(DHS_COUNTRIES), "breakdown": "national", "perpage": 1000, "f": "json"}
    url = DHS_API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": oa.USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read()
    raw.write_bytes(body)
    oa._log(url, 200, 0, "dhs stage2")
    time.sleep(1)
    return json.loads(body).get("Data", [])


def gho_rows():
    rows = []
    for code, (name, unit) in GHO_INDICATORS.items():
        kept = 0
        for v in fetch_gho(code):
            if v.get("SpatialDimType") != "COUNTRY" or v["SpatialDim"] not in COUNTRIES:
                continue
            dims = []
            for t, d in (("Dim1Type", "Dim1"), ("Dim2Type", "Dim2"), ("Dim3Type", "Dim3")):
                if v.get(t):
                    dims.append("%s=%s" % (v[t], v[d]))
            dim = "; ".join(dims)
            if "SEX=" in dim and "SEX=SEX_BTSX" not in dim:
                continue
            rows.append({
                "country": COUNTRIES[v["SpatialDim"]], "iso3": v["SpatialDim"], "indicator_code": code, "indicator": name,
                "dimension": dim, "year": v.get("TimeDim"), "value": v.get("NumericValue"), "value_display": v.get("Value"),
                "low": v.get("Low"), "high": v.get("High"), "unit": unit, "source": "WHO Global Health Observatory",
                "url": "https://www.who.int/data/gho/data/indicators/indicator-details/GHO/" + code.lower(),
            })
            kept += 1
        print("%-32s rows kept: %4d" % (code, kept))
    return rows


def dhs_rows():
    rows = []
    for code, (name, unit) in DHS_INDICATORS.items():
        kept = 0
        for d in fetch_dhs(code):
            cc = d.get("DHS_CountryCode")
            if cc not in DHS_COUNTRIES or d.get("CharacteristicLabel") not in ("Total", "..Total", None, ""):
                continue
            iso3 = DHS_COUNTRIES[cc]
            rows.append({
                "country": COUNTRIES[iso3], "iso3": iso3, "indicator_code": "DHS_" + code, "indicator": name,
                "dimension": "survey=%s %s" % (d.get("SurveyType", ""), d.get("SurveyYearLabel", "")),
                "year": d.get("SurveyYear"), "value": d.get("Value"), "value_display": d.get("Value"), "low": d.get("CILow", ""), "high": d.get("CIHigh", ""),
                "unit": unit, "source": "DHS Program STATcompiler API",
                "url": "https://api.dhsprogram.com/rest/dhs/data?indicatorIds=%s&countryIds=%s" % (code, cc),
            })
            kept += 1
        print("%-32s rows kept: %4d" % ("DHS_" + code, kept))
    return rows


def main():
    GHO_RAW.mkdir(parents=True, exist_ok=True)
    DHS_RAW.mkdir(parents=True, exist_ok=True)
    rows = gho_rows() + dhs_rows()
    rows.sort(key=lambda r: (r["country"], r["indicator_code"], r["dimension"], str(r["year"])))
    oa.write_csv(oa.ROOT / "data" / "country-baselines.csv", rows, FIELDS)
    print("total rows:", len(rows))


if __name__ == "__main__":
    main()
