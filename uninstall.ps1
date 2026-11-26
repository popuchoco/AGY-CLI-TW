param(
    [string]$HomeDirectory = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'
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

$state = $null
if (Test-Path -LiteralPath $statePath) {
    try { $state = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($statePath)) -ErrorAction Stop }
    catch { throw "JSON 格式錯誤：$statePath。$($_.Exception.Message)" }
    if ($null -eq $state -or $state -is [Array] -or $state -is [string] -or $state -is [ValueType]) { throw "JSON 根節點必須是物件：$statePath" }
}

$settings = $null
if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    $settingsText = [IO.File]::ReadAllText($settingsPath)
    if ($settingsText.Trim()) {
        try { $settings = ConvertFrom-Json -InputObject $settingsText -ErrorAction Stop }
        catch { throw "JSON 格式錯誤：$settingsPath。$($_.Exception.Message)" }
        if ($null -eq $settings -or $settings -is [Array] -or $settings -is [string] -or $settings -is [ValueType]) { throw "JSON 根節點必須是物件：$settingsPath" }
    } else { $settings = [pscustomobject]@{} }
}

if (Test-Path -LiteralPath $agentsPath) {
    $agentsText = [IO.File]::ReadAllText($agentsPath)
    $startIndex = $agentsText.IndexOf($beginMarker, [StringComparison]::Ordinal)
    $endIndex = $agentsText.IndexOf($endMarker, [StringComparison]::Ordinal)
    if ($startIndex -ge 0 -and $endIndex -ge $startIndex) {
        $endIndex += $endMarker.Length
        $remaining = $agentsText.Substring(0, $startIndex) + $agentsText.Substring($endIndex)
        if ($remaining.Trim().Length -eq 0 -and $state -and $state.agentsFileExisted -eq $false) {
            Remove-Item -LiteralPath $agentsPath -Force
        } else {
            [IO.File]::WriteAllText($agentsPath, $remaining, (New-Object System.Text.UTF8Encoding($false)))
        }
    }
}

if ((Test-Path -LiteralPath $settingsPath -PathType Leaf) -and $state -and $settings) {
    $currentStatusLine = $settings.PSObject.Properties['statusLine']
    if ($null -ne $currentStatusLine -and [string]$currentStatusLine.Value.command -eq [string]$state.managedCommand) {
        $settings.PSObject.Properties.Remove('statusLine')
        if ($state.originalStatusLinePresent) {
            $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $state.originalStatusLine -Force
        }
        [IO.File]::WriteAllText($settingsPath, (ConvertTo-Json -InputObject $settings -Depth 50), (New-Object System.Text.UTF8Encoding($false)))
    } else {
        Write-Warning '目前的 statusLine 與本套件安裝值不同；保留目前設定。'
    }
}

Remove-Item -LiteralPath $statuslinePath, $skillPath, $statePath -Force -ErrorAction SilentlyContinue
if ((Test-Path -LiteralPath $skillDir) -and -not (Get-ChildItem -LiteralPath $skillDir -Force | Select-Object -First 1)) {
    Remove-Item -LiteralPath $skillDir -Force
}
Write-Host '已移除 Antigravity CLI 台灣繁體中文增補包。'
