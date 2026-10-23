"""Country baselines from the WHO Global Health Observatory (open OData API).

Pulls the WASH burden, attributable fraction, coverage and child health
indicators for the Aqua for All countries and writes a tidy extract to
data/country-baselines.csv (country, iso3, indicator, year, value, unit,
source, url). Raw responses go to data-raw/gho/.

Run: python3 -I scripts/06_gho_baselines.py
"""

import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oa_client as oa  # noqa: E402

API = "https://ghoapi.azureedge.net/api/"
RAW = oa.DATA_RAW / "gho"

COUNTRIES = {
    "BGD": "Bangladesh", "KHM": "Cambodia", "GHA": "Ghana", "IND": "India", "KEN": "Kenya",
    "MDG": "Madagascar", "MWI": "Malawi", "RWA": "Rwanda", "SEN": "Senegal", "ZAF": "South Africa",
    "UGA": "Uganda",
}

# indicator code -> (short name, unit)
INDICATORS = {
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
    "WSH_HYGIENE_BASIC": ("Population with basic handwashing facilities at home", "percent"),
    "MDG_0000000007": ("Under-five mortality rate", "per 1000 live births"),
    "WHS2_167": ("Share of under-five deaths due to diarrhoea", "percent"),
    "NUTSTUNTINGPREV": ("Stunting prevalence under 5, model based", "percent"),
    "HWWS_1": ("Handwashing with soap after using the toilet", "percent"),
}


def fetch(code):
    url = API + code + "?$filter=" + urllib.parse.quote("SpatialDim in ('%s')" % "','".join(COUNTRIES))
    raw = RAW / (code + ".json")
    req = urllib.request.Request(url, headers={"User-Agent": oa.USER_AGENT})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                body = r.read()
            raw.write_bytes(body)
            oa._log(url, 200, 0, "gho")
            time.sleep(0.5)
            return json.loads(body).get("value", [])
        except Exception as e:  # noqa: BLE001
            oa._log(url, "error", 0, str(e)[:120])
            time.sleep(2 * (attempt + 1))
    return []


def main():
    RAW.mkdir(parents=True, exist_ok=True)
    rows = []
    for code, (name, unit) in INDICATORS.items():
        vals = fetch(code)
        kept = 0
        for v in vals:
            if v.get("SpatialDimType") != "COUNTRY":
                continue
            # keep both sexes / total rows only when a sex dimension exists
            if v.get("Dim1Type") == "SEX" and v.get("Dim1") not in ("SEX_BTSX", "BTSX"):
                continue
            if v.get("Dim1Type") == "RESIDENCEAREATYPE" and v.get("Dim1") != "RESIDENCEAREATYPE_TOTL":
                continue
            if v.get("Dim1Type") == "AGEGROUP" and v.get("Dim1") not in ("AGEGROUP_YEARSALL", "AGEGROUP_YEARS00-04", "AGEGROUP_YEARS05-14"):
                continue
            rows.append({
                "country": COUNTRIES[v["SpatialDim"]],
                "iso3": v["SpatialDim"],
                "indicator_code": code,
                "indicator": name,
                "dimension": "%s=%s" % (v.get("Dim1Type") or "", v.get("Dim1") or "") if v.get("Dim1Type") else "",
                "year": v.get("TimeDim"),
                "value": v.get("NumericValue"),
                "value_display": v.get("Value"),
                "low": v.get("Low"),
                "high": v.get("High"),
                "unit": unit,
                "source": "WHO Global Health Observatory",
                "url": "https://www.who.int/data/gho/data/indicators/indicator-details/GHO/" + code.lower(),
            })
            kept += 1
        print("%-32s rows kept: %4d (raw %d)" % (code, kept, len(vals)))
    rows.sort(key=lambda r: (r["country"], r["indicator_code"], r["dimension"], str(r["year"])))
    oa.write_csv(oa.ROOT / "data" / "country-baselines.csv", rows, ["country", "iso3", "indicator_code", "indicator", "dimension", "year", "value", "value_display", "low", "high", "unit", "source", "url"])
    print("total rows:", len(rows))


if __name__ == "__main__":
    main()
