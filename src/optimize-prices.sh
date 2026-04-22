#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"
mkdir -p "$ARTIFACTS_DIR"

usage(){
  cat <<EOF
Usage: $(basename "$0") --requestsPath requests.json --resultsCsv results.csv [--outFile recommendation.csv]
EOF
  exit 1
}

REQUESTS_PATH=""
RESULTS_CSV=""
OUT_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --requestsPath)
      shift; REQUESTS_PATH="$1"; shift;;
    --resultsCsv)
      shift; RESULTS_CSV="$1"; shift;;
    --outFile)
      shift; OUT_FILE="$1"; shift;;
    -h|--help)
      usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [ -z "$REQUESTS_PATH" ] || [ -z "$RESULTS_CSV" ]; then
  usage
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js not found. Install Node.js (>=16)." >&2
  exit 1
fi

TS=$(date +%s)
if [ -z "$OUT_FILE" ]; then
  OUT_FILE="$ARTIFACTS_DIR/recommendation-$TS.csv"
fi

node - <<'NODE' "$REQUESTS_PATH" "$RESULTS_CSV" "$OUT_FILE"
const fs = require('fs')
const reqPath = process.argv[2]
const resultsCsv = process.argv[3]
const outFile = process.argv[4]
if(!fs.existsSync(reqPath)){ console.error('Requests file not found:', reqPath); process.exit(2) }
if(!fs.existsSync(resultsCsv)){ console.error('Results CSV not found:', resultsCsv); process.exit(2) }
const requests = JSON.parse(fs.readFileSync(reqPath,'utf8'))
const csvText = fs.readFileSync(resultsCsv,'utf8')
if(!csvText.trim()){ console.error('Results CSV empty'); process.exit(0) }
function parseLine(line){
  const res = []
  let cur = ''
  let inQuotes = false
  for(let i=0;i<line.length;i++){
    const ch = line[i]
    if(inQuotes){
      if(ch==='"'){
        if(i+1<line.length && line[i+1]==='"'){ cur += '"'; i++ } else { inQuotes = false }
      } else { cur += ch }
    } else {
      if(ch===','){ res.push(cur); cur = '' }
      else if(ch==='"'){ inQuotes = true }
      else { cur += ch }
    }
  }
  res.push(cur)
  return res
}
const lines = csvText.split(/\r?\n/).filter(Boolean)
const headers = parseLine(lines[0]).map(h=>h.trim())
const rows = lines.slice(1).map(l=>{
  const cols = parseLine(l)
  const obj = {}
  headers.forEach((h,i)=> obj[h] = cols[i] === undefined ? '' : cols[i])
  return obj
})

function normalizeText(s){ if(!s) return []
  s = String(s).toLowerCase()
  s = s.replace(/[áàäâ]/g,'a').replace(/[éèëê]/g,'e').replace(/[íìïî]/g,'i').replace(/[óòöô]/g,'o').replace(/[úùüû]/g,'u').replace(/ñ/g,'n')
  s = s.replace(/[^\w\s\u00C0-\u017F]/g,' ')
  const stop = new Set(['de','el','la','en','y','con','para','un','una','unidades','pack'])
  const toks = s.split(/\s+/).map(t=>t.trim()).filter(t=>t && !stop.has(t))
  return toks
}
function tokenScore(req, title){ const rt = normalizeText(req); const tt = normalizeText(title); if(rt.length===0) return 0.0; const common = rt.filter(x=>tt.includes(x)); return common.length / rt.length }
function parseSize(sizeStr){ if(!sizeStr) return null; const m = String(sizeStr).match(/(\d+(?:[\.,]\d+)?)\s*(kg|g|gr|ml|l|un|unidad|unidades)/i); if(m){ let num = parseFloat(m[1].replace(',','.')); let unit = m[2].toLowerCase(); if(unit==='gr') unit='g'; if(unit==='unidad' || unit==='unidades' || unit==='un') unit='unit'; if(unit==='lt') unit='l'; return { size: num, unit: unit } } return null }
function toNumber(s){ if(s===undefined || s===null) return null; let t = String(s).replace(/[^0-9,\.\-]/g,''); if(t==='') return null; // replicate PS heuristic: remove dots (thousands) then make comma decimal
  t = t.replace(/\./g,'').replace(/,/g,'.')
  const n = Number(t)
  return isNaN(n) ? null : n
}
function computeNormalizedUnitPrice(row, requestedUnit){
  let price = toNumber(row.price)
  let upn = toNumber(row.unit_price)
  const sizeInfo = row.size ? parseSize(row.size) : null
  let reqU = requestedUnit
  if(reqU==='g' || reqU==='kg' || reqU==='l' || reqU==='ml'){} else reqU='unit'
  if(sizeInfo && price!==null){
    const pSize = sizeInfo.size; const pUnit = sizeInfo.unit
    if((reqU==='kg' || reqU==='g') && (pUnit==='kg' || pUnit==='g')){
      const sizeKg = (pUnit==='g') ? pSize/1000.0 : pSize
      if(sizeKg!==0){ const pricePerKg = price / sizeKg; if(reqU==='kg') return {unitPrice: pricePerKg, unit:'kg'}; if(reqU==='g') return {unitPrice: pricePerKg/1000.0, unit:'g'} }
    }
    if((reqU==='l' || reqU==='ml') && (pUnit==='l' || pUnit==='ml')){
      const sizeL = (pUnit==='ml') ? pSize/1000.0 : pSize
      if(sizeL!==0){ const pricePerL = price / sizeL; if(reqU==='l') return {unitPrice: pricePerL, unit:'l'}; if(reqU==='ml') return {unitPrice: pricePerL/1000.0, unit:'ml'} }
    }
    if(reqU==='unit' && pUnit==='unit'){ return {unitPrice: price, unit:'unit'} }
    if(reqU==='unit' && (pUnit==='kg' || pUnit==='g' || pUnit==='l' || pUnit==='ml')){ return null }
  }
  if(upn!==null) return {unitPrice: upn, unit: row.unit || 'kg'}
  if(price!==null) return {unitPrice: price, unit:'unit'}
  return null
}

// main
const stores = Array.from(new Set(rows.map(r=>r.site))).filter(Boolean)
let recommendations = []
let feasibleStores = {}
let storeTotals = {}
stores.forEach(s=>{ feasibleStores[s]=true; storeTotals[s]=0.0 })

requests.forEach(req=>{
  const reqName = req.original || req.name || req.query || req.name
  const reqQty = Number(req.quantity || 1)
  const reqUnit = req.unit || 'unit'
  stores.forEach(store=>{
    const candidates = rows.filter(r=> (r.query||'') === (req.query||req.name||'') && (r.site||'') === store)
    if(!candidates || candidates.length===0){ feasibleStores[store]=false; return }
    let best = null; let bestScore = Number.POSITIVE_INFINITY
    candidates.forEach(cand=>{
      const tScore = tokenScore(reqName, cand.title || '')
      const norm = computeNormalizedUnitPrice(cand, reqUnit)
      if(!norm) return
      const estCost = norm.unitPrice * reqQty
      const ts = Math.max(0.01, Number(tScore))
      const combined = estCost / ts
      if(combined < bestScore){ bestScore = combined; best = {candidate:cand, norm, estCost, tokenScore: tScore} }
    })
    if(!best) { feasibleStores[store]=false } else {
      storeTotals[store] += best.estCost
      recommendations.push({store: store, request: reqName, query: req.query || req.name || '', quantity: reqQty, req_unit: reqUnit, matched_title: best.candidate.title, price: best.candidate.price, match_score: best.tokenScore, unit_price: best.norm.unitPrice, unit: best.norm.unit, item_total: best.estCost, product_url: best.candidate.product_url})
    }
  })
})

const feasible = stores.filter(s=>feasibleStores[s])
if(feasible.length === 0){
  console.warn('No single store can supply all requested items. Writing partial recommendations to', outFile)
  // write partial and exit
  const header = ['store','request','query','quantity','req_unit','matched_title','price','match_score','unit_price','unit','item_total','product_url']
  const csv = header.join(',') + '\n' + recommendations.map(r=> header.map(h=>{
    let v = r[h]===undefined ? '' : String(r[h])
    if(v.includes('"')||v.includes(',')||v.includes('\n')) v='"'+v.replace(/"/g,'""')+'"'
    return v
  }).join(',')).join('\n')
  fs.writeFileSync(outFile, csv, 'utf8')
  process.exit(0)
}
let bestStore = null; let bestTotal = Number.POSITIVE_INFINITY
feasible.forEach(s=>{ const t = storeTotals[s]; if(t < bestTotal){ bestTotal = t; bestStore = s } })
const final = recommendations.filter(r=> r.store === bestStore)
const header = ['store','request','query','quantity','req_unit','matched_title','price','match_score','unit_price','unit','item_total','product_url']
const csv = header.join(',') + '\n' + final.map(r=> header.map(h=>{
  let v = r[h]===undefined ? '' : String(r[h])
  if(v.includes('"')||v.includes(',')||v.includes('\n')) v='"'+v.replace(/"/g,'""')+'"'
  return v
}).join(',')).join('\n')
fs.writeFileSync(outFile, csv, 'utf8')
console.log('Chosen store:', bestStore, 'Total:', Math.round(bestTotal*100)/100)
console.log('Recommendations saved to', outFile)
NODE

echo "Recommendations saved to $OUT_FILE"
