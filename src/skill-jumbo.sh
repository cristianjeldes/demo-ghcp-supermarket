#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Forward all args to scrape-prices.sh and force site to jumbo
"$SCRIPT_DIR/scrape-prices.sh" "$@" --sites jumbo
