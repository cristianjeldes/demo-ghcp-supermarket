#!/usr/bin/env bash
set -euo pipefail

# quantity-parser.sh --text "item string"
# Outputs a single JSON object: {"quantity":<number>,"unit":"unit","name":"..."}

text=""
while [ $# -gt 0 ]; do
  case "$1" in
    --text)
      shift
      text="$1"
      shift
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") --text \"item string\""; exit 0
      ;;
    *)
      text="$1"
      shift
      ;;
  esac
done

if [ -z "$text" ]; then
  # read from stdin
  if [ -t 0 ]; then
    # no stdin
    echo '{"quantity":1,"unit":"unit","name":""}'
    exit 0
  else
    text=$(cat -)
  fi
fi

node - <<'NODE' -- "$text"
const txt = process.argv[2] || ''
function normalizeUnit(u){ if(!u) return u; u = u.toLowerCase(); if(u==='gr') return 'g'; if(u==='lt') return 'l'; if(u==='unidad' || u==='unidades' || u==='un') return 'unit'; if(u==='paquete') return 'pack'; return u }
const orig = txt.trim()
if(!orig){ console.log(JSON.stringify({quantity:1,unit:'unit',name:''})); process.exit(0) }
const re1 = /^\s*(\d+(?:[.,]\d+)?)\s*(kg|g|gr|l|lt|ml|un|unidad|unidades|pack|paquete|x)\b/i
let m = orig.match(re1)
if(m){
  let q = parseFloat(m[1].replace(',', '.'))
  let u = normalizeUnit(m[2])
  let name = orig.substring(m[0].length).trim()
  if(!name) name = orig
  console.log(JSON.stringify({quantity: q, unit: u, name: name}))
  process.exit(0)
}
const re2 = /(\d+(?:[.,]\d+)?)\s*(kg|g|gr|l|lt|ml|un|unidad|unidades|pack|paquete|x)\b/i
let m2 = orig.match(re2)
if(m2){
  let q = parseFloat(m2[1].replace(',', '.'))
  let u = normalizeUnit(m2[2])
  let name = orig.replace(m2[0],'').trim()
  if(!name) name = orig
  console.log(JSON.stringify({quantity: q, unit: u, name: name}))
  process.exit(0)
}
console.log(JSON.stringify({quantity:1,unit:'unit',name:orig}))
NODE
