param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\images\statusline-zh-tw.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$payload = '{"agent_state":"thinking","context_window":{"used_percentage":12.4},"vcs":{"branch":"main","dirty":true},"sandbox":{"enabled":true},"artifact_count":1,"subagents":[{}],"task_count":2,"model":{"display_name":"Gemini 4 Argon"},"terminal_width":120}'
$powershellExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
if (-not $powershellExe) { $powershellExe = (Get-Command pwsh.exe -ErrorAction Stop).Source }
$statusline = Join-Path (Split-Path -Parent $PSScriptRoot) 'statusline-tw.ps1'
$status = ($payload | & $powershellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $statusline | Out-String).Trim()
if ($status -notmatch '思考中' -or $status -notmatch 'Gemini 4 Argon' -or $status -notmatch '12\.4%') {
    throw "The statusline test did not produce the expected output: $status"
}

$width, $height = 1440, 470
$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

function Color([int]$r, [int]$g, [int]$b) { return [System.Drawing.Color]::FromArgb($r, $g, $b) }
function Brush([int]$r, [int]$g, [int]$b) { return New-Object System.Drawing.SolidBrush((Color $r $g $b)) }
function Font([string]$family, [float]$size, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular) {
    return New-Object System.Drawing.Font($family, $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

$background = Brush 12 17 26
$window = Brush 17 24 35
$header = Brush 23 32 45
$border = New-Object System.Drawing.Pen((Color 42 55 72), 1)
$green = Brush 82 214 151
$yellow = Brush 246 196 83
$red = Brush 243 110 108
$text = Brush 226 233 242
$muted = Brush 143 159 178
$cyan = Brush 93 211 215
$success = Brush 93 211 143
$sans = Font 'Microsoft JhengHei UI' 19
$title = Font 'Microsoft JhengHei UI' 18 ([System.Drawing.FontStyle]::Bold)
$small = Font 'Microsoft JhengHei UI' 15

$graphics.Clear((Color 12 17 26))
$graphics.FillRectangle($window, 36, 34, 1368, 402)
$graphics.DrawRectangle($border, 36, 34, 1368, 402)
$graphics.FillRectangle($header, 37, 35, 1366, 58)

$graphics.FillEllipse($red, 58, 56, 12, 12)
$graphics.FillEllipse($yellow, 80, 56, 12, 12)
$graphics.FillEllipse($green, 102, 56, 12, 12)
$graphics.DrawString('Antigravity CLI  ·  1.5.17', $title, $text, 144, 48)
$graphics.DrawString('ZH-TW STATUSLINE', (Font 'Consolas' 12 ([System.Drawing.FontStyle]::Bold)), $cyan, 1120, 53)

$graphics.DrawString('繁體中文狀態列驗證', (Font 'Microsoft JhengHei UI' 29 ([System.Drawing.FontStyle]::Bold)), $text, 78, 126)
$graphics.DrawString('透過官方 statusLine.command 注入點，不修改 CLI 執行檔', $sans, $muted, 78, 177)
$graphics.DrawLine($border, 78, 220, 1360, 220)

$graphics.DrawString('腳本輸出預覽', $small, $muted, 78, 244)
$graphics.FillRectangle((Brush 9 14 22), 78, 275, 1284, 82)
$graphics.DrawRectangle($border, 78, 275, 1284, 82)
$fitFont = Font 'Microsoft JhengHei UI' 17
while ($graphics.MeasureString($status, $fitFont).Width -gt 1244 -and $fitFont.Size -gt 13) {
    $nextSize = $fitFont.Size - 1
    $fitFont.Dispose()
    $fitFont = Font 'Microsoft JhengHei UI' $nextSize
}
$graphics.DrawString($status, $fitFont, $text, 96, 303)

$graphics.FillEllipse($success, 80, 382, 12, 12)
$graphics.DrawString('PASS', (Font 'Consolas' 14 ([System.Drawing.FontStyle]::Bold)), $success, 101, 379)
$graphics.DrawString('安裝／還原測試通過', $small, $text, 165, 378)
$graphics.DrawString('測試資料：agent_state=thinking · used_percentage=12.4 · branch=main*', (Font 'Consolas' 12), $muted, 78, 408)

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
$bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)

foreach ($item in @($background, $window, $header, $border, $green, $yellow, $red, $text, $muted, $cyan, $success, $sans, $title, $small, $bitmap, $graphics, $fitFont)) {
    if ($item -is [IDisposable]) { $item.Dispose() }
}
Write-Host "Saved preview screenshot: $OutputPath"
