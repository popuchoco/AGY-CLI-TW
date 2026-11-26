param(
    [string]$HomeDirectory = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'

function Read-JsonObject([string]$Path, [bool]$MissingIsNull = $false) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if (Test-Path -LiteralPath $Path) { throw "預期是檔案，但找到其他項目：$Path" }
        if ($MissingIsNull) { return $null }
        return [pscustomobject]@{}
    }
    $text = [IO.File]::ReadAllText($Path)
    if (-not $text.Trim()) { return [pscustomobject]@{} }
    try { $value = ConvertFrom-Json -InputObject $text -ErrorAction Stop }
    catch { throw "JSON 格式錯誤：$Path。$($_.Exception.Message)" }
    if ($null -eq $value -or $value -is [Array] -or $value -is [string] -or $value -is [ValueType]) {
        throw "JSON 根節點必須是物件：$Path"
    }
    return $value
}

function Test-WritableDirectory([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $probe = Join-Path $Path ('.agy-cli-tw-write-test-' + [Guid]::NewGuid().ToString('N'))
    try {
        $stream = [IO.File]::Open($probe, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
    } finally {
        if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force }
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($HomeDirectory)) { throw '找不到使用者家目錄。請使用 -HomeDirectory 指定。' }

    $repoRoot = $PSScriptRoot
    $agentsSource = Join-Path (Join-Path $repoRoot 'resources') 'AGENTS.zh-TW.md'
    $statuslineSource = Join-Path $repoRoot 'statusline-tw.ps1'
    $skillSource = Join-Path (Join-Path (Join-Path $repoRoot 'skills') 'zh-tw') 'SKILL.md'
    foreach ($source in @($agentsSource, $statuslineSource, $skillSource)) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "缺少必要套件檔案：$source" }
    }
    $block = [IO.File]::ReadAllText($agentsSource).Trim()
    $skillText = [IO.File]::ReadAllText($skillSource)
    $statuslineText = [IO.File]::ReadAllText($statuslineSource)

    $beginMarker = '<!-- BEGIN AGY-CLI-TW -->'
    $endMarker = '<!-- END AGY-CLI-TW -->'
    $geminiDir = Join-Path $HomeDirectory '.gemini'
    $configDir = Join-Path $geminiDir 'config'
    $cliDir = Join-Path $geminiDir 'antigravity-cli'
    $agentsPath = Join-Path $configDir 'AGENTS.md'
    $settingsPath = Join-Path $cliDir 'settings.json'
    $statePath = Join-Path $cliDir '.agy-cli-tw-state.json'
    $statuslinePath = Join-Path $cliDir 'statusline-tw.ps1'
    $skillRoot = Join-Path $cliDir 'skills'
    $skillDir = Join-Path $skillRoot 'zh-tw'
    $skillPath = Join-Path $skillDir 'SKILL.md'

    # Parse and validate all existing JSON before changing any user files.
    $settings = Read-JsonObject $settingsPath
    $state = Read-JsonObject $statePath -MissingIsNull $true
    $settingsHadStatusLine = $null -ne $settings.PSObject.Properties['statusLine']
    $statusLineProperty = $settings.PSObject.Properties['statusLine']
    $currentStatusLine = if ($statusLineProperty) { $statusLineProperty.Value } else { $null }
    $currentCommand = ''
    if ($null -ne $currentStatusLine -and $null -ne $currentStatusLine.PSObject.Properties['command']) {
        $currentCommand = [string]$currentStatusLine.command
    }

    Test-WritableDirectory $configDir
    Test-WritableDirectory $cliDir
    Test-WritableDirectory $skillDir

    $pathsToSnapshot = @($agentsPath, $settingsPath, $statePath, $statuslinePath, $skillPath)
    $snapshots = @{}
    foreach ($path in $pathsToSnapshot) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $snapshots[$path] = [IO.File]::ReadAllBytes($path)
        } else {
            $snapshots[$path] = $null
        }
    }

    try {
        $agentsExisted = $null -ne $snapshots[$agentsPath]
        $agentsText = if ($agentsExisted) { [Text.Encoding]::UTF8.GetString($snapshots[$agentsPath]) } else { '' }
        $startIndex = $agentsText.IndexOf($beginMarker, [StringComparison]::Ordinal)
        $endIndex = $agentsText.IndexOf($endMarker, [StringComparison]::Ordinal)
        if ($startIndex -ge 0 -and $endIndex -ge $startIndex) {
            $endIndex += $endMarker.Length
            $agentsText = $agentsText.Substring(0, $startIndex) + $block + $agentsText.Substring($endIndex)
        } else {
            if ($agentsText.Length -gt 0 -and -not $agentsText.EndsWith("`n")) { $agentsText += "`r`n" }
            $agentsText += "`r`n$block`r`n"
        }
        [IO.File]::WriteAllText($agentsPath, $agentsText, (New-Object System.Text.UTF8Encoding($false)))
        # Windows PowerShell 5.1 needs a UTF-8 BOM to parse Traditional Chinese literals.
        [IO.File]::WriteAllText($statuslinePath, $statuslineText, (New-Object System.Text.UTF8Encoding($true)))
        [IO.File]::WriteAllText($skillPath, $skillText, (New-Object System.Text.UTF8Encoding($false)))

        $command = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $statuslinePath + '"'
        if ($null -eq $state) {
            $state = [pscustomobject]@{
                schemaVersion = 1
                agentsFileExisted = $agentsExisted
                originalStatusLinePresent = $settingsHadStatusLine
                originalStatusLine = $currentStatusLine
                managedCommand = $command
            }
        } elseif ($settingsHadStatusLine -and $currentCommand -ne [string]$state.managedCommand) {
            Write-Warning '偵測到安裝後另行變更的 statusLine；保留目前設定，請手動設定繁體中文狀態列。'
            $command = $null
        }

        if ($command) {
            $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue ([pscustomobject]@{ type = 'command'; command = $command }) -Force
        }
        [IO.File]::WriteAllText($statePath, (ConvertTo-Json -InputObject $state -Depth 50), (New-Object System.Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($settingsPath, (ConvertTo-Json -InputObject $settings -Depth 50), (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        $writeError = $_
        foreach ($path in $pathsToSnapshot) {
            try {
                if ($null -eq $snapshots[$path]) {
                    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
                } else {
                    [IO.File]::WriteAllBytes($path, [byte[]]$snapshots[$path])
                }
            } catch { Write-Warning "回復檔案時發生錯誤：$path。$($_.Exception.Message)" }
        }
        throw $writeError
    }

    Write-Host '已安裝 Antigravity CLI 台灣繁體中文增補包。'
    Write-Host "全域規則：$agentsPath"
    Write-Host "狀態列設定：$settingsPath"
    Write-Host '請重新啟動 agy 以載入設定。'
} catch {
    [Console]::Error.WriteLine("安裝失敗：$($_.Exception.Message)")
    throw
}
