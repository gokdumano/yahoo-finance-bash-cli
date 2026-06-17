# Yahoo Finance Historical Data CLI 📈

![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)

A lightweight, robust, and fail-safe Bash CLI tool to fetch historical stock market data directly from the Yahoo Finance API (v8 chart endpoint). It dynamically handles Yahoo's hidden API rate limits and converts columnar JSON responses into clean, relational CSV files ready for database ingestion.

## ✨ Key Features
- **No API Key Required:** Leverages the public Yahoo Finance v8 chart endpoint.
- **Smart Router (Polymorphism):** Fetch data using human-readable ranges (`1mo`, `ytd`, `max`) OR precise Unix timestamps.
- **Fail-Fast Validation:** Enforces Yahoo's strict API limits locally (e.g., `1m` intraday data is restricted to max 8 days) before making any HTTP requests, preventing IP bans.
- **Dynamic YTD Calculation:** Automatically calculates Year-to-Date (YTD) limits based on the current day of the year.
- **Idempotent ETL Design:** Pivots JSON arrays into row-based CSV formats with headers using `jq`. Prints logs to `STDERR` and clean data to `STDOUT`.
- **Locale Safe:** Prevents capitalization bugs (like the Turkish I/i problem) using `LC_ALL=C`.

## ⚙️ Prerequisites
This script requires two standard command-line tools:
- `curl` (for making HTTP requests)
- `jq` (for parsing and pivoting JSON data)

## 🚀 Installation
Clone the repository and make the script executable:

```bash
git clone https://github.com/gokdumano/yahoo-finance-bash-cli.git
cd yahoo-finance-bash-cli
chmod +x yahoo_historical.sh
```

📖 Usage

The CLI operates in two modes depending on the number of arguments provided.

1. Range Mode (3 Arguments)
Use this mode for quick, human-readable timeframes.

```bash
# Syntax: ./yahoo_historical.sh <ticker> <range> <interval>

# Fetch 1-month of daily data for Apple and save it to a CSV file
./yahoo_historical.sh AAPL 1mo 1d > AAPL_daily.csv

# Fetch Year-to-Date weekly data for Turkish Airlines
./yahoo_historical.sh THYAO.IS ytd 1wk > THYAO_weekly.csv
```

- Valid Ranges: 1d, 5d, 1mo, 3mo, 6mo, 1y, 2y, 5y, 10y, ytd, max
- Valid Intervals: 1m, 5m, 15m, 1h, 1d, 1wk, 1mo

2. Period Mode (4 Arguments)
Use this mode to fetch data between two specific Unix timestamps.

```bash
# Syntax: ./yahoo_historical.sh <ticker> <start_timestamp> <end_timestamp> <interval>

# Fetch 1-hour interval data between two specific dates
./yahoo_historical.sh TSLA 1704067200 1711929600 1h > TSLA_hourly.csv
```

📊 Output Example
The script outputs standard comma-separated values with headers:

```bash
"Ticker","Date","Open","High","Low","Close","Adj_Close","Volume"
"AAPL","2024-03-01 00:00:00",179.55,180.53,177.38,179.66,179.66,73628800
"AAPL","2024-03-04 00:00:00",176.15,176.90,173.79,175.10,175.10,81510100
```

⚠️ Disclaimer
This script is for educational and personal use only. Yahoo Finance limits the availability of certain data (e.g., 1-minute data is only available for the last 8 days, and 5-minute data for the last 60 days). This script respects these limits to prevent abuse.
