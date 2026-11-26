$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tempHome = Join-Path ([IO.Path]::GetTempPath()) ('agy cli tw test-' + [Guid]::NewGuid().ToString('N'))
try {
    $configDir = Join-Path $tempHome '.gemini\config'
    $cliDir = Join-Path $tempHome '.gemini\antigravity-cli'
    New-Item -ItemType Directory -Force -Path $configDir, $cliDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $configDir 'AGENTS.md'), "# Existing preference`r`nUse concise explanations.`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $initial = [pscustomobject]@{ colorScheme = 'dark'; statusLine = [pscustomobject]@{ type = 'command'; command = 'old-statusline' } }
    [IO.File]::WriteAllText((Join-Path $cliDir 'settings.json'), (ConvertTo-Json $initial -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

    & (Join-Path $repo 'install.ps1') -HomeDirectory $tempHome | Out-Null
    $settingsPath = Join-Path $cliDir 'settings.json'
    $settings = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($settingsPath))
    if ($settings.colorScheme -ne 'dark') { throw 'Existing settings were not preserved.' }
    if ($settings.statusLine.command -notmatch 'statusline-tw\.ps1') { throw 'Localized statusline was not configured.' }
    $agentsPath = Join-Path $configDir 'AGENTS.md'
    $agents = [IO.File]::ReadAllText($agentsPath)
    if (($agents.Split('<!-- BEGIN AGY-CLI-TW -->').Count - 1) -ne 1) { throw 'Global rule marker should occur exactly once.' }
    if (-not (Test-Path (Join-Path $cliDir 'skills\zh-tw\SKILL.md'))) { throw 'Skill was not installed.' }

    $payload = '{"agent_state":"thinking","context_window":{"used_percentage":12.4},"vcs":{"branch":"main","dirty":true},"sandbox":{"enabled":true},"artifact_count":1,"subagents":[{}],"task_count":2,"model":{"display_name":"Gemini 4 Argon"},"terminal_width":120}'
    $powershellExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if (-not $powershellExe) { $powershellExe = (Get-Command pwsh.exe -ErrorAction Stop).Source }
    $status = $payload | & $powershellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $cliDir 'statusline-tw.ps1') | Out-String
    if ($status -notmatch '思考中' -or $status -notmatch 'Gemini 4 Argon' -or $status -notmatch '12\.4%' -or $status -notmatch '代理：1') { throw "Unexpected statusline output: $status" }
    $statusViaCmd = $payload | & $env:ComSpec /d /s /c $settings.statusLine.command | Out-String
    if ($statusViaCmd -notmatch '思考中' -or $statusViaCmd -notmatch 'Gemini 4 Argon') { throw "statusLine command could not run through cmd.exe: $statusViaCmd" }

    & (Join-Path $repo 'install.ps1') -HomeDirectory $tempHome | Out-Null
    $agentsAfterRepeat = [IO.File]::ReadAllText($agentsPath)
    if (($agentsAfterRepeat.Split('<!-- BEGIN AGY-CLI-TW -->').Count - 1) -ne 1) { throw 'Repeated install duplicated the global rule.' }

    & (Join-Path $repo 'uninstall.ps1') -HomeDirectory $tempHome | Out-Null
    $restored = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($settingsPath))
    if ($restored.colorScheme -ne 'dark' -or $restored.statusLine.command -ne 'old-statusline') { throw 'Original settings were not restored.' }
    $agentsAfterRemove = [IO.File]::ReadAllText($agentsPath)
    if ($agentsAfterRemove -notmatch 'Use concise explanations\.' -or $agentsAfterRemove -match 'BEGIN AGY-CLI-TW') { throw 'Global rule cleanup was incorrect.' }
    if (Test-Path (Join-Path $cliDir 'skills\zh-tw\SKILL.md')) { throw 'Skill was not removed.' }

    Write-Host 'PASS: statusline translation, install, repeat install, settings restore, and uninstall.'
} finally {
    if (Test-Path -LiteralPath $tempHome) { Remove-Item -LiteralPath $tempHome -Recurse -Force }
}
