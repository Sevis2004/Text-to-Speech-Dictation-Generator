function Split-Sentences {
    param([string]$Paragraph)

    if ([string]::IsNullOrWhiteSpace($Paragraph)) { return @() }

    $Paragraph = $Paragraph -replace "`r",' '
    $Paragraph = $Paragraph -replace "`n",' '

    return [regex]::Split($Paragraph.Trim(), '(?<=[.!?])\s+')
}

function Get-WordCount {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    return (@($Text.Trim() -split '\s+' | Where-Object { $_ })).Count
}

function Split-LongChunk {
    param([string]$Chunk)

    $chunk = $Chunk.Trim()
    if (-not $chunk) { return @() }

    $words = @($chunk -split '\s+' | Where-Object { $_ })
    if ($words.Count -le 5) {
        return @($chunk)
    }

    $leadingConjunctions = @('когда','чтобы','где','если','хотя')
    if ($leadingConjunctions -contains $words[0].ToLowerInvariant()) {
        if ($words.Count -ge 5) {
            $leftCount = $words.Count - 2
            if ($leftCount -ge 2) {
                return @(
                    ($words[0..($leftCount-1)] -join ' ').Trim(),
                    ($words[$leftCount..($words.Count-1)] -join ' ').Trim()
                )
            }
        }
    }

    if ($words.Count -gt 8) {
        $conjunctions = @('и','но','а','чтобы','когда','где')
        for ($i = 1; $i -lt $words.Count; $i++) {
            $w = $words[$i].ToLowerInvariant()
            if ($conjunctions -contains $w) {
                $left = ($words[0..($i-1)] -join ' ').Trim()
                $right = ($words[$i..($words.Count-1)] -join ' ').Trim()
                if ((Get-WordCount $left) -ge 2 -and (Get-WordCount $right) -ge 2) {
                    $result = @()
                    $result += (Split-LongChunk -Chunk $left)
                    $result += (Split-LongChunk -Chunk $right)
                    return $result
                }
            }
        }
    }

    $mid = [math]::Floor($words.Count / 2)
    if ($mid -lt 1) { $mid = 1 }
    return @(
        ($words[0..($mid-1)] -join ' ').Trim(),
        ($words[$mid..($words.Count-1)] -join ' ').Trim()
    )
}

function Get-AutoSplitLegacy {
    param([string]$Sentence)

    $sentence = $Sentence.Trim()
    if (-not $sentence) { return @() }

    $core = $sentence
    if ($core -match '[.!?]$') {
        $core = $core.Substring(0, $core.Length - 1)
    }

    $parts = @()
    $chunks = @($core -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($chunk in $chunks) {
        $parts += (Split-LongChunk -Chunk $chunk)
    }

    if ($parts.Count -eq 0) {
        return @($core)
    }
    return $parts
}

function Get-OverrideOrAutoSplit {
    param(
        [string]$Slug,
        [string]$Sentence,
        [hashtable]$Overrides
    )

    $key = "$Slug||$Sentence"
    if ($Overrides.ContainsKey($key)) {
        return $Overrides[$key]
    }

    return (Get-AutoSplitLegacy -Sentence $Sentence)
}