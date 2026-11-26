param(
    [string]$HomeDirectory = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'
$beginMarker = '<!-- BEGIN AGY-CLI-TW -->'
$endMarker = '<!-- END AGY-CLI-TW -->'
$repoRoot = $PSScriptRoot
$geminiDir = Join-Path $HomeDirectory '.gemini'
$configDir = Join-Path $geminiDir 'config'
$cliDir = Join-Path $geminiDir 'antigravity-cli'
$agentsPath = Join-Path $configDir 'AGENTS.md'
$settingsPath = Join-Path $cliDir 'settings.json'
$statePath = Join-Path $cliDir '.agy-cli-tw-state.json'
$statuslinePath = Join-Path $cliDir 'statusline-tw.ps1'
$skillDir = Join-Path $cliDir 'skills\zh-tw'
$skillPath = Join-Path $skillDir 'SKILL.md'

New-Item -ItemType Directory -Force -Path $configDir, $cliDir, $skillDir | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'statusline-tw.ps1') -Destination $statuslinePath -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'skills\zh-tw\SKILL.md') -Destination $skillPath -Force

$block = [IO.File]::ReadAllText((Join-Path $repoRoot 'resources\AGENTS.zh-TW.md')).Trim()
$agentsExisted = Test-Path -LiteralPath $agentsPath
$agentsText = if ($agentsExisted) { [IO.File]::ReadAllText($agentsPath) } else { '' }
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

$settings = [pscustomobject]@{}
if (Test-Path -LiteralPath $settingsPath) {
    $settingsText = [IO.File]::ReadAllText($settingsPath)
    if ($settingsText.Trim()) { $settings = ConvertFrom-Json -InputObject $settingsText }
}

$state = $null
if (Test-Path -LiteralPath $statePath) {
    $state = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($statePath))
}
$currentStatusLine = $settings.PSObject.Properties['statusLine']
$command = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $statuslinePath + '"'

if ($null -eq $state) {
    $originalPresent = $null -ne $currentStatusLine
    $originalValue = if ($originalPresent) { $currentStatusLine.Value } else { $null }
    $state = [pscustomobject]@{
        schemaVersion = 1
        agentsFileExisted = $agentsExisted
        originalStatusLinePresent = $originalPresent
        originalStatusLine = $originalValue
        managedCommand = $command
    }
} elseif ($null -ne $currentStatusLine -and [string]$currentStatusLine.Value.command -ne [string]$state.managedCommand) {
    Write-Warning '偵測到安裝後另行變更的 statusLine；保留目前設定，請手動設定繁體中文狀態列。'
    $command = $null
}

if ($command) {
    $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue ([pscustomobject]@{ type = 'command'; command = $command }) -Force
}

[IO.File]::WriteAllText($statePath, (ConvertTo-Json -InputObject $state -Depth 50), (New-Object System.Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($settingsPath, (ConvertTo-Json -InputObject $settings -Depth 50), (New-Object System.Text.UTF8Encoding($false)))
Write-Host '已安裝 Antigravity CLI 台灣繁體中文增補包。'
Write-Host "全域規則：$agentsPath"
Write-Host "狀態列設定：$settingsPath"
Write-Host '請重新啟動 agy 以載入設定。'
