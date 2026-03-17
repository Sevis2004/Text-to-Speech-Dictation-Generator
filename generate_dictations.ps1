cls
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\split.ps1"

function Get-ArgumentValue {
    param(
        [string[]]$Arguments,
        [string]$Name,
        [string]$Default = ''
    )

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        if ($Arguments[$i] -ieq $Name) {
            if ($i + 1 -lt $Arguments.Count) {
                return $Arguments[$i + 1]
            }
            return $Default
        }
    }

    return $Default
}

$script:RunMode = (Get-ArgumentValue -Arguments $args -Name '-Mode' -Default 'missing').ToLowerInvariant()
$script:SelectedSlugsRaw = Get-ArgumentValue -Arguments $args -Name '-Slugs' -Default ''
$script:SelectedSlugs = @{}
if (-not [string]::IsNullOrWhiteSpace($script:SelectedSlugsRaw)) {
    foreach ($slug in ($script:SelectedSlugsRaw -split ',')) {
        $s = $slug.Trim().ToLowerInvariant()
        if ($s) { $script:SelectedSlugs[$s] = $true }
    }
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$time] [$Level] $Message"
    Write-Host $line

    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    }
}

function Load-Config {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "config.json not found: $Path"
    }

    $config = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json

    $localPath = Join-Path (Split-Path -Parent $Path) 'config.local.json'
    if (Test-Path $localPath) {
        $localConfig = Get-Content $localPath -Raw -Encoding UTF8 | ConvertFrom-Json

        if ($localConfig.PSObject.Properties.Name -contains 'ApiKey') {
            if ($config.PSObject.Properties.Name -contains 'ApiKey') {
                $config.ApiKey = $localConfig.ApiKey
            }
            else {
                $config | Add-Member -NotePropertyName ApiKey -NotePropertyValue $localConfig.ApiKey
            }
        }

        if ($localConfig.PSObject.Properties.Name -contains 'tts') {
            if (-not ($config.PSObject.Properties.Name -contains 'tts')) {
                $config | Add-Member -NotePropertyName tts -NotePropertyValue ([pscustomobject]@{})
            }

            if ($localConfig.tts -and ($localConfig.tts.PSObject.Properties.Name -contains 'apiKey')) {
                if ($config.tts.PSObject.Properties.Name -contains 'apiKey') {
                    $config.tts.apiKey = $localConfig.tts.apiKey
                }
                else {
                    $config.tts | Add-Member -NotePropertyName apiKey -NotePropertyValue $localConfig.tts.apiKey
                }
            }
        }

        if ($localConfig.PSObject.Properties.Name -contains 'tools') {

            if (-not ($config.PSObject.Properties.Name -contains 'tools')) {
                $config | Add-Member -NotePropertyName tools -NotePropertyValue ([pscustomobject]@{})
            }

            foreach ($prop in $localConfig.tools.PSObject.Properties.Name) {
                if ($config.tools.PSObject.Properties.Name -contains $prop) {
                    $config.tools.$prop = $localConfig.tools.$prop
                }
                else {
                    $config.tools | Add-Member -NotePropertyName $prop -NotePropertyValue $localConfig.tools.$prop
                }
            }
        }

    }

    return $config
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Initialize-ProjectFolders {
    param(
        $Config,
        [string]$ProjectRoot
    )

    if (-not [System.IO.Path]::IsPathRooted($Config.paths.outputSiteDir)) {
    $Config.paths.outputSiteDir = Join-Path $ProjectRoot $Config.paths.outputSiteDir
    }
        if (-not [System.IO.Path]::IsPathRooted($Config.paths.outputTempDir)) {
        $Config.paths.outputTempDir = Join-Path $ProjectRoot $Config.paths.outputTempDir
    }
    if (-not [System.IO.Path]::IsPathRooted($Config.paths.outputLogsDir)) {
        $Config.paths.outputLogsDir = Join-Path $ProjectRoot $Config.paths.outputLogsDir
    }
    if (-not [System.IO.Path]::IsPathRooted($Config.paths.inputFile)) {
        $Config.paths.inputFile = Join-Path $ProjectRoot $Config.paths.inputFile
    }
    if (-not [System.IO.Path]::IsPathRooted($Config.paths.indexTemplate)) {
        $Config.paths.indexTemplate = Join-Path $ProjectRoot $Config.paths.indexTemplate
    }
    if ($Config.paths.overridesFile -and -not [System.IO.Path]::IsPathRooted($Config.paths.overridesFile)) {
        $Config.paths.overridesFile = Join-Path $ProjectRoot $Config.paths.overridesFile
    }

    Ensure-Directory $Config.paths.outputSiteDir
    Ensure-Directory $Config.paths.outputTempDir
    Ensure-Directory $Config.paths.outputLogsDir

    $script:TtsCacheDir = Join-Path $ProjectRoot 'cache\tts_wav'
    $script:SilenceCacheDir = Join-Path $ProjectRoot 'cache\silence_wav'
    Ensure-Directory $script:TtsCacheDir
    Ensure-Directory $script:SilenceCacheDir

    $script:LogFile = Join-Path $Config.paths.outputLogsDir ("generation_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
    New-Item -Path $script:LogFile -ItemType File -Force | Out-Null
}

function Read-TextFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }
    return Get-Content $Path -Raw -Encoding UTF8
}

function Parse-BooleanOrDefault {
    param($Value, [bool]$Default)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $Default
    }

    switch -Regex (([string]$Value).Trim().ToLowerInvariant()) {
        '^true$|^1$|^yes$' { return $true }
        '^false$|^0$|^no$' { return $false }
        default { return $Default }
    }
}


function Get-SplitModeFromConfig {
    param($Config)

    if ($null -eq $Config -or -not ($Config.PSObject.Properties.Name -contains 'SplitMode')) {
        return 'legacy'
    }

    return (Resolve-SplitMode -SplitMode ([string]$Config.SplitMode))
}

function Parse-Dictations {
    param(
        [string]$RawText,
        $Config
    )

    $blocks = $RawText -split '(?m)^=== DICTATION ===\s*\r?\n'
    $dictations = @()

    foreach ($block in $blocks) {
        $current = $block.Trim()
        if ([string]::IsNullOrWhiteSpace($current)) { continue }

        $lines = $current -split "\r?\n"
        $meta = @{}
        $bodyLines = New-Object System.Collections.Generic.List[string]
        $inBody = $false

        foreach ($line in $lines) {
            if (-not $inBody -and $line -match '^\s*$') {
                $inBody = $true
                continue
            }

            if (-not $inBody -and $line -match '^\s*([A-Za-z][A-Za-z0-9_]*)\s*:\s*(.*)$') {
                $meta[$matches[1].Trim().ToLowerInvariant()] = $matches[2].Trim()
                continue
            }

            $inBody = $true
            $bodyLines.Add($line)
        }

        $heading = $null
        $bodyText = ($bodyLines -join "`n").Trim()

        $bodyText = $bodyText -replace "`r`n", "`n"
        $bodyLines2 = New-Object System.Collections.Generic.List[string]

        foreach ($line in ($bodyText -split "`n")) {
            $bodyLines2.Add($line)
        }

        while ($bodyLines2.Count -gt 0 -and [string]::IsNullOrWhiteSpace($bodyLines2[0])) {
            $bodyLines2.RemoveAt(0)
        }

        if ($bodyLines2.Count -gt 0 -and $bodyLines2[0] -match '^\s*#\s+(.+?)\s*$') {
            $heading = $matches[1].Trim()
            $bodyLines2.RemoveAt(0)
        }

        $bodyText = (($bodyLines2 | ForEach-Object { $_.TrimEnd() }) -join "`n").Trim()

        $paragraphs = @(
            $bodyText -split '(\n\s*\n)+' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
        )

        if (-not $meta.ContainsKey('title')) { throw 'Each dictation must contain title:' }
        if (-not $meta.ContainsKey('slug')) { throw "Dictation '$($meta['title'])' must contain slug:" }
        if ($paragraphs.Count -eq 0) { throw "Dictation '$($meta['title'])' has empty body" }

        $speedValue = if ($meta.ContainsKey('speed')) { [double]$meta['speed'] } else { [double]$Config.defaults.speed }
        $publishValue = if ($meta.ContainsKey('publish')) { $meta['publish'] } else { $null }

        $dictations += [PSCustomObject]@{
            Title      = $meta['title']
            Slug       = $meta['slug']
            Voice      = if ($meta.ContainsKey('voice')) { $meta['voice'] } else { $Config.defaults.voice }
            Speed      = $speedValue
            Publish    = Parse-BooleanOrDefault -Value $publishValue -Default ([bool]$Config.defaults.publish)
            Heading    = $heading
            Paragraphs = $paragraphs
        }
    }

    return $dictations
}

function Parse-Overrides {
    param([string]$RawText)

    $map = @{}
    if ([string]::IsNullOrWhiteSpace($RawText)) { return $map }

    $blocks = $RawText -split '(?m)^=== OVERRIDE ===\s*\r?\n'
    foreach ($block in $blocks) {
        $current = $block.Trim()
        if ([string]::IsNullOrWhiteSpace($current)) { continue }

        $slug = $null
        $sentence = $null
        $split = $null

        foreach ($line in ($current -split "\r?\n")) {
            if ($line -match '^\s*slug\s*:\s*(.+)$') { $slug = $matches[1].Trim(); continue }
            if ($line -match '^\s*sentence\s*:\s*(.+)$') { $sentence = $matches[1].Trim(); continue }
            if ($line -match '^\s*split\s*:\s*(.+)$') { $split = $matches[1].Trim(); continue }
        }

        if ($slug -and $sentence -and $split) {
            $key = "$slug||$sentence"
            $map[$key] = @($split -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }

    return $map
}

function Get-PauseTierPart1 {
    param([string]$Text)
    $count = Get-WordCount $Text
    if ($count -le 4) { return 'short' }
    if ($count -le 9) { return 'medium' }
    return 'long'
}

function Get-PauseTierPart2 {
    param([string]$Text)
    $count = Get-WordCount $Text
    if ($count -le 3) { return 'short' }
    if ($count -le 6) { return 'medium' }
    return 'long'
}

function New-PlanItemSpeak {
    param([string]$Text, [string]$Section)
    return [PSCustomObject]@{ Type = 'speak'; Text = $Text; Ms = 0; Section = $Section }
}

function New-PlanItemPause {
    param([int]$Ms, [string]$Section)
    return [PSCustomObject]@{ Type = 'pause'; Text = $null; Ms = $Ms; Section = $Section }
}

function Build-DictationPlan {
    param(
        $Dictation,
        $Config,
        [hashtable]$Overrides,
        [string]$SplitMode = 'legacy'
    )

    $plan = New-Object System.Collections.Generic.List[object]
    $part1 = $Config.pauses.part1
    $part2 = $Config.pauses.part2

    if ($Dictation.Heading) {
        $plan.Add((New-PlanItemSpeak -Text $Dictation.Heading -Section 'part1'))
        $plan.Add((New-PlanItemPause -Ms ([int]$part1.titleMs) -Section 'part1'))
    }

    foreach ($paragraph in $Dictation.Paragraphs) {
        $sentences = Split-Sentences -Paragraph $paragraph
        foreach ($sentence in $sentences) {
            $plan.Add((New-PlanItemSpeak -Text $sentence -Section 'part1'))
            switch (Get-PauseTierPart1 -Text $sentence) {
                'short'  { $plan.Add((New-PlanItemPause -Ms ([int]$part1.shortMs) -Section 'part1')); break }
                'medium' { $plan.Add((New-PlanItemPause -Ms ([int]$part1.mediumMs) -Section 'part1')); break }
                default  { $plan.Add((New-PlanItemPause -Ms ([int]$part1.longMs) -Section 'part1')); break }
            }
        }
        $plan.Add((New-PlanItemPause -Ms ([int]$part1.paragraphMs) -Section 'part1'))
    }

    if ($Dictation.Heading) {
        $plan.Add((New-PlanItemSpeak -Text $Dictation.Heading -Section 'part2'))
        $plan.Add((New-PlanItemPause -Ms ([int]$part2.beforeSplitMs) -Section 'part2'))
    }

    for ($pIndex = 0; $pIndex -lt $Dictation.Paragraphs.Count; $pIndex++) {
        $paragraph = $Dictation.Paragraphs[$pIndex]
        $sentences = Split-Sentences -Paragraph $paragraph

        if ($pIndex -gt 0) {
            $plan.Add((New-PlanItemSpeak -Text 'Следующий абзац.' -Section 'part2'))
            $plan.Add((New-PlanItemPause -Ms ([int]$part2.beforeSplitMs) -Section 'part2'))
        }

        foreach ($sentence in $sentences) {
            $plan.Add((New-PlanItemSpeak -Text $sentence -Section 'part2'))
            $plan.Add((New-PlanItemPause -Ms ([int]$part2.beforeSplitMs) -Section 'part2'))

            $splitParts = Get-OverrideOrAutoSplit -Slug $Dictation.Slug -Sentence $sentence -Overrides $Overrides -SplitMode $SplitMode
            foreach ($chunk in $splitParts) {
                $plan.Add((New-PlanItemSpeak -Text $chunk -Section 'part2'))
                switch (Get-PauseTierPart2 -Text $chunk) {
                    'short'  { $plan.Add((New-PlanItemPause -Ms ([int]$part2.shortMs) -Section 'part2')); break }
                    'medium' { $plan.Add((New-PlanItemPause -Ms ([int]$part2.mediumMs) -Section 'part2')); break }
                    default  { $plan.Add((New-PlanItemPause -Ms ([int]$part2.longMs) -Section 'part2')); break }
                }
            }

            $plan.Add((New-PlanItemPause -Ms ([int]$part2.sentenceEndMs) -Section 'part2'))
        }
    }

    return $plan.ToArray()
}

function Get-HashString {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-TtsCacheFile {
    param(
        [string]$Text,
        [string]$Voice,
        [double]$Speed,
        $Config
    )

    $speedString = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.##}', $Speed)
    $key = "voice=$Voice|speed=$speedString|format=$($Config.tts.format)|text=$Text"
    $hash = Get-HashString -Text $key
    return Join-Path $script:TtsCacheDir ($hash + '.wav')
}

function Get-ApiKey {
    param($Config)
    if (-not $Config.tts -or -not $Config.tts.apiKey) {
        throw 'config.json must contain tts.apiKey'
    }
    return [string]$Config.tts.apiKey
}

function Invoke-TtsToWav {
    param(
        [string]$Text,
        [string]$OutFile,
        [string]$Voice,
        [double]$Speed,
        $Config
    )

    $cacheFile = Get-TtsCacheFile -Text $Text -Voice $Voice -Speed $Speed -Config $Config
    if (Test-Path $cacheFile) {
        Copy-Item -Path $cacheFile -Destination $OutFile
        return
    }

    $apiKey = Get-ApiKey -Config $Config
    $tmpMp3 = [System.IO.Path]::ChangeExtension($OutFile, '.tmp.mp3')
    if (Test-Path $tmpMp3) { Remove-Item $tmpMp3 -Force -ErrorAction SilentlyContinue }

    $tmpText = [System.IO.Path]::ChangeExtension($OutFile, '.tmp.txt')
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmpText, [string]$Text, $utf8NoBom)
    
    & $config.tools.curlPath --http1.1 -sS `
      --retry 4 --retry-all-errors --retry-delay 2 `
      --connect-timeout 20 --max-time 120 `
      -X POST $Config.tts.endpoint `
      -H "Authorization: Api-Key $apiKey" `
      -H "Content-Type: application/x-www-form-urlencoded" `
      --data-urlencode "text@$tmpText"`
      --data-urlencode "lang=ru-RU" `
      --data-urlencode "voice=$Voice" `
      --data-urlencode ("speed=" + [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.##}', $Speed)) `
      --data-urlencode "format=$($Config.tts.format)" `
      -o $tmpMp3

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpMp3)) {
        throw "TTS request failed: $Text"
    }

    & ffmpeg -hide_banner -loglevel error -y -i $tmpMp3 -ar 48000 -ac 1 -c:a pcm_s16le $OutFile 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg conversion failed: $Text"
    }

    Copy-Item -Path $OutFile -Destination $cacheFile
    Remove-Item $tmpMp3 -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpText -Force -ErrorAction SilentlyContinue
}

function Get-SilenceCacheFile {
    param([int]$DurationMs)
    return Join-Path $script:SilenceCacheDir ("silence_" + $DurationMs + '.wav')
}

function New-SilenceWav {
    param(
        [int]$DurationMs,
        [string]$OutFile
    )

    $cacheFile = Get-SilenceCacheFile -DurationMs $DurationMs
    if (Test-Path $cacheFile) {
        Copy-Item -Path $cacheFile -Destination $OutFile
        return
    }

    $seconds = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.###}', ($DurationMs / 1000.0))
    & ffmpeg -hide_banner -loglevel error -y -f lavfi -i anullsrc=r=48000:cl=mono -t $seconds -c:a pcm_s16le $OutFile 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed to generate silence: $OutFile"
    }

    Copy-Item -Path $OutFile -Destination $cacheFile
}

function Merge-WavPartsToMp3 {
    param(
        [string[]]$Parts,
        [string]$OutFile,
        [string]$TempDir
    )

    $listFile = Join-Path $TempDir 'concat.txt'
    $concatLines = $Parts | ForEach-Object { "file '$($_ -replace '\\','/')'" }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($listFile, $concatLines, $utf8NoBom)

    & ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i $listFile -ar 48000 -ac 1 -c:a libmp3lame -b:a 128k $OutFile 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg concat failed for $OutFile"
    }
}

function Get-OutputMp3Path {
    param($Dictation, $Config)
    return Join-Path $Config.paths.outputSiteDir ($Dictation.Slug + '_full.mp3')
}

function Should-GenerateDictation {
    param($Dictation, $Config)

    $outputFile = Get-OutputMp3Path -Dictation $Dictation -Config $Config

    switch ($script:RunMode) {
        'force' {
            return $true
        }
        'selected' {
            return $script:SelectedSlugs.ContainsKey($Dictation.Slug.ToLowerInvariant())
        }
        default {
            return (-not (Test-Path $outputFile))
        }
    }
}

function Remove-OldPublishedAudio {
    param(
        [string]$OutputSiteDir,
        [string[]]$KeepFiles
    )

    $keepSet = @{}
    foreach ($file in $KeepFiles) { $keepSet[$file.ToLowerInvariant()] = $true }
    $keepSet['index.html'] = $true
    $keepSet['dictations.json'] = $true
    $keepSet['error.html'] = $true

    Get-ChildItem -Path $OutputSiteDir -File -Filter '*.mp3' -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $keepSet.ContainsKey($_.Name.ToLowerInvariant())) {
            Remove-Item $_.FullName -Force
        }
    }
}

function Render-DictationAudio {
    param(
        $Dictation,
        [object[]]$Plan,
        $Config
    )

    $workDir = Join-Path $Config.paths.outputTempDir $Dictation.Slug
    if (Test-Path $workDir) {
        Remove-Item $workDir -Recurse -Force
    }
    Ensure-Directory $workDir

    $parts = New-Object System.Collections.Generic.List[string]
    $index = 0
    $totalItems = $Plan.Count
    $lastLoggedPercent = -10

    foreach ($item in $Plan) {
        $index++
        $percent = [int][Math]::Floor(($index / [double]$totalItems) * 100)
        if ($percent -ge ($lastLoggedPercent + 10)) {
            $lastLoggedPercent = $percent
            Write-Log ("Progress: " + $Dictation.Slug + " " + $percent + "%")
        }

        $partFile = Join-Path $workDir ('part_{0:D4}.wav' -f $index)

        if ($item.Type -eq 'speak') {
            Invoke-TtsToWav -Text $item.Text -OutFile $partFile -Voice $Dictation.Voice -Speed $Dictation.Speed -Config $Config
        }
        elseif ($item.Type -eq 'pause') {
            New-SilenceWav -DurationMs ([int]$item.Ms) -OutFile $partFile
        }
        else {
            throw "Unknown plan item type: $($item.Type)"
        }

        $parts.Add($partFile)
    }

    $tempFinal = Join-Path $workDir ($Dictation.Slug + '_full.mp3')
    Merge-WavPartsToMp3 -Parts @($parts) -OutFile $tempFinal -TempDir $workDir

    $siteFinal = Get-OutputMp3Path -Dictation $Dictation -Config $Config
    if (Test-Path $siteFinal) {
        Remove-Item $siteFinal -Force
    }

    Move-Item -Path $tempFinal -Destination $siteFinal
    Remove-Item -Path $workDir -Recurse -Force

    return $siteFinal
}

function Build-Manifest {
    param(
        [object[]]$PublishedDictations,
        $Config
    )

    $items = @()
    foreach ($d in $PublishedDictations) {
        $audioFile = Get-OutputMp3Path -Dictation $d -Config $Config
        if (Test-Path $audioFile) {
            $items += [PSCustomObject]@{
                title = [string]$d.Title
                slug  = [string]$d.Slug
                audio = ([string]$d.Slug + '_full.mp3')
            }
        }
        else {
            Write-Log ("Skipping manifest item because file missing: " + $d.Slug) 'WARN'
        }
    }

    $manifestPath = Join-Path $Config.paths.outputSiteDir 'dictations.json'
    $items | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
}

function Build-IndexHtml {
    param($Config)

    $template = Read-TextFile -Path $Config.paths.indexTemplate
    $html = $template.Replace('{{SITE_TITLE}}', [string]$Config.site.title)
    $indexPath = Join-Path $Config.paths.outputSiteDir 'index.html'
    Set-Content -Path $indexPath -Value $html -Encoding UTF8
}

function Publish-Site {
    param($Config)

    if (-not [bool]$Config.publish.enabled) {
        Write-Log 'Publish disabled in config.'
        return
    }

    $folder = $Config.publish.syncFolder
    $bucket = $Config.publish.bucket
    $endpoint = $Config.publish.endpoint

    Write-Log "Publishing folder '$folder' to bucket '$bucket'"
    & aws s3 sync $folder "s3://$bucket" --endpoint-url $endpoint
    if ($LASTEXITCODE -ne 0) {
        throw 'aws s3 sync failed'
    }
}

function Main {
    $projectRoot = Split-Path -Parent $PSCommandPath
    $configPath = Join-Path $projectRoot 'config.json'
    $config = Load-Config -Path $configPath
    $splitMode = Get-SplitModeFromConfig -Config $config

    Initialize-ProjectFolders -Config $config -ProjectRoot $projectRoot

    try {
        Write-Log ("Run mode: " + $script:RunMode)
        Write-Log ("Split mode: " + $splitMode)
        if ($script:RunMode -eq 'selected') {
            Write-Log ("Selected slugs: " + $script:SelectedSlugsRaw)
        }

        $dictationsRaw = Read-TextFile -Path $config.paths.inputFile
        $dictations = Parse-Dictations -RawText $dictationsRaw -Config $config
        Write-Log "Loaded dictations: $($dictations.Count)"

        $overrides = @{}
        if (Test-Path $config.paths.overridesFile) {
            $overridesRaw = Read-TextFile -Path $config.paths.overridesFile
            $overrides = Parse-Overrides -RawText $overridesRaw
            Write-Log "Loaded overrides: $($overrides.Count)"
        }

        $published = New-Object System.Collections.Generic.List[object]

        foreach ($dictation in $dictations) {
            if ($dictation.Publish) {
                $published.Add($dictation)
            }

            if (-not (Should-GenerateDictation -Dictation $dictation -Config $config)) {
                Write-Log ("Skipped generation: " + $dictation.Slug)
                continue
            }

            Write-Log ("Processing: " + $dictation.Title)
            $plan = Build-DictationPlan -Dictation $dictation -Config $config -Overrides $overrides -SplitMode $splitMode
            $siteFile = Render-DictationAudio -Dictation $dictation -Plan $plan -Config $config
            Write-Log ("Generated: " + $siteFile)
        }

        $publishedArray = $published.ToArray()
        Remove-OldPublishedAudio -OutputSiteDir $config.paths.outputSiteDir -KeepFiles (@($publishedArray | ForEach-Object { $_.Slug + '_full.mp3' }))
        Build-Manifest -PublishedDictations $publishedArray -Config $config
        Build-IndexHtml -Config $config
        Publish-Site -Config $config

        Write-Log 'Done.'
    }
    catch {
        Write-Log $_.Exception.Message 'ERROR'
        if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
            Write-Log $_.InvocationInfo.PositionMessage 'ERROR'
        }
        throw
    }
}

Main
