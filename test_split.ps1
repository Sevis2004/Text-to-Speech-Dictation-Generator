param(
    [string]$Text
)

. "$PSScriptRoot\lib\split.ps1"

cls

Write-Host ""
Write-Host "=== SENTENCES ===" -ForegroundColor Cyan

$sentences = Split-Sentences $Text

$i=1
foreach ($s in $sentences) {
    Write-Host "$i`t$s"
    $i++
}

Write-Host ""
Write-Host "=== PHRASES ===" -ForegroundColor Yellow

foreach ($s in $sentences) {

    Write-Host ""
    Write-Host $s -ForegroundColor Green

    $phrases = Get-AutoSplitLegacy $s

    foreach ($p in $phrases) {
        Write-Host "   -> $p"
    }
}