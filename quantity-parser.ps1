<#
quantity-parser.ps1
Provides Parse-QuantityString function to extract quantity, unit, and cleaned name from a freeform item string.
#>

function Parse-QuantityString {
  param([string]$Text)
  if (-not $Text) {
    return [PSCustomObject]@{ quantity = 1; unit = 'unit'; name = '' }
  }

  $orig = $Text.Trim()

  # pattern: leading quantity e.g. '2 kg apples'
  $m = [regex]::Match($orig, '^\s*(\d+(?:[.,]\d+)?)\s*(kg|g|gr|l|lt|ml|un|unidad|unidades|pack|paquete|x)\b', 'IgnoreCase')
  if ($m.Success) {
    $q = ($m.Groups[1].Value -replace ',', '.')
    $u = $m.Groups[2].Value.ToLower()
    switch ($u) {
      'gr' { $u = 'g' }
      'lt' { $u = 'l' }
      'unidad' { $u = 'unit' }
      'unidades' { $u = 'unit' }
      'un' { $u = 'unit' }
      'paquete' { $u = 'pack' }
    }
    $name = $orig.Substring($m.Length).Trim()
    if (-not $name) { $name = $orig }
    return [PSCustomObject]@{ quantity = [double]$q; unit = $u; name = $name }
  }

  # pattern: trailing or embedded quantity e.g. 'apples 2 kg'
  $m2 = [regex]::Match($orig, '(\d+(?:[.,]\d+)?)\s*(kg|g|gr|l|lt|ml|un|unidad|unidades|pack|paquete|x)\b', 'IgnoreCase')
  if ($m2.Success) {
    $q = ($m2.Groups[1].Value -replace ',', '.')
    $u = $m2.Groups[2].Value.ToLower()
    switch ($u) {
      'gr' { $u = 'g' }
      'lt' { $u = 'l' }
      'unidad' { $u = 'unit' }
      'unidades' { $u = 'unit' }
      'un' { $u = 'unit' }
      'paquete' { $u = 'pack' }
    }
    $name = ($orig -replace [regex]::Escape($m2.Value), '').Trim()
    if (-not $name) { $name = $orig }
    return [PSCustomObject]@{ quantity = [double]$q; unit = $u; name = $name }
  }

  # default: quantity 1, unit 'unit'
  return [PSCustomObject]@{ quantity = 1; unit = 'unit'; name = $orig }
}
