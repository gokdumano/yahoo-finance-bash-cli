# Yahoo Finance Bash CLI 📈

![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)

A lightweight, robust, and fail-safe command-line interface (CLI) toolkit written purely in Bash. It fetches historical stock market data and dynamically filters equities using the Yahoo Finance API (v8 chart and v1 screener endpoints). 

This toolkit dynamically handles Yahoo's hidden API rate limits, manages crumb/cookie authentication autonomously, and pivots complex columnar JSON responses into clean, relational CSV files ready for database ingestion.

## ✨ Key Features
- **No API Key Required:** Leverages public Yahoo Finance endpoints without requiring registration.
- **Dual Tool Architecture:**
  - `yahoo_screener.sh`: A dynamic SQL-like query builder to filter stocks based on technical and fundamental indicators.
  - `yahoo_historical.sh`: Fetch timeseries market data via precise UNIX timestamps or human-readable ranges.
- **Fail-Fast Validation:** Enforces API limitations locally (e.g., `1m` intraday data max 8-day limit) before making HTTP requests.
- **Idempotent ETL Design:** Pivots JSON arrays into row-based CSV formats with headers using `jq`. Prints status logs to `STDERR` and pure data to `STDOUT`.
- **Locale Safe:** Prevents capitalization bugs across different operating system languages using `LC_ALL=C`.

## ⚙️ Prerequisites
Ensure you have the following standard command-line tools installed on your system:
- `curl` (for making HTTP POST/GET requests)
- `jq` (for building complex payloads and parsing JSON)

## 🚀 Installation
Clone the repository and make the bash scripts executable:

```bash
git clone https://github.com/gokdumano/yahoo-finance-bash-cli.git
cd yahoo-finance-bash-cli
chmod +x *.sh
```

---

## 📖 Tool 1: Historical Data Fetcher (`yahoo_historical.sh`)

This tool extracts historical OHLCV (Open, High, Low, Close, Volume) data. It operates in two modes depending on the number of arguments provided.

### 1. Range Mode (3 Arguments)
Use this mode for quick, human-readable timeframes.
**Syntax:** `./yahoo_historical.sh <ticker> <range> <interval>`

```bash
# Fetch 1-month of daily data for Apple and save it to a CSV
./yahoo_historical.sh AAPL 1mo 1d > AAPL_daily.csv

# Fetch Year-to-Date weekly data for Turkish Airlines
./yahoo_historical.sh THYAO.IS ytd 1wk > THYAO_weekly.csv
```
* **Valid Ranges:** `1d, 5d, 1mo, 3mo, 6mo, 1y, 2y, 5y, 10y, ytd, max`
* **Valid Intervals:** `1m, 5m, 15m, 1h, 1d, 1wk, 1mo`

### 2. Period Mode (4 Arguments)
Use this mode to fetch data between two specific Unix timestamps.
**Syntax:** `./yahoo_historical.sh <ticker> <start_timestamp> <end_timestamp> <interval>`

```bash
# Fetch 1-hour interval data between two specific dates
./yahoo_historical.sh TSLA 1704067200 1711929600 1h > TSLA_hourly.csv
```

---

## 📖 Tool 2: Dynamic Equity Screener (`yahoo_screener.sh`)

This tool filters the global stock market based on specific parameters using Yahoo's Screener endpoint. It utilizes a nested JSON query builder via `jq`.

**Syntax:** `./yahoo_screener.sh <offset> <size> <filters_json_array>`

### Examples

**1. Basic Query:** Get the top 5 equities listed on the Istanbul Stock Exchange (IST):
```bash
./yahoo_screener.sh 0 5 '[["eq", ["exchange", "IST"]]]'
```

**2. Complex Query (AND/OR Logic):** Get top 10 US Technology stocks with a daily volume greater than 5 million:
```bash
./yahoo_screener.sh 0 10 '[
  ["eq", ["region", "us"]], 
  ["eq", ["sector", "Technology"]], 
  ["gt", ["dayvolume", 5000000]]
]' > us_tech_volume_leaders.csv
```

---

## 📊 Output Format Example
Both scripts output standard comma-separated values (CSV) with headers, bypassing temporary files entirely:

```csv
"Ticker","Date","Open","High","Low","Close","Adj_Close","Volume"
"AAPL","2024-03-01 00:00:00",179.55,180.53,177.38,179.66,179.66,73628800
"AAPL","2024-03-04 00:00:00",176.15,176.90,173.79,175.10,175.10,81510100
```

```csv
"Ticker","Company_Name","Sector","Industry","Price","Change","Change_Pct","Volume","Avg_Vol_3m","PE_Ratio","Market_Cap","52W_Low","52W_High"
"ISBTR.IS","Türkiye Is Bankasi A.S.","Financial Services","Banks—Regional",421125.0,-18875.0,-4.2897725,4,5.741379310344827,4.697201,1.0528125E+16,371860.0,670550.0
"ASELS.IS","ASELSAN Elektronik Sanayi ve Ticaret Anonim Sirketi","Industrials","Aerospace & Defense",395.0,1.0,0.2538071,22440322,25643790.068965517,52.070184,1.8012E+12,138.6,450.0
"QNBTR.IS","QNB Bank A.S.","Financial Services","Banks—Regional",219.0,1.3999939,0.6433795,21563,30810.620689655174,22.745962,1.2045E+12,151.17636,627.36365
"DSTKF.IS","DESTEK FINANS FAKTORING","Financial Services","Capital Markets",2870.0,60.0,2.1352313,485780,834275.9137931034,225.546993,9.5666666571E+11,301.5,2895.0
"ENPRA.IS","Enpara Bank A.S.","Financial Services","Banks—Regional",69.95,-2.350006,-3.250354,113321,137623.65714285715,106.413339,872646497708.2363,61.5,104.2
```

## ⚠️ Disclaimer
This script is for educational and personal use only. Yahoo Finance dynamically limits the availability of certain intraday data to prevent scraping abuse. The CLI attempts to respect these hard limits locally to prevent IP bans.
