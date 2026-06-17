#!/bin/bash

# ==========================================
# STRICT MODE & ERROR HANDLING
# ==========================================
# 'e': Exit immediately if a command exits with a non-zero status.
# 'u': Treat unset variables as an error and exit immediately.
# 'o pipefail': Return value of a pipeline is the status of the last command to exit with a non-zero status.
set -euo pipefail

# ==========================================
# DEPENDENCY CHECKS
# ==========================================
# Ensure required commands are available in the system before proceeding.
for cmd in curl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Required command '$cmd' is not installed or not in PATH." >&2
        exit 1
    fi
done

# ==========================================
# CONSTANTS & CONFIGURATION
# ==========================================
readonly USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
readonly CHART_URL="https://query1.finance.yahoo.com/v8/finance/chart"
readonly VALID_RANGES="^(1d|5d|1mo|3mo|6mo|1y|2y|5y|10y|ytd|max)$"
readonly VALID_INTERVALS="^(1m|5m|15m|1h|1d|1wk|1mo)$"

# ==========================================
# FUNCTION: parse_json_to_csv
# DESCRIPTION: Reads JSON from STDIN, outputs CSV with headers to STDOUT.
#              Pivots Yahoo's columnar arrays into a row-based relational format.
# ==========================================
parse_json_to_csv() {
    jq -r '
      # 1. Output the CSV Header
      (["Ticker","Date","Open","High","Low","Close","Adj_Close","Volume"] | @csv),
      
      # 2. Parse and pivot the JSON response
      (
        .chart.result[0] as $res |
        select($res != null) |
        
        $res.meta.symbol as $sym |
        $res.timestamp as $ts |
        $res.indicators.quote[0] as $q |
        $res.indicators.adjclose[0] as $a |
        
        range($ts | length) |
        # Skip days/minutes where the market was closed or data is null
        select($q.close[.] != null) |
        [
            $sym,
            # Format timestamp as YYYY-MM-DD HH:MM:SS for robust timeseries tracking
            ($ts[.] | strftime("%Y-%m-%d %H:%M:%S")),
            ($q.open[.] // null),
            ($q.high[.] // null),
            ($q.low[.] // null),
            ($q.close[.] // null),
            ($a.adjclose[.] // null),
            ($q.volume[.] // null)
        ] | @csv
      )
    '
}

# ==========================================
# FUNCTION: get_data_by_period
# DESCRIPTION: Core engine function. Validates hard limits based on the time 
#              difference, constructs the URL, fetches JSON, and pipes to CSV parser.
# ==========================================
get_data_by_period(){
    local ticker=$(echo "$1" | LC_ALL=C tr 'a-z' 'A-Z')
    local period1=$2
    local period2=$3
    local interval=$(echo "$4" | LC_ALL=C tr 'A-Z' 'a-z')
    
    # 1. Basic Syntax Checks
    if [[ -z "$ticker" ]]; then
        echo "ERROR: ticker cannot be empty!" >&2
        return 1
    elif ! [[ "$period1" =~ ^[0-9]+$ ]] || ! [[ "$period2" =~ ^[0-9]+$ ]]; then
        echo "ERROR: period1 and period2 values must be valid Unix Timestamps (integers)!" >&2
        return 1
    elif [ "$period1" -ge "$period2" ]; then
        echo "ERROR: period1 must be strictly less than period2 (Start Time < End Time)!" >&2
        return 1
    elif [[ ! "$interval" =~ $VALID_INTERVALS ]]; then
        echo "ERROR: invalid interval value ($interval), valid values: 1m, 5m, 15m, 1h, 1d, 1wk, 1mo" >&2
        return 1
    fi
    
    # 2. Calculate the difference in DAYS (Unix time diff divided by 86400 seconds)
    local delta_days=$(( (period2 - period1) / 86400 ))
    
    # 3. Apply Yahoo API Hard Limits
    case "$interval" in
        1m)
            if [[ "$delta_days" -gt 8 ]]; then
                echo "ERROR: For 1m interval, the requested duration ($delta_days days) exceeds the 8-day API limit." >&2
                return 1
            fi
        ;;
        5m|15m)
            if [[ "$delta_days" -gt 60 ]]; then
                echo "ERROR: For $interval interval, the requested duration ($delta_days days) exceeds the 60-day API limit." >&2
                return 1
            fi
        ;;
        1h)
            if [[ "$delta_days" -gt 730 ]]; then
                echo "ERROR: For 1h (hourly) interval, the requested duration ($delta_days days) exceeds the 730-day API limit." >&2
                return 1
            fi
        ;;
    esac
    
    # 4. Fetch JSON and Pipe to CSV Parser
    echo "Query Prepared: '$ticker' (Period: $period1 to $period2, Interval: '$interval')..." >&2
    curl -sLG -A "$USER_AGENT"                \
      --data-urlencode "period1=${period1}"   \
      --data-urlencode "period2=${period2}"   \
      --data-urlencode "interval=${interval}" \
      --data-urlencode "events=div,splits"    \
      --url "${CHART_URL}/${ticker}"           \
    | parse_json_to_csv
    
    return ${PIPESTATUS[0]} # Return the exit code of curl
}

# ==========================================
# FUNCTION: get_data_by_range
# DESCRIPTION: Converts human-readable ranges into Unix timestamps 
#              and passes them to get_data_by_period. Handles 'max' directly.
# ==========================================
get_data_by_range(){
    local ticker=$(echo "$1" | LC_ALL=C tr 'a-z' 'A-Z')
    local range=$(echo "$2" | LC_ALL=C tr 'A-Z' 'a-z')
    local interval=$(echo "$3" | LC_ALL=C tr 'A-Z' 'a-z')

    # 1. Validate the range string
    if [[ ! "$range" =~ $VALID_RANGES ]]; then
        echo "ERROR: invalid range value: ($range), valid values: 1d, 5d, 1mo, 3mo, 6mo, 1y, 2y, 5y, 10y, ytd, max" >&2
        return 1
    fi
    
    local period1
    local period2=$(date +%s)
    
    # 2. Convert 'range' to 'period1' (Unix Timestamp) using GNU date format
    case "$range" in
         1d) period1=$(date -d '-1 day'    +%s) ;;
         5d) period1=$(date -d '-5 days'   +%s) ;;
        1mo) period1=$(date -d '-1 month'  +%s) ;;
        3mo) period1=$(date -d '-3 months' +%s) ;;
        6mo) period1=$(date -d '-6 months' +%s) ;;
         1y) period1=$(date -d '-1 year'   +%s) ;;
         2y) period1=$(date -d '-2 years'  +%s) ;;
         5y) period1=$(date -d '-5 years'  +%s) ;;
        10y) period1=$(date -d '-10 years' +%s) ;;
        ytd)
            local current_year=$(date +%Y)
            period1=$(date -d "${current_year}-01-01 00:00:00" +%s) 
            ;;
        max)
            # Handle 'max' separately as it ignores timestamps
            if [[ "$interval" != "1mo" ]]; then
                echo "WARNING: When range=max is selected, Yahoo API defaults to '1mo' (monthly) data." >&2
                echo "To prevent data pollution, the interval is automatically updated to '1mo'." >&2
                interval="1mo"
            fi
            
            echo "Query Prepared: '$ticker' (Range: '$range', Interval: '$interval')..." >&2
            curl -sLG -A "$USER_AGENT"                \
              --data-urlencode "range=${range}"       \
              --data-urlencode "interval=${interval}" \
              --data-urlencode "events=div,splits"    \
              --url "${CHART_URL}/${ticker}"           \
            | parse_json_to_csv
            return ${PIPESTATUS[0]}
        ;;
    esac
    
    # 3. Pass to the core function
    get_data_by_period "${ticker}" "${period1}" "${period2}" "${interval}"
    return $?
}

# ==========================================
# FUNCTION: get_data (MAIN ROUTER)
# DESCRIPTION: Determines mode based on argument count.
# ==========================================
get_data() {
    if [ "$#" -eq 3 ]; then
        get_data_by_range "$1" "$2" "$3"
    elif [ "$#" -eq 4 ]; then
        get_data_by_period "$1" "$2" "$3" "$4"
    else
        echo "ERROR: Invalid number of arguments." >&2
        echo "USAGE 1 (Range mode) : $0 <ticker> <range> <interval>" >&2
        echo "USAGE 2 (Period mode): $0 <ticker> <period1> <period2> <interval>" >&2
        echo "EXAMPLE: $0 THYAO.IS 1mo 1d" >&2
        return 1
    fi
}

# ==========================================
# EXECUTION TRIGGER
# ==========================================
# Passes all command-line arguments to the master router function
get_data "$@"
