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

function Split-PhraseLegacy {
    param([string]$Sentence)
    return (Get-AutoSplitLegacy -Sentence $Sentence)
}

function Get-NormalizedWord {
    param([string]$Word)
    if ([string]::IsNullOrWhiteSpace($Word)) { return '' }
    return ([regex]::Replace($Word.ToLowerInvariant(), '^[^\p{L}\p{Nd}-]+|[^\p{L}\p{Nd}-]+$', '')).Trim()
}

function Get-AdvancedChunkPenalty {
    param([string[]]$Words, [int]$SplitIndex)

    if ($SplitIndex -le 0 -or $SplitIndex -ge $Words.Count) { return 9999 }

    $leftCount = $SplitIndex
    $rightCount = $Words.Count - $SplitIndex
    $penalty = 0

    if ($leftCount -eq 1) { $penalty += 9 }
    if ($rightCount -eq 1) { $penalty += 9 }
    if ($leftCount -lt 2) { $penalty += 3 }
    if ($rightCount -lt 2) { $penalty += 3 }
    if ($leftCount -gt 6) { $penalty += 2 * ($leftCount - 6) }
    if ($rightCount -gt 6) { $penalty += 2 * ($rightCount - 6) }

    $leftWord = Get-NormalizedWord -Word $Words[$SplitIndex - 1]
    $rightWord = Get-NormalizedWord -Word $Words[$SplitIndex]

    $prepositions = @('в','на','под','над','за','к','ко','по','о','об','обо','у','из','с','со','от','для','без','при','между','через','перед')
    if ($prepositions -contains $leftWord) { $penalty += 8 }

    $adjectivalEndings = @('ый','ий','ой','ая','яя','ое','ее','ые','ие','ого','его','ому','ему','ым','им','ую','юю','ых','их','ыми','ими')
    foreach ($ending in $adjectivalEndings) {
        if ($leftWord.EndsWith($ending) -and $rightWord.Length -ge 2) {
            $penalty += 6
            break
        }
    }

    return $penalty
}

function Split-AdvancedChunk {
    param([string]$Chunk)

    $chunk = $Chunk.Trim()
    if (-not $chunk) { return @() }

    $words = @($chunk -split '\s+' | Where-Object { $_ })
    if ($words.Count -le 5) {
        return @($chunk)
    }

    $bestIndex = -1
    $bestPenalty = [int]::MaxValue
    for ($i = 2; $i -le ($words.Count - 2); $i++) {
        $penalty = Get-AdvancedChunkPenalty -Words $words -SplitIndex $i
        if ($penalty -lt $bestPenalty) {
            $bestPenalty = $penalty
            $bestIndex = $i
        }
    }

    if ($bestIndex -lt 0) {
        $bestIndex = [math]::Floor($words.Count / 2)
    }

    $left = ($words[0..($bestIndex-1)] -join ' ').Trim()
    $right = ($words[$bestIndex..($words.Count-1)] -join ' ').Trim()

    $result = @()
    if ((Get-WordCount $left) -gt 6) {
        $result += (Split-AdvancedChunk -Chunk $left)
    }
    else {
        $result += $left
    }

    if ((Get-WordCount $right) -gt 6) {
        $result += (Split-AdvancedChunk -Chunk $right)
    }
    else {
        $result += $right
    }

    return @($result | Where-Object { $_ })
}

function Split-PhraseAdvanced {
    param([string]$Sentence)

    $sentence = $Sentence.Trim()
    if (-not $sentence) { return @() }

    $core = $sentence
    if ($core -match '[.!?]$') {
        $core = $core.Substring(0, $core.Length - 1)
    }

    $coordinating = @('и','а','но')
    $subordinate = @('когда','где','если','чтобы','хотя')

    $rawChunks = New-Object System.Collections.Generic.List[string]
    $commaChunks = @($core -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    foreach ($chunk in $commaChunks) {
        $tokens = @($chunk -split '\s+' | Where-Object { $_ })
        if ($tokens.Count -le 6) {
            $rawChunks.Add($chunk)
            continue
        }

        $splitIndex = -1
        for ($i = 2; $i -lt $tokens.Count; $i++) {
            $word = Get-NormalizedWord -Word $tokens[$i]
            if ($coordinating -contains $word -or $subordinate -contains $word) {
                $splitIndex = $i
                break
            }

            if ($word -eq 'потому' -and $i + 1 -lt $tokens.Count) {
                $nextWord = Get-NormalizedWord -Word $tokens[$i + 1]
                if ($nextWord -eq 'что') {
                    $splitIndex = $i
                    break
                }
            }
        }

        if ($splitIndex -gt 1 -and $splitIndex -lt ($tokens.Count - 1)) {
            $left = ($tokens[0..($splitIndex-1)] -join ' ').Trim()
            $right = ($tokens[$splitIndex..($tokens.Count-1)] -join ' ').Trim()
            if ((Get-WordCount $left) -ge 2 -and (Get-WordCount $right) -ge 2) {
                $rawChunks.Add($left)
                $rawChunks.Add($right)
                continue
            }
        }

        $rawChunks.Add($chunk)
    }

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($chunk in $rawChunks) {
        if ((Get-WordCount $chunk) -gt 6) {
            foreach ($subChunk in (Split-AdvancedChunk -Chunk $chunk)) {
                $result.Add($subChunk)
            }
        }
        else {
            $result.Add($chunk)
        }
    }

    return @($result | Where-Object { $_ })
}

function Resolve-SplitMode {
    param([string]$SplitMode)

    if ([string]::IsNullOrWhiteSpace($SplitMode)) {
        return 'legacy'
    }

    $mode = $SplitMode.Trim().ToLowerInvariant()
    if (@('legacy','advanced','compare') -contains $mode) {
        return $mode
    }

    return 'legacy'
}

function Get-PhraseSplitComparison {
    param([string]$Sentence)

    return [PSCustomObject]@{
        Legacy   = @(Split-PhraseLegacy -Sentence $Sentence)
        Advanced = @(Split-PhraseAdvanced -Sentence $Sentence)
    }
}

function Get-OverrideOrAutoSplit {
    param(
        [string]$Slug,
        [string]$Sentence,
        [hashtable]$Overrides,
        [string]$SplitMode = 'legacy'
    )

    $key = "$Slug||$Sentence"
    if ($Overrides.ContainsKey($key)) {
        return $Overrides[$key]
    }

    switch (Resolve-SplitMode -SplitMode $SplitMode) {
        'advanced' { return (Split-PhraseAdvanced -Sentence $Sentence) }
        'compare' { return (Split-PhraseLegacy -Sentence $Sentence) }
        default { return (Split-PhraseLegacy -Sentence $Sentence) }
    }
}
