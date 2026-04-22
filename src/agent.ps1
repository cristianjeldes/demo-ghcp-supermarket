[CmdletBinding()]
param(
  [string]$Prompt = '',
  [string[]]$Items = @(),
  [string[]]$Sites = @('super','jumbo'),
  [string]$Output = ''
)

function Parse-PromptToItems {
  param([string]$prompt)
  if (-not $prompt) { return @() }
  # split on commas, semicolons, ' and ', ' y ', ampersand
  $parts = $prompt -split '[,;]| and | & |\s+y\s+'
  return $parts | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}

if (-not $Items -or $Items.Count -eq 0) {
  if ($Prompt) { $Items = Parse-PromptToItems -prompt $Prompt }
}

if (-not $Items -or $Items.Count -eq 0) {
  Write-Error "No items provided. Use -Items or -Prompt to specify a list of items to scrape."
  exit 2
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Parent $scriptDir
$artifacts = Join-Path $repoRoot 'artifacts'
if (-not (Test-Path $artifacts)) { New-Item -ItemType Directory -Force -Path $artifacts | Out-Null }

$main = Join-Path $scriptDir 'scrape-prices.ps1'
if (-not (Test-Path $main)) { Write-Error "scrape-prices.ps1 not found in $scriptDir"; exit 1 }

Write-Host "Agent (src): scraping items: $($Items -join ', ') on sites: $($Sites -join ', ')"

# Dot-source quantity parser if available
$qp = Join-Path $scriptDir 'quantity-parser.ps1'
if (Test-Path $qp) { . $qp } else { Write-Verbose "quantity-parser.ps1 not found; continuing without quantity parsing" }

# Parse items into requests (name + quantity)
$requests = @()
foreach ($item in $Items) {
  if (Get-Command -Name Parse-QuantityString -ErrorAction SilentlyContinue) {
    $p = Parse-QuantityString -Text $item
  } else {
    $p = [PSCustomObject]@{ quantity = 1; unit = 'unit'; name = $item.Trim() }
  }
  $requests += [PSCustomObject]@{ query = $p.name; quantity = $p.quantity; unit = $p.unit; original = $item }
}

$queries = $requests | ForEach-Object { $_.query }

# Save parsed requests in artifacts
$requestsPath = Join-Path $artifacts ('requests-' + (Get-Date -UFormat %s) + '.json')
$requests | ConvertTo-Json -Depth 4 | Out-File $requestsPath -Encoding UTF8
Write-Host "Parsed requests saved to $requestsPath"

# Delegate to scraper with cleaned queries
# Determine results CSV path (in artifacts by default)
$resultsCsv = if ($Output) { $Output } else { Join-Path $artifacts 'results.csv' }
# Run scraper
& $main -Items $queries -Sites $Sites -Output $resultsCsv

# Run optimizer (product matching + pricing normalization)
$opt = Join-Path $scriptDir 'optimize-prices.ps1'
if (Test-Path $opt) {
  & $opt -RequestsPath $requestsPath -ResultsCsv $resultsCsv
} else {
  Write-Warning "optimize-prices.ps1 not found; skipping optimization step"
}
