param(
  [Parameter(Mandatory=$true)][string[]]$Items,
  [string]$Output = ''
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$main = Join-Path $scriptDir 'scrape-prices.ps1'
& $main -Items $Items -Sites @('super') -Output $Output
