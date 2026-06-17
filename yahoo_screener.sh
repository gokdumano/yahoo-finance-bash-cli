#!/bin/bash

# ==========================================
# CONSTANTS & CONFIGURATION
# ==========================================
readonly USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
readonly COOKIE_JAR=$(mktemp)
readonly SCREENER_URL="https://query1.finance.yahoo.com/v1/finance/screener"

# Ensure temp files are cleaned up on exit
trap 'rm -f "$COOKIE_JAR"' EXIT INT TERM HUP

# ==========================================
# FUNCTION: get_crumb
# DESCRIPTION: Authenticates with Yahoo Finance to retrieve a valid session cookie 
#              and a crumb token, necessary to bypass API rate limits.
# OUTPUT: Prints the crumb string to STDOUT.
# ==========================================
get_crumb() {
    # 1. Hit the base URL to generate initial cookies
    curl -s -c "$COOKIE_JAR" -A "$USER_AGENT" "https://fc.yahoo.com" > /dev/null
    
    # Wait briefly to mimic human behavior and avoid immediate blocks
    sleep 1 
    
    # 2. Extract the crumb token using the generated cookies
    local crumb
    crumb=$(curl -s -b "$COOKIE_JAR" -A "$USER_AGENT" \
        -H "Origin: https://finance.yahoo.com" \
        "https://query1.finance.yahoo.com/v1/test/getcrumb")
        
    echo "$crumb"
}

# ==========================================
# FUNCTION: build_query_tree
# DESCRIPTION: Takes a flat JSON array of filters and groups them by field.
#              Fields of the same type are grouped with 'OR', different fields with 'AND'.
#              This simulates Yahoo's complex SQL-like JSON syntax.
# USAGE: build_query_tree '[["eq", ["region", "us"]], ["gt", ["dayvolume", 5000000]]]'
# OUTPUT: Prints the nested JSON query block to STDOUT.
# ==========================================
build_query_tree() {
    local filters_json="$1"

    echo "$filters_json" | jq -c '
      {
        operator: "and",
        operands: [
          group_by(.[1][0])[] | 
          {
            operator: "or",
            operands: [
              .[] | {
                operator: .[0],
                operands: .[1]
              }
            ]
          }
        ]
      }'
}

# ==========================================
# FUNCTION: build_screener_payload
# DESCRIPTION: Constructs the final JSON POST payload containing pagination, 
#              sorting, requested fields, and the dynamically built query tree.
# USAGE: build_screener_payload <offset> <size> <filters_json_array>
# OUTPUT: Prints the complete JSON payload to STDOUT.
# ==========================================
build_screener_payload() {
    local offset="$1"
    local size="$2"
    local filters_json="$3"

    # Generate the nested query tree
    local query_block
    query_block=$(build_query_tree "$filters_json")

    # Assemble the final payload
    jq -n \
      --arg size "$size" \
      --arg offset "$offset" \
      --argjson query "$query_block" \
      '{
        size: ($size | tonumber),
        offset: ($offset | tonumber),
        sortType: "DESC",
        sortField: "intradaymarketcap",
        includeFields: [
          "ticker",
          "companyshortname",
          "intradayprice",
          "intradaypricechange",
          "percentchange",
          "dayvolume",
          "avgdailyvol3m",
          "intradaymarketcap",
          "peratio.lasttwelvemonths",
          "day_open_price",
          "fiftytwowklow",
          "fiftytwowkhigh",
          "region",
          "sector",
          "industry"
        ],
        topOperator: "AND",
        query: $query,
        quoteType: "EQUITY"
      }'
}

# ==========================================
# FUNCTION: parse_json_to_csv
# DESCRIPTION: Pivots the complex Screener JSON response into a flat, 
#              row-based CSV format suitable for database insertion.
# USAGE: curl ... | parse_json_to_csv
# OUTPUT: Prints CSV data (with headers) to STDOUT.
# ==========================================
parse_json_to_csv() {
    jq -r '
        # 1. Output the CSV Header
        (["Ticker","Company_Name","Sector","Industry","Price","Change","Change_Pct","Volume","Avg_Vol_3m","PE_Ratio","Market_Cap","52W_Low","52W_High"] | @csv),
        
        # 2. Parse the records array
        (
            .finance.result[0].records[]? | 
            [
                .ticker, 
                .companyName, 
                (.sector // null),
                (.industry // null),
                (.regularMarketPrice.raw // null), 
                (.regularMarketChange.raw // null), 
                (.regularMarketChangePercent.raw // null), 
                (.regularMarketVolume.raw // null), 
                (.avgDailyVol3m.raw // null),
                (.peRatioLtm.raw // null),
                (.marketCap.raw // null),
                (.fiftyTwoWeekLow.raw // null), 
                (.fiftyTwoWeekHigh.raw // null)
            ] | @csv
        )
    '
}

# ==========================================
# FUNCTION: run_screener
# DESCRIPTION: The master orchestrator. Handles authentication, payload creation, 
#              HTTP POST requests, and triggers the CSV parser.
# USAGE: run_screener <offset> <size> <filters_json_array>
# EXAMPLE: run_screener 0 25 '[["eq", ["exchange", "IST"]]]'
# ==========================================
run_screener() {
    local offset="${1:-0}"
    local size="${2:-25}"
    local filters_json="$3"

    # Fail-fast: Check if filters are provided
    if [ -z "$filters_json" ]; then
        echo "ERROR: Filters JSON array is required." >&2
        echo "USAGE: $0 <offset> <size> <filters_json_array>" >&2
        return 1
    fi

    echo "1. Authenticating with Yahoo Finance..." >&2
    local crumb
    crumb=$(get_crumb)
    
    if [ -z "$crumb" ]; then
        echo "ERROR: Failed to retrieve crumb. Yahoo might be blocking the request." >&2
        return 1
    fi

    echo "2. Building dynamic query payload..." >&2
    local payload
    payload=$(build_screener_payload "$offset" "$size" "$filters_json")

    echo "3. Fetching Screener Data (Offset: $offset, Size: $size)..." >&2
    local endpoint="${SCREENER_URL}?formatted=true&useRecordsResponse=true&lang=en-US&region=US&crumb=${crumb}"
    
    # Execute the request and pipe directly to the CSV parser
    curl -s -X POST \
        -b "$COOKIE_JAR" \
        -A "$USER_AGENT" \
        -H "Content-Type: application/json" \
        -H "Origin: https://finance.yahoo.com" \
        -H "x-crumb: $crumb" \
        -d "$payload" \
        "$endpoint" | parse_json_to_csv
        
    return ${PIPESTATUS[0]}
}

# ==========================================
# EXECUTION TRIGGER
# ==========================================
# Pass all command-line arguments to the orchestrator function
run_screener "$@"
