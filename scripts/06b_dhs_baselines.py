"""Country baselines from the DHS Program indicator API (open, no key needed
for indicator data; microdata need registration, which this script never does).

Indicators: diarrhoea prevalence in the two weeks before the survey among
children under five, handwashing place with soap and water, improved water
source and sanitation (DHS definitions), for the Aqua for All countries.
Rows are appended to data/country-baselines.csv with source "DHS Program
STATcompiler API"; earlier DHS rows are replaced on rerun. Raw to data-raw/dhs/.

Run: python3 -I scripts/06b_dhs_baselines.py
"""
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

API = "https://api.dhsprogram.com/rest/dhs/data"
RAW = oa.DATA_RAW / "dhs"
COUNTRIES = {"BD": ("Bangladesh", "BGD"), "KH": ("Cambodia", "KHM"), "GH": ("Ghana", "GHA"), "IA": ("India", "IND"), "KE": ("Kenya", "KEN"), "MD": ("Madagascar", "MDG"), "MW": ("Malawi", "MWI"), "RW": ("Rwanda", "RWA"), "SN": ("Senegal", "SEN"), "ZA": ("South Africa", "ZAF"), "UG": ("Uganda", "UGA")}
INDICATORS = {
    "CH_DIAR_C_DIA": ("Children under five with diarrhoea in the two weeks before the survey", "percent"),
    "CH_DIAT_C_ORT": ("Children with diarrhoea given oral rehydration therapy", "percent"),
    "WS_SRCE_H_IMP": ("Households using an improved water source", "percent"),
    "WS_TLET_H_IMP": ("Households using an improved sanitation facility (not shared)", "percent"),
    "WS_HNDW_H_SWT": ("Households with a handwashing place with soap and water", "percent"),
    "CN_NUTS_C_HA2": ("Children under five stunted (height for age below -2 SD)", "percent"),
    "CM_ECMR_C_U5M": ("Under-five mortality rate (10 years before survey)", "per 1000 live births"),
}
FIELDS = ["country", "iso3", "indicator_code", "indicator", "dimension", "year", "value", "value_display", "low", "high", "unit", "source", "url"]


def fetch(ind):
    params = {"indicatorIds": ind, "countryIds": ",".join(COUNTRIES), "breakdown": "national", "perpage": 1000, "f": "json"}
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": oa.USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read()
    (RAW / (ind + ".json")).write_bytes(body)
    oa._log(url, 200, 0, "dhs")
    time.sleep(1)
    return json.loads(body).get("Data", [])


def main():
    RAW.mkdir(parents=True, exist_ok=True)
    path = oa.ROOT / "data" / "country-baselines.csv"
    rows = [r for r in oa.read_csv(path) if not r["source"].startswith("DHS")] if path.exists() else []
    n = 0
    for code, (name, unit) in INDICATORS.items():
        for d in fetch(code):
            cc = d.get("DHS_CountryCode")
            if cc not in COUNTRIES or d.get("CharacteristicLabel") not in ("Total", "..Total", None, ""):
                continue
            rows.append({
                "country": COUNTRIES[cc][0], "iso3": COUNTRIES[cc][1], "indicator_code": "DHS_" + code, "indicator": name,
                "dimension": "survey=%s %s" % (d.get("SurveyType", ""), d.get("SurveyYearLabel", "")),
                "year": d.get("SurveyYear"), "value": d.get("Value"), "value_display": d.get("Value"), "low": d.get("CILow", ""), "high": d.get("CIHigh", ""),
                "unit": unit, "source": "DHS Program STATcompiler API", "url": "https://api.dhsprogram.com/rest/dhs/data?indicatorIds=%s&countryIds=%s" % (code, cc),
            })
            n += 1
        print("%-16s rows: %d" % (code, n))
    rows.sort(key=lambda r: (r["country"], r["indicator_code"], r["dimension"], str(r["year"])))
    oa.write_csv(path, rows, FIELDS)
    print("DHS rows added:", n, "total rows:", len(rows))


if __name__ == "__main__":
    main()
