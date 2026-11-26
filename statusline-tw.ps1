param()

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

function Get-Value($Object, [string]$Path, $Default) {
    $value = $Object
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $value) { return $Default }
        $property = $value.PSObject.Properties[$part]
        if ($null -eq $property) { return $Default }
        $value = $property.Value
    }
    if ($null -eq $value) { return $Default }
    return $value
}

function Get-CodePointDisplayWidth([int]$CodePoint) {
    if (($CodePoint -ge 0x1100 -and $CodePoint -le 0x115F) -or
        $CodePoint -eq 0x2329 -or $CodePoint -eq 0x232A -or
        ($CodePoint -ge 0x2E80 -and $CodePoint -le 0xA4CF) -or
        ($CodePoint -ge 0xAC00 -and $CodePoint -le 0xD7A3) -or
        ($CodePoint -ge 0xF900 -and $CodePoint -le 0xFAFF) -or
        ($CodePoint -ge 0xFE10 -and $CodePoint -le 0xFE19) -or
        ($CodePoint -ge 0xFE30 -and $CodePoint -le 0xFE6F) -or
        ($CodePoint -ge 0xFF00 -and $CodePoint -le 0xFF60) -or
        ($CodePoint -ge 0xFFE0 -and $CodePoint -le 0xFFE6) -or
        ($CodePoint -ge 0x1F300 -and $CodePoint -le 0x1FAFF) -or
        ($CodePoint -ge 0x20000 -and $CodePoint -le 0x3FFFD)) { return 2 }
    return 1
}

function Get-DisplayWidth([string]$Text) {
    $cells = 0
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $codePoint = [char]::ConvertToUtf32($Text, $index)
        if ($codePoint -gt 0xFFFF) { $index++ }
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($Text, [Math]::Max(0, $index - $(if ($codePoint -gt 0xFFFF) { 1 } else { 0 })))
        if ($category -in @([Globalization.UnicodeCategory]::NonSpacingMark, [Globalization.UnicodeCategory]::EnclosingMark, [Globalization.UnicodeCategory]::Format, [Globalization.UnicodeCategory]::Control)) { continue }
        $cells += Get-CodePointDisplayWidth $codePoint
    }
    return $cells
}

function Limit-DisplayWidth([string]$Text, [int]$Limit) {
    if ($Limit -le 0) { return '' }
    if ((Get-DisplayWidth $Text) -le $Limit) { return $Text }
    $suffix = '…'
    $budget = [Math]::Max(0, $Limit - 1)
    $cells = 0
    $result = New-Object System.Text.StringBuilder
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $codePoint = [char]::ConvertToUtf32($Text, $index)
        if ($codePoint -gt 0xFFFF) { $index++ }
        $categoryIndex = $index - $(if ($codePoint -gt 0xFFFF) { 1 } else { 0 })
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($Text, $categoryIndex)
        $charWidth = if ($category -in @([Globalization.UnicodeCategory]::NonSpacingMark, [Globalization.UnicodeCategory]::EnclosingMark, [Globalization.UnicodeCategory]::Format, [Globalization.UnicodeCategory]::Control)) { 0 } else { Get-CodePointDisplayWidth $codePoint }
        if ($cells + $charWidth -gt $budget) { break }
        [void]$result.Append([char]::ConvertFromUtf32($codePoint))
        $cells += $charWidth
    }
    return $result.ToString() + $suffix
}

function Format-StatusLines([string[]]$Fields, [int]$Width) {
    $separator = '  │  '
    $limit = [Math]::Max(1, $Width)
    $lines = New-Object System.Collections.Generic.List[string]
    $current = ''
    foreach ($field in $Fields) {
        if ([string]::IsNullOrEmpty($field)) { continue }
        $field = Limit-DisplayWidth $field $limit
        $candidate = if ($current) { $current + $separator + $field } else { $field }
        if ($current -and (Get-DisplayWidth $candidate) -gt $limit) {
            $lines.Add($current)
            $current = $field
        } else { $current = $candidate }
    }
    if ($current) { $lines.Add($current) }
    foreach ($line in $lines) { [Console]::WriteLine($line) }
}

try {
    $raw = [Console]::In.ReadToEnd()
    $data = ConvertFrom-Json -InputObject $raw
} catch {
    [Console]::WriteLine('Antigravity CLI 狀態列：等待工作階段資料')
    exit 0
}

$state = [string](Get-Value $data 'agent_state' 'idle')
$stateLabels = @{
    initializing = '初始化中'
    idle = '準備就緒'
    thinking = '思考中'
    working = '執行中'
    tool_use = '呼叫工具中'
    reviewing = '等待審查'
    approval = '等待核准'
}
if ($stateLabels.ContainsKey($state)) { $stateText = $stateLabels[$state] } else { $stateText = $state }

$model = [string](Get-Value $data 'model.display_name' '')
$branch = [string](Get-Value $data 'vcs.branch' '')
$dirty = [bool](Get-Value $data 'vcs.dirty' $false)
$sandbox = [bool](Get-Value $data 'sandbox.enabled' $false)
$sandboxText = if ($sandbox) { '開啟' } else { '關閉' }
$artifacts = [int](Get-Value $data 'artifact_count' 0)
$tasks = [int](Get-Value $data 'task_count' 0)
$subagentsProperty = $data.PSObject.Properties['subagents']
$subagentsValue = $null
if ($null -ne $subagentsProperty) { $subagentsValue = $subagentsProperty.Value }
$subagents = if ($subagentsValue -is [System.Collections.IList]) { $subagentsValue.Count } else { 0 }
$widthValue = Get-Value $data 'terminal_width' $null
if ($null -ne $widthValue) {
    try { $width = [int]$widthValue } catch { $width = 100 }
} else {
    $width = 100
    try { if ([Console]::WindowWidth -gt 0) { $width = [Console]::WindowWidth } } catch {}
}

$percentage = 0.0
try { $percentage = [double](Get-Value $data 'context_window.used_percentage' 0) } catch {}
$percentage = [Math]::Max(0.0, [Math]::Min(100.0, $percentage))
$percentageText = $percentage.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) + '%'

$statePart = "狀態：$stateText"
$modelPart = if ($model) { "模型：$model" } else { '' }
$branchText = if ($branch) { if ($dirty) { "$branch*" } else { $branch } } else { '' }
$branchPart = if ($branchText) { "分支：$branchText" } else { '' }
$usagePart = "上下文：$percentageText"
$workPart = "代理：$subagents  工作：$tasks"
$sandboxPart = "沙箱：$sandboxText"

$fields = @($statePart, $modelPart, $branchPart, $usagePart, $workPart, "成品：$artifacts", $sandboxPart)
Format-StatusLines $fields $width
