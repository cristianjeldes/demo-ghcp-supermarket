#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"
mkdir -p "$ARTIFACTS_DIR"

usage() {
  cat <<EOF
Usage: $(basename "$0") --items "item1" "item2" [--sites super jumbo] [--output path]
Example:
  $(basename "$0") --items "pan integral" "leche" --sites super jumbo --output results.csv
EOF
  exit 1
}

ITEMS=()
SITES=()
OUTPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
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

if [ ${#ITEMS[@]} -eq 0 ]; then
  echo "No items provided. Use --items"
  exit 2
fi

if [ ${#SITES[@]} -eq 0 ]; then
  SITES=(super jumbo)
fi

# ensure node exists
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js not found. Install Node.js (>=16) and run npm install in repo root." >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
OUTFILE_JSONL="$TMPDIR/scraped.jsonl"
: > "$OUTFILE_JSONL"

for itm in "${ITEMS[@]}"; do
  for site in "${SITES[@]}"; do
    siteArg=$(printf '%s' "$site" | tr '[:upper:]' '[:lower:]')
    if [ "$siteArg" = "lider" ]; then siteArg="super"; fi
    echo "Searching '$itm' on $siteArg..."
    raw="$(node "$SCRIPT_DIR/scraper.js" "$siteArg" "$itm" 2>&1 || true)"
    marker="$(printf '%s
' "$raw" | grep -E '^___BEGIN___' | tail -n1 || true)"
    if [ -n "$marker" ]; then
      json="$(printf '%s
' "$marker" | sed -n 's/^___BEGIN___\(.*\)___END___/\1/p')"
    else
      json="$(printf '%s
' "$raw" | grep -E '^\s*[\{\[]' | tail -n1 || true)"
    fi
    if [ -z "$json" ]; then
      echo "Warning: no JSON output for '$itm' on $siteArg" >&2
      printf '%s
' "$raw" >&2
      continue
    fi
    echo "$json" >> "$OUTFILE_JSONL"
  done
done

# convert JSON lines to CSV using Node
OUTPUT_PATH="${OUTPUT:-$ARTIFACTS_DIR/results.csv}"
node - <<'NODE' "$OUTFILE_JSONL" "$OUTPUT_PATH"
const fs = require('fs')
const inFile = process.argv[2]
const outFile = process.argv[3] || ''
const txt = fs.readFileSync(inFile, 'utf8').trim()
if (!txt) process.exit(0)
const lines = txt.split('\n').filter(Boolean)
let parsed = lines.map(l=>{
  try { return JSON.parse(l) } catch(e) { try { return JSON.parse(l.trim()) } catch(e2) { return null } }
}).filter(Boolean)
let rows = []
parsed.forEach(p=>{
  const items = Array.isArray(p.items) ? p.items : []
  items.forEach((it, idx)=>{
    const title = (it && it.title) ? it.title : (typeof it === 'string' ? it : '')
    const price = it && (it.price || it.price === 0) ? it.price : ''
    const currency = it && (it.currency || it.currency === 0) ? it.currency : ''
    const size = it && (it.size || it.size === 0) ? it.size : ''
    const unit = it && (it.unit || it.unit === 0) ? it.unit : ''
    const unit_price = it && (it.unitPrice || it.unit_price) ? (it.unitPrice || it.unit_price) : ''
    const product_url = it && (it.productUrl || it.product_url) ? (it.productUrl || it.product_url) : ''
    const raw = it && (it.raw || (typeof it === 'string' ? it : null)) ? (it.raw || (typeof it === 'string' ? it : JSON.stringify(it))) : ''
    rows.push({
      site: p.site || '', query: p.query || '', index: idx+1, title, price, currency, size, unit, unit_price, product_url, raw
    })
  })
})
function csvEscape(s){ if (s===null||s===undefined) return ''; s = String(s); if (s.includes('"') || s.includes(',') || s.includes('\n')) return '"'+s.replace(/"/g,'""')+'"'; return s }
const header = ['site','query','index','title','price','currency','size','unit','unit_price','product_url','raw'].join(',')
const out = header + '\n' + rows.map(r=>[r.site,r.query,r.index,r.title,r.price,r.currency,r.size,r.unit,r.unit_price,r.product_url,r.raw].map(csvEscape).join(',')).join('\n')
if (outFile) fs.writeFileSync(outFile, out, 'utf8'); else console.log(out)
NODE

if [ -n "$OUTPUT_PATH" ]; then
  echo "Saved results to $OUTPUT_PATH"
else
  # print generated CSV
  cat "$TMPDIR/scraped.jsonl" >/dev/null
fi

rm -rf "$TMPDIR"
