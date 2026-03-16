param(
    [string]$Text,
    [string]$SplitMode = 'compare'
)

. "$PSScriptRoot\lib\split.ps1"

cls

$mode = Resolve-SplitMode -SplitMode $SplitMode
$sentences = Split-Sentences $Text

foreach ($s in $sentences) {
    Write-Host ""
    Write-Host "=== SENTENCE ===" -ForegroundColor Cyan
    Write-Host $s

    $comparison = Get-PhraseSplitComparison -Sentence $s
    $legacy = @($comparison.Legacy)
    $advanced = @($comparison.Advanced)

    if ($mode -eq 'legacy') {
        Write-Host ""
        Write-Host "LEGACY:" -ForegroundColor Yellow
        foreach ($p in $legacy) {
            Write-Host "→ $p"
        }
        continue
    }

    if ($mode -eq 'advanced') {
        Write-Host ""
        Write-Host "ADVANCED:" -ForegroundColor Yellow
        foreach ($p in $advanced) {
            Write-Host "→ $p"
        }
        continue
    }

    Write-Host ""
    Write-Host "LEGACY:" -ForegroundColor Yellow
    foreach ($p in $legacy) {
        Write-Host "→ $p"
    }

    Write-Host ""
    Write-Host "ADVANCED:" -ForegroundColor Green
    foreach ($p in $advanced) {
        Write-Host "→ $p"
    }

    $legacyJoined = $legacy -join '|'
    $advancedJoined = $advanced -join '|'
    if ($legacyJoined -ne $advancedJoined) {
        Write-Host ""
        Write-Host "DIFFERENCE DETECTED" -ForegroundColor Magenta
    }
}
