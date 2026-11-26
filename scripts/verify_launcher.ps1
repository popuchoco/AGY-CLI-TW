$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$launcher = Get-Content -Raw (Join-Path $repo 'launcher\windows\agy-tw.ps1')
$match = [regex]::Match($launcher, "(?s)\`$source\s*=\s*@'\r?\n(.*?)\r?\n'@")
if (-not $match.Success) { throw 'Could not find the launcher C# source block.' }
if ($null -eq ('AgyPtyProxy' -as [type])) {
    Add-Type -TypeDefinition $match.Groups[1].Value -Language CSharp
}
$conPtyIssue = [AgyPtyProxy]::ProbeConPty()
if ($conPtyIssue) { Write-Host "INFO: ConPTY unavailable; launcher will direct users to path A. $conPtyIssue" }

$cases = @(
    @('Add a directory to the workspace', '將目錄加入工作區'),
    @('List available custom agents', '列出可用的自訂代理'),
    @('View and review artifacts', '檢視與審閱產物'),
    @('Ask a side question without interrupting the current task', '在不中斷目前工作的情況下提出旁支問題'),
    @('Show release notes and changes', '顯示版本資訊與變更'),
    @('Clear conversation and start a new one', '清除對話並開始新對話'),
    @('Search code in the workspace (usage: /codesearch <query>)', '搜尋工作區程式碼'),
    @('Open settings panel', '開啟設定面板'),
    @('Visualize current context usage', '顯示目前上下文用量'),
    @("Copy the last planner response to the clipboard, the n-th with '/copy n', or the /btw answer with '/copy btw'", '複製最後一則規劃回覆'),
    @('Show remaining G1 credits and purchase link', '顯示剩餘 G1 點數與購買連結'),
    @('View uncommitted changes and per-turn diffs', '檢視未提交的變更與各回合差異'),
    @('Set the reasoning effort', '設定推理強度'),
    @('Exit the CLI', '離開 CLI'),
    @('Submit qualitative feedback to improve the agent', '提交意見回饋以協助改善代理'),
    @('Create a branch of the current conversation at this point, optionally specifying a project ID to fork into', '在此處為目前對話建立分支'),
    @('Show available commands and keybindings', '顯示可用指令與按鍵對應'),
    @('Manage hook configurations for tool events', '管理工具事件的 Hook 設定'),
    @('Set custom keybindings', '設定自訂按鍵對應'),
    @('Log out', '登出'),
    @('Manage MCP servers', '管理 MCP 伺服器'),
    @('Set a model, or run a single prompt on another model', '設定模型'),
    @('Open a file or view opened/edited files', '開啟檔案或檢視已開啟／編輯的檔案'),
    @('Manage tool permissions', '管理工具權限'),
    @('Manage, discover, install, uninstall, enable, and disable plugins', '管理、探索、安裝、解除安裝、啟用與停用外掛'),
    @('Create and edit projects', '建立與編輯專案'),
    @('Dictate a prompt using your microphone', '使用麥克風聽寫提示'),
    @('Turn on remote control for this session (off to disable)', '啟用此工作階段的遠端控制'),
    @('Rename the current conversation', '重新命名目前對話'),
    @('Browse and resume past conversations', '瀏覽並繼續過往對話'),
    @('Rewind conversation to a previous message', '將對話倒回先前訊息'),
    @('List available skills', '列出可用技能'),
    @('Toggle the statusline', '切換狀態列'),
    @('View background tasks', '檢視背景工作'),
    @("Toggle streaming the model's full thinking in the transcript", '切換是否在逐字稿中串流顯示模型完整思考過程'),
    @('Toggle custom terminal window title', '切換自訂終端視窗標題'),
    @('View model quota usage', '檢視模型配額用量'),
    @('Dictate a prompt or talk with the agent by voice', '使用語音聽寫提示或與代理對話'),
    @('Run until the specified goal is completely finished.', '持續執行，直到指定目標完成。'),
    @('Compact the conversation now (summarize history to free up the context window).', '立即壓縮對話'),
    @('Run an instruction on a recurring schedule or as a one-time timer.', '依週期排程或單次計時器執行指令。'),
    @('Invoke a browser agent for web tasks.', '呼叫瀏覽器代理處理網頁工作。'),
    @('Plan carefully before executing a task.', '執行前仔細規劃。'),
    @('Interview me to align on a plan.', '訪談我以對齊計畫。'),
    @('Reflect on recent successes or corrections to capture reusable skills or rules.', '回顧近期成功經驗或修正'),
    @('Comprehensive guide and reference for the Antigravity Customization System.', 'Antigravity 自訂系統完整指南與參考資料。'),
    @('Provides a comprehensive guide, quick reference, and sitemap for Google Antigravity (AGY), including the Antigravity CLI (agy), Antigravity 2.0, Antigravity IDE, Python SDK, slash commands, keybindings, and customizations (skills, rules, MCP, sidecars). Activate this skill when the user asks questions about how to use, configure, or customize Antigravity, AGY, the agy CLI, the Antigravity IDE, or Antigravity 2.0.', '提供 Google Antigravity（AGY）完整指南'),
    @('How to write and run a dynamic workflow script with the `run_workflow` tool:', '如何使用 `run_workflow` 工具撰寫並執行動態工作流程指令碼：'),
    @('(Preview & Quota Heavy) Run a swarm: several agents working in parallel on', '（預覽／配額消耗較高）執行 Swarm 多代理並行工作…')
)

$shortcuts = @(
    @('Open slash commands', '開啟斜線指令'),
    @('Insert newline fallback', '插入換行（替代方式）'),
    @('Manage subagent', '管理子代理'),
    @('Send with opposite Queued Messages setting', '依相反的「佇列訊息」設定傳送'),
    @('Paste image/video', '貼上圖片／影片'),
    @('Undo', '復原'),
    @('Go back / dismiss', '返回／關閉'),
    @('Exit', '離開'),
    @('Go to bottom', '移至底部'),
    @('Open prompt in $EDITOR', '在 $EDITOR 中開啟提示'),
    @('Go to top', '移至頂端'),
    @('Approve subagent fast', '快速核准子代理'),
    @('Clear CLI screen', '清除 CLI 畫面'),
    @('Toggle trajectory view', '切換軌跡檢視'),
    @('Review artifact', '檢視成品'),
    @('Redo', '重做'),
    @('Yank (paste from kill ring)', '從剪貼環貼上'),
    @('Insert newline', '插入換行'),
    @('Suspend CLI', '暫停 CLI'),
    @('Send message or confirm', '傳送訊息或確認'),
    @('Rename', '重新命名'),
    @('Delete', '刪除'),
    @('Start voice dictation', '開始語音聽寫'),
    @('Half page down', '向下半頁'),
    @('Cycle mode', '切換模式'),
    @('Half page up', '向上半頁'),
    @('Select and copy text', '選取並複製文字')
)

$translatorType = [AgyPtyProxy].GetNestedType('VtTranslator', [Reflection.BindingFlags]'NonPublic')
$stream = [IO.MemoryStream]::new()
$translator = [Activator]::CreateInstance($translatorType, [Reflection.BindingFlags]'Instance,Public,NonPublic', $null, [object[]]@($stream), $null)
$sourceLines = @($cases | ForEach-Object { $_[0] }) + @($shortcuts | ForEach-Object { $_[0] }) + @(
    'Type / to see available commands',
    'Keyboard: ↑/↓ Navigate · ←/→ Switch View esc Close',
    'C:\Users\Example\workspace'
)
$input = (($sourceLines -join "`n") + "`n").ToCharArray()
$translatorType.GetMethod('Process').Invoke($translator, @($input, $input.Length))
$output = [Text.Encoding]::UTF8.GetString($stream.ToArray())

foreach ($case in @($cases) + @($shortcuts)) {
    if (-not $output.Contains($case[1])) {
        throw "Missing translation for '$($case[0])'; expected '$($case[1])'.`n$output"
    }
}
foreach ($expected in @('輸入 / 查看可用指令', '鍵盤：↑/↓ 導覽 · ←/→ 切換檢視 esc 關閉', 'C:\Users\Example\workspace')) {
    if (-not $output.Contains($expected)) { throw "Missing expected UI output: $expected`n$output" }
}

Write-Host 'PASS: launcher maps all 49 command descriptions, 27 shortcut descriptions, and UI footer samples.'
