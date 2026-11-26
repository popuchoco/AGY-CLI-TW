$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tempHome = Join-Path ([IO.Path]::GetTempPath()) ('agy cli tw test-' + [Guid]::NewGuid().ToString('N'))

function Get-TestDisplayWidth([string]$Text) {
    $cells = 0
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $codePoint = [char]::ConvertToUtf32($Text, $index)
        if ($codePoint -gt 0xFFFF) { $index++ }
        $categoryIndex = $index - $(if ($codePoint -gt 0xFFFF) { 1 } else { 0 })
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($Text, $categoryIndex)
        if ($category -in @([Globalization.UnicodeCategory]::NonSpacingMark, [Globalization.UnicodeCategory]::EnclosingMark, [Globalization.UnicodeCategory]::Format, [Globalization.UnicodeCategory]::Control)) { continue }
        $wide = (($codePoint -ge 0x1100 -and $codePoint -le 0x115F) -or $codePoint -eq 0x2329 -or $codePoint -eq 0x232A -or ($codePoint -ge 0x2E80 -and $codePoint -le 0xA4CF) -or ($codePoint -ge 0xAC00 -and $codePoint -le 0xD7A3) -or ($codePoint -ge 0xF900 -and $codePoint -le 0xFAFF) -or ($codePoint -ge 0xFE10 -and $codePoint -le 0xFE19) -or ($codePoint -ge 0xFE30 -and $codePoint -le 0xFE6F) -or ($codePoint -ge 0xFF00 -and $codePoint -le 0xFF60) -or ($codePoint -ge 0xFFE0 -and $codePoint -le 0xFFE6) -or ($codePoint -ge 0x1F300 -and $codePoint -le 0x1FAFF) -or ($codePoint -ge 0x20000 -and $codePoint -le 0x3FFFD))
        $cells += if ($wide) { 2 } else { 1 }
    }
    return $cells
}
try {
    $configDir = Join-Path $tempHome '.gemini\config'
    $cliDir = Join-Path $tempHome '.gemini\antigravity-cli'
    New-Item -ItemType Directory -Force -Path $configDir, $cliDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $configDir 'AGENTS.md'), "# Existing preference`r`nUse concise explanations.`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $initial = [pscustomobject]@{ colorScheme = 'dark'; statusLine = [pscustomobject]@{ type = 'command'; command = 'old-statusline' } }
    [IO.File]::WriteAllText((Join-Path $cliDir 'settings.json'), (ConvertTo-Json $initial -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

    & (Join-Path $repo 'install.ps1') -HomeDirectory $tempHome | Out-Null
    $settingsPath = Join-Path $cliDir 'settings.json'
    $skillPath = Join-Path (Join-Path (Join-Path $cliDir 'skills') 'zh-tw') 'SKILL.md'
    $settings = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($settingsPath))
    if ($settings.colorScheme -ne 'dark') { throw 'Existing settings were not preserved.' }
    if ($settings.statusLine.command -notmatch 'statusline-tw\.ps1') { throw 'Localized statusline was not configured.' }
    $agentsPath = Join-Path $configDir 'AGENTS.md'
    $agents = [IO.File]::ReadAllText($agentsPath)
    if (($agents.Split('<!-- BEGIN AGY-CLI-TW -->').Count - 1) -ne 1) { throw 'Global rule marker should occur exactly once.' }
    if (-not (Test-Path -LiteralPath $skillPath)) { throw 'Skill was not installed.' }

    $payload = '{"agent_state":"thinking","context_window":{"used_percentage":12.4},"vcs":{"branch":"main","dirty":true},"sandbox":{"enabled":true},"artifact_count":1,"subagents":[{}],"task_count":2,"model":{"display_name":"Gemini 4 Argon"},"terminal_width":120}'
    $powershellExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if (-not $powershellExe) { $powershellExe = (Get-Command pwsh.exe -ErrorAction Stop).Source }
    $invalidHome = Join-Path $tempHome 'invalid-json'
    $invalidCliDir = Join-Path $invalidHome '.gemini\antigravity-cli'
    $invalidConfigDir = Join-Path $invalidHome '.gemini\config'
    New-Item -ItemType Directory -Force -Path $invalidCliDir, $invalidConfigDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $invalidCliDir 'settings.json'), '{ invalid json', (New-Object System.Text.UTF8Encoding($false)))
    $invalidOutput = & $powershellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'install.ps1') -HomeDirectory $invalidHome 2>&1
    $invalidExitCode = $LASTEXITCODE
    if ($invalidExitCode -eq 0) { throw "Installer accepted malformed JSON: $invalidOutput" }
    if ((Test-Path (Join-Path $invalidConfigDir 'AGENTS.md')) -or (Test-Path (Join-Path $invalidCliDir 'statusline-tw.ps1'))) { throw 'Installer modified files before rejecting malformed JSON.' }
    $status = $payload | & $powershellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $cliDir 'statusline-tw.ps1') | Out-String
    if ($status -notmatch '思考中' -or $status -notmatch 'Gemini 4 Argon' -or $status -notmatch '12\.4%' -or $status -notmatch '代理：1') { throw "Unexpected statusline output: $status" }
    $statusViaCmd = $payload | & $env:ComSpec /d /s /c $settings.statusLine.command | Out-String
    if ($statusViaCmd -notmatch '思考中' -or $statusViaCmd -notmatch 'Gemini 4 Argon') { throw "statusLine command could not run through cmd.exe: $statusViaCmd" }
    $narrowPayload = '{"agent_state":"working","terminal_width":40,"model":{"display_name":"Gemini 4 Hydrogen extra-long-name"},"vcs":{"branch":"feature/long-branch-name","dirty":true},"context_window":{"used_percentage":45.2},"subagents":{"unexpected":"object"},"task_count":17,"artifact_count":8,"sandbox":{"enabled":true}}'
    $narrowStatus = $narrowPayload | & $powershellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $cliDir 'statusline-tw.ps1') | Out-String
    if (($narrowStatus -split "`r?`n").Count -lt 3 -or $narrowStatus -notmatch '代理：0') { throw "Narrow statusline layout or subagent fallback is incorrect: $narrowStatus" }
    foreach ($line in ($narrowStatus.Trim() -split "`r?`n")) {
        if ((Get-TestDisplayWidth $line) -gt 40) { throw "Statusline exceeded terminal width: $line" }
    }

    & (Join-Path $repo 'install.ps1') -HomeDirectory $tempHome | Out-Null
    $agentsAfterRepeat = [IO.File]::ReadAllText($agentsPath)
    if (($agentsAfterRepeat.Split('<!-- BEGIN AGY-CLI-TW -->').Count - 1) -ne 1) { throw 'Repeated install duplicated the global rule.' }

    & (Join-Path $repo 'uninstall.ps1') -HomeDirectory $tempHome | Out-Null
    $restored = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($settingsPath))
    if ($restored.colorScheme -ne 'dark' -or $restored.statusLine.command -ne 'old-statusline') { throw 'Original settings were not restored.' }
    $agentsAfterRemove = [IO.File]::ReadAllText($agentsPath)
    if ($agentsAfterRemove -notmatch 'Use concise explanations\.' -or $agentsAfterRemove -match 'BEGIN AGY-CLI-TW') { throw 'Global rule cleanup was incorrect.' }
    if (Test-Path -LiteralPath $skillPath) { throw 'Skill was not removed.' }

    Write-Host 'PASS: statusline translation, install, repeat install, settings restore, and uninstall.'
} finally {
    if (Test-Path -LiteralPath $tempHome) { Remove-Item -LiteralPath $tempHome -Recurse -Force }
}
