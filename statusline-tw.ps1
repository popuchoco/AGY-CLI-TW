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
$subagentsItems = @(Get-Value $data 'subagents' @())
$subagents = $subagentsItems.Count
$width = [int](Get-Value $data 'terminal_width' 100)
try { if ([Console]::WindowWidth -gt 0) { $width = [Console]::WindowWidth } } catch {}

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

if ($width -ge 112) {
    $parts = @($statePart, $modelPart, $branchPart, $usagePart, $workPart, "成品：$artifacts", $sandboxPart) | Where-Object { $_ }
    [Console]::WriteLine(($parts -join '  │  '))
} elseif ($width -ge 78) {
    $line1 = @($statePart, $modelPart, $branchPart) | Where-Object { $_ }
    $line2 = @($usagePart, $workPart, "成品：$artifacts", $sandboxPart) | Where-Object { $_ }
    [Console]::WriteLine(($line1 -join '  │  '))
    [Console]::WriteLine(($line2 -join '  │  '))
} else {
    [Console]::WriteLine("$statePart  │  $usagePart")
    [Console]::WriteLine("代理：$subagents  工作：$tasks  │  沙箱：$sandboxText")
}
