<#
PowerShell wrapper: scrape-prices.ps1
Usage example:
  powershell -File .\scrape-prices.ps1 -Items "pan integral","leche" -Sites "super","jumbo" -Output results.csv

Requirements:
  - Node.js >= 16
  - npm install (in this repo)
  - npx playwright install --with-deps
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true, Position=0)]
  [string[]]$Items,

  [Parameter(Position=1)]
  [string[]]$Sites = @('super','jumbo'),

  [string]$Output = ''
)

function Ensure-Node {
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js not found. Install Node.js (>=16) and run 'npm install' in the repo root."
    exit 1
  }
}

Ensure-Node

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$nodeScript = Join-Path $scriptDir 'scraper.js'
if (-not (Test-Path $nodeScript)) {
  Write-Error "scraper.js not found at $nodeScript"
  exit 1
}

$results = @()

foreach ($item in $Items) {
  foreach ($site in $Sites) {
    $siteArg = switch ($site.ToLower()) {
      'super' { 'super' }
      'lider' { 'super' }
      'jumbo' { 'jumbo' }
      default { $site }
    }

    Write-Host "Searching '$item' on $siteArg..."
    $raw = & node $nodeScript $siteArg $item 2>&1

    # Prefer the marker-wrapped JSON output if present (scraper prints ___BEGIN___{...}___END___)
    $markerLine = $raw | Where-Object { $_ -match '^___BEGIN___' } | Select-Object -Last 1
    if ($markerLine) {
      $m = [regex]::Match($markerLine, '___BEGIN___(.*)___END___')
      if ($m.Success) { $jsonLine = $m.Groups[1].Value } else { $jsonLine = $markerLine -replace '^___BEGIN___','' }
      Write-Host "DEBUG: extracted JSON from marker (truncated): $($jsonLine.ToString().Substring(0,[Math]::Min(400,$jsonLine.ToString().Length)))"
    } else {
      # Fallback: find the last JSON-looking line in the output
      $jsonLine = $raw | Where-Object { $_ -match '^\s*[\{\[]' } | Select-Object -Last 1
      if ($jsonLine) { Write-Host "DEBUG: selected JSON line (truncated): $($jsonLine.ToString().Substring(0,[Math]::Min(400,$jsonLine.ToString().Length)))" } else { Write-Host "DEBUG: no JSON-looking line found in node output" }
    }

    if (-not $jsonLine) {
      Write-Warning "No JSON output for '$item' on $siteArg. Raw output:" 
      $raw | ForEach-Object { Write-Host $_ }
      continue
    }

    try {
      $parsed = $jsonLine | ConvertFrom-Json -ErrorAction Stop
      if ($parsed.items) {
        for ($i = 0; $i -lt $parsed.items.Count; $i++) {
          $it = $parsed.items[$i]

          # Extract fields safely (avoid inline if-expressions inside hashtable initializer)
          $title = $null
          $price = $null
          $currency = $null
          $size = $null
          $unit = $null
          $unit_price = $null
          $product_url = $null
          $rawVal = $null

          if ($it -is [System.Management.Automation.PSCustomObject]) {
            if ($it.PSObject.Properties.Name -contains 'title') { $title = $it.title }
            if ($it.PSObject.Properties.Name -contains 'price') { $price = $it.price }
            if ($it.PSObject.Properties.Name -contains 'currency') { $currency = $it.currency }
            if ($it.PSObject.Properties.Name -contains 'size') { $size = $it.size }
            if ($it.PSObject.Properties.Name -contains 'unit') { $unit = $it.unit }
            if ($it.PSObject.Properties.Name -contains 'unitPrice') { $unit_price = $it.unitPrice }
            if ($it.PSObject.Properties.Name -contains 'productUrl') { $product_url = $it.productUrl }
            if ($it.PSObject.Properties.Name -contains 'raw') { $rawVal = $it.raw } else { $rawVal = $it.ToString() }
          } else {
            $title = $it.ToString()
            $rawVal = $it.ToString()
          }

          $results += [PSCustomObject]@{
            site = $parsed.site
            query = $parsed.query
            index = $i + 1
            title = $title
            price = $price
            currency = $currency
            size = $size
            unit = $unit
            unit_price = $unit_price
            product_url = $product_url
            raw = $rawVal
          }
        }
      }
    } catch {
      Write-Warning ("Failed to parse JSON for '{0}' on {1}: {2}" -f $item, $siteArg, $_)
    }
  }
}

if ($Output) {
  $results | Export-Csv -Path $Output -NoTypeInformation -Encoding UTF8
  Write-Host "Saved results to $Output"
} else {
  if ($results.Count) {
    $results | Format-Table -AutoSize
  } else {
    Write-Host "No results found."
  }
}
