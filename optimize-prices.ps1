<#
optimize-prices.ps1
Given a requests JSON (from agent) and the raw scraped results CSV, match requested items to scraped products,
compute normalized unit prices, compute per-store totals and select the single-store lowest total purchase.

Usage:
  .\optimize-prices.ps1 -RequestsPath .\requests-12345.json -ResultsCsv .\results.csv -OutFile recommendation.csv

This is a heuristic implementation: token overlap + normalized pricing.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$RequestsPath,
  [Parameter(Mandatory=$false)][string]$ResultsCsv = 'results.csv',
  [Parameter(Mandatory=$false)][string]$OutFile = ''
)

function Normalize-Text {
  param([string]$s)
  if (-not $s) { return @() }
  $s = $s.ToLowerInvariant()
  # simple accent removal
  $s = $s -replace 'á','a' -replace 'é','e' -replace 'í','i' -replace 'ó','o' -replace 'ú','u' -replace 'ñ','n'
  # remove punctuation
  $s = $s -replace "[\p{P}\p{S}]", ' '
  $tokens = $s -split '\s+' | Where-Object { $_ -and $_ -notin @('de','el','la','en','y','con','para','un','una','unidades','pack') }
  return ($tokens | ForEach-Object { $_.Trim() })
}

function TokenScore {
  param([string]$req, [string]$title)
  $rt = Normalize-Text -s $req
  $tt = Normalize-Text -s $title
  if ($rt.Count -eq 0) { return 0.0 }
  $common = ($rt | Where-Object { $tt -contains $_ })
  return [double]($common.Count) / [double]($rt.Count)
}

function Parse-Size {
  param([string]$sizeStr)
  if (-not $sizeStr) { return $null }
  $m = [regex]::Match($sizeStr, '(\d+(?:[\.,]\d+)?)\s*(kg|g|gr|ml|l|un|unidad|unidades)', 'IgnoreCase')
  if ($m.Success) {
    $num = [double]($m.Groups[1].Value -replace ',', '.')
    $unit = $m.Groups[2].Value.ToLower()
    switch ($unit) {
      'gr' { $unit = 'g' }
      'unidad' { $unit = 'unit' }
      'unidades' { $unit = 'unit' }
      'un' { $unit = 'unit' }
      'lt' { $unit = 'l' }
    }
    return @{ size = $num; unit = $unit }
  }
  return $null
}

function Compute-NormalizedUnitPrice {
  param([pscustomobject]$row, [string]$requestedUnit)
  # return @{ unitPrice = <number>; unit = '<unit>' } or $null if not convertible
  $price = $null
  if ($row.price -and ($row.price -ne '')) {
    # numeric conversion: remove thousand sep
    $price = ([string]$row.price) -replace '\.','' -replace ',','.'
    try { $price = [double]$price } catch { $price = $null }
  }

  # if explicit unit_price field exists, prefer it (this came from scraper unitPrice field)
  if ($row.unit_price -and ($row.unit_price -ne '')) {
    $up = ([string]$row.unit_price) -replace '\.','' -replace ',','.'
    try { $upn = [double]$up } catch { $upn = $null }
  } else { $upn = $null }

  $sizeInfo = $null
  if ($row.size) { $sizeInfo = Parse-Size -sizeStr $row.size }

  # requestedUnit normalization
  switch ($requestedUnit) {
    'g' { $reqU = 'g' }
    'kg' { $reqU = 'kg' }
    'l' { $reqU = 'l' }
    'ml' { $reqU = 'ml' }
    default { $reqU = 'unit' }
  }

  if ($sizeInfo -ne $null -and $price -ne $null) {
    $pSize = $sizeInfo['size']; $pUnit = $sizeInfo['unit']
    # grams/kilograms
    if ($reqU -in @('kg','g') -and $pUnit -in @('kg','g')) {
      $sizeKg = if ($pUnit -eq 'g') { $pSize/1000.0 } else { $pSize }
      if ($sizeKg -ne 0) {
        $pricePerKg = $price / $sizeKg
        if ($reqU -eq 'kg') { return @{ unitPrice = $pricePerKg; unit = 'kg' } }
        if ($reqU -eq 'g') { return @{ unitPrice = $pricePerKg / 1000.0; unit = 'g' } }
      }
    }
    # liters
    if ($reqU -in @('l','ml') -and $pUnit -in @('l','ml')) {
      $sizeL = if ($pUnit -eq 'ml') { $pSize/1000.0 } else { $pSize }
      if ($sizeL -ne 0) {
        $pricePerL = $price / $sizeL
        if ($reqU -eq 'l') { return @{ unitPrice = $pricePerL; unit = 'l' } }
        if ($reqU -eq 'ml') { return @{ unitPrice = $pricePerL / 1000.0; unit = 'ml' } }
      }
    }
    # units
    if ($reqU -eq 'unit' -and $pUnit -eq 'unit') {
      return @{ unitPrice = $price; unit = 'unit' }
    }
    if ($reqU -eq 'unit' -and $pUnit -ne 'unit' -and $pUnit -in @('kg','g','l','ml')) {
      # cannot reliably convert weight/volume to unit
      return $null
    }
  }

  # Fallback: use provided unit price value (upn) if available
  if ($upn -ne $null) {
    return @{ unitPrice = $upn; unit = ($row.unit -or 'kg') }
  }

  # Last resort: if no size/unit info, treat as per-unit
  if ($price -ne $null) { return @{ unitPrice = $price; unit = 'unit' } }

  return $null
}

# --- main ---
if (-not (Test-Path $RequestsPath)) { Write-Error "Requests file not found: $RequestsPath"; exit 2 }
if (-not (Test-Path $ResultsCsv)) { Write-Error "Results CSV not found: $ResultsCsv"; exit 2 }

$requests = Get-Content $RequestsPath | ConvertFrom-Json
$results = Import-Csv -Path $ResultsCsv | ForEach-Object {
  # normalize property names
  [PSCustomObject]@{
    site = $_.site
    query = $_.query
    index = $_.index
    title = $_.title
    price = $_.price
    currency = $_.currency
    size = $_.size
    unit = $_.unit
    unit_price = $_.unit_price
    product_url = $_.product_url
    raw = $_.raw
  }
}

$stores = ($results | Select-Object -ExpandProperty site | Sort-Object -Unique)

$recommendations = @()
$feasibleStores = @{}

foreach ($store in $stores) { $feasibleStores[$store] = $true }

# For each store, try to find best candidate for each request
$storeTotals = @{}
foreach ($store in $stores) { $storeTotals[$store] = 0.0 }

foreach ($req in $requests) {
  $reqName = $req.original -or $req.query
  $reqQty = [double]$req.quantity
  $reqUnit = $req.unit

  foreach ($store in $stores) {
    $candidates = $results | Where-Object { $_.query -eq $req.query -and $_.site -eq $store }
    if (-not $candidates -or $candidates.Count -eq 0) {
      # mark store infeasible
      $feasibleStores[$store] = $false
      continue
    }

    $best = $null
    $bestScore = [double]::PositiveInfinity

    foreach ($cand in $candidates) {
      $tokenScore = TokenScore -req $reqName -title $cand.title
      $norm = Compute-NormalizedUnitPrice -row $cand -requestedUnit $reqUnit
      if ($norm -eq $null) { continue }
      $estCost = $norm.unitPrice * $reqQty
      # avoid zero tokenScore
      $ts = [Math]::Max(0.01, [double]$tokenScore)
      $combined = $estCost / $ts
      if ($combined -lt $bestScore) {
        $bestScore = $combined
        $best = @{ candidate = $cand; norm = $norm; estCost = $estCost; tokenScore = $tokenScore }
      }
    }

    if ($best -eq $null) {
      $feasibleStores[$store] = $false
    } else {
      # accumulate
      $storeTotals[$store] += $best.estCost
      # store best selection for reporting
      $recommendations += [PSCustomObject]@{
        store = $store
        request = $reqName
        query = $req.query
        quantity = $reqQty
        req_unit = $reqUnit
        matched_title = $best.candidate.title
        price = $best.candidate.price
        match_score = $best.tokenScore
        unit_price = $best.norm.unitPrice
        unit = $best.norm.unit
        item_total = $best.estCost
        product_url = $best.candidate.product_url
      }
    }
  }
}

# Filter feasible stores
$feasible = $stores | Where-Object { $feasibleStores[$_] }
if (-not $feasible -or $feasible.Count -eq 0) {
  Write-Warning "No single store can supply all requested items. Consider allowing cross-store optimization or relaxing constraints."
  # still write partial recommendations
  if (-not $OutFile) { $OutFile = "recommendation-$(Get-Date -UFormat %s).csv" }
  $recommendations | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
  Write-Host "Partial recommendations saved to $OutFile"
  exit 0
}

# Choose the feasible store with lowest total
$bestStore = $null; $bestTotal = [double]::PositiveInfinity
foreach ($s in $feasible) {
  $t = $storeTotals[$s]
  if ($t -lt $bestTotal) { $bestTotal = $t; $bestStore = $s }
}

# Filter recommendations to bestStore
$final = $recommendations | Where-Object { $_.store -eq $bestStore }
if (-not $OutFile) { $OutFile = "recommendation-$(Get-Date -UFormat %s).csv" }
$final | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
Write-Host "Chosen store: $bestStore  Total: $([Math]::Round($bestTotal,2))"
Write-Host "Recommendations saved to $OutFile"
