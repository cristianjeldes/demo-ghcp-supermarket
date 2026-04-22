#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"
mkdir -p "$ARTIFACTS_DIR"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--prompt "text"] [--items "item1" "item2"] [--sites "super" "jumbo"] [--output path]
Example:
  $(basename "$0") --items "pan integral" "leche" --sites super jumbo --output results.csv
  $(basename "$0") --prompt "Buy pan integral and 2L leche" --sites super,jumbo
EOF
  exit 1
}

PROMPT=""
ITEMS=()
SITES=()
OUTPUT=""

# simple arg parsing
while [ $# -gt 0 ]; do
  case "$1" in
    --prompt)
      shift
      [ $# -gt 0 ] || usage
      PROMPT="$1"
      shift
      ;;
    --items)
      shift
      while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
        ITEMS+=("$1")
        shift
      done
      ;;
    --sites)
      shift
      while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
        SITES+=("$1")
        shift
      done
      ;;
    --output)
      shift
      [ $# -gt 0 ] || usage
      OUTPUT="$1"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown arg: $1"
      usage
      ;;
  esac
done

if [ ${#SITES[@]} -eq 0 ]; then
  SITES=(super jumbo)
fi

if [ ${#ITEMS[@]} -eq 0 ]; then
  if [ -n "$PROMPT" ]; then
    # normalize: replace " and ", " y ", "&" with comma, semicolons to comma
    normalized=$(printf '%s' "$PROMPT" | sed -E 's/\s+and\s+/,/ig; s/\s+y\s+/,/ig; s/\s*&\s+/,/g; s/;/,/g')
    IFS=',' read -ra parts <<< "$normalized"
    for p in "${parts[@]}"; do
      t=$(printf '%s' "$p" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
      if [ -n "$t" ]; then ITEMS+=("$t"); fi
    done
  fi
fi

if [ ${#ITEMS[@]} -eq 0 ]; then
  echo "No items provided. Use --items or --prompt."
  exit 2
fi

ts=$(date +%s)
REQS_PATH="$ARTIFACTS_DIR/requests-$ts.json"

# build JSON array by asking quantity-parser.sh for each item
echo "[" > "$REQS_PATH"
first=1
for itm in "${ITEMS[@]}"; do
  parsed="$("$SCRIPT_DIR/quantity-parser.sh" --text "$itm")"
  if [ "$first" -eq 1 ]; then first=0; else echo "," >> "$REQS_PATH"; fi
  echo "$parsed" >> "$REQS_PATH"
done
echo "]" >> "$REQS_PATH"
echo "Parsed requests saved to $REQS_PATH"

RESULTS_CSV="${OUTPUT:-$ARTIFACTS_DIR/results.csv}"
"$SCRIPT_DIR/scrape-prices.sh" --items "${ITEMS[@]}" --sites "${SITES[@]}" --output "$RESULTS_CSV"

if [ -x "$SCRIPT_DIR/optimize-prices.sh" ]; then
  "$SCRIPT_DIR/optimize-prices.sh" --requestsPath "$REQS_PATH" --resultsCsv "$RESULTS_CSV"
else
  echo "optimize-prices.sh not found or not executable; skipping optimization"
fi
