# 產品規劃：AGY-CLI-TW

本專案保留兩條繁體中文化途徑：**A. 官方設定增補包**與 **B. Windows ConPTY TUI 啟動器**。兩者功能範圍、技術方式及政策判讀分開說明；規劃文件不以移除某條途徑作為預設處置，也不宣稱 Google 已為本專案背書。

政策文件最近檢視：2026-11-26。

## 產品目標

- 為 Antigravity CLI 使用者提供台灣繁體中文的代理規則、`/zh-tw` Skill 與本機狀態列（途徑 A）。
- 為 Windows 使用者保留可選的互動式 TUI 固定字串翻譯啟動器（途徑 B）。
- 誠實記錄支援範圍、已知限制、CLI 版本相依性及 Google 公開政策文字。

## 產品途徑

### A. 官方設定增補包（建議的一般使用途徑）

使用 CLI 公開設定位置的 `AGENTS.md`、Agent Skill 與 `statusLine.command`；狀態列只格式化 CLI 傳入的 JSON，不呼叫 Antigravity 網路服務，也不啟動 `agy` 子程序。這是本專案較低耦合、跨平台的本地化方式。

### B. Windows ConPTY TUI 啟動器（保留的實驗性途徑）

`agy-tw.cmd`／`agy-tw.ps1` 以 Windows ConPTY 啟動使用者本機原版 `agy.exe`，轉送互動輸入，並翻譯已知的固定 TUI 字串。它不修改或注入 `agy.exe`，不使用 headless `agy -p`，也不透過 Codex、Claude Code 等第三方 AI 代理編排 CLI。

**途徑 B 仍是外部啟動器／互動式 CLI wrapper。**「不是 `agy -p`」不能推導成「已獲 Google 明確豁免」：Google FAQ 一方面概括說明第三方軟體、工具或服務存取 Antigravity 的限制，另一方面指出 `agy -p` 用於直接 scripting／CI，且在 consumer plan 下不支援由第三方 coding agent 或應用程式包裝 `agy`。FAQ／條款沒有專門判定本專案這種只做終端 UI 翻譯的 ConPTY 用法。因此本規劃保留 B 的程式碼與使用文件，但不把它標成 Google 核准，也不對此特定情境作確定的合規結論；若政策適用性會影響使用決策，需依 Google 最新文件或取得 Google 明確答覆判斷。

## 政策與技術邊界

- `agy -p` headless 呼叫、CI 自動化、帳號輪替、重用登入憑證供第三方 AI 代理存取，不屬於本專案功能目標。
- 途徑 A 不呼叫 CLI 子程序；途徑 B 則會啟動原版互動式 `agy.exe`。文件和產品描述必須清楚區分兩者，不得把 B 說成「完全不包裝／不啟動 agy」。
- 途徑 B 僅轉譯已觀察到的固定介面字串；版本、路徑、帳號、模型、強度、使用者內容、代理回覆及工具輸出保留原文。CLI 變更字串、ANSI 分段或排版後需重新驗證。
- 兩條途徑均不修改、重新簽署或注入 CLI 執行檔；這是專案的技術特性，不等同於政策許可判定。
- 每次發布前檢查 Google FAQ、Additional Terms of Service 與官方 CLI 文件的最新內容，並更新本文件的檢查日期或政策摘要。

## 路線圖

### P0：維持雙途徑資訊清晰

- README 同時介紹 A 與 B，標示 A 為跨平台的一般建議、B 為 Windows 實驗性選項。
- 保留 B 的啟動方式、ConPTY 需求、已翻譯範圍、限制及逐版本驗證方式。
- 說明 B 會啟動互動式原版 `agy.exe`、不是 `agy -p`，並準確呈現 FAQ／條款用語與未明確涵蓋之處。

### P1：改善途徑 A

- 維持安裝／解除安裝安全性、使用者設定保留、JSON 輸入驗證及 CJK 顯示寬度測試。
- 增補繁中規則、Skill、狀態列與跨平台文件；狀態列保持只處理 CLI 提供的輸入資料。

### P2：維護途徑 B 與政策紀錄

- CLI 有新版本時對照實際 UI，更新字串映射並執行 ConPTY 與畫面回歸測試。
- 對 FAQ 中「third-party software/tools/services」及「wrapping `agy` inside third-party coding agents or applications」的範圍持續追蹤；若官方新增 UI 翻譯介面或針對此用法作出說明，再調整對應技術與文件，不預先刪除 B。
- 可評估把字串映射抽離成資料檔，但須以 VT 序列安全、截短字串覆蓋及可測試性為前提。

## 驗收條件

- README 與架構文件保留並連結 A、B 兩條使用途徑；不把 B 誤標為 `agy -p` 或 AI 代理編排工具。
- 文件如實說明 B 會經 ConPTY 啟動互動式 `agy.exe`，也不將「非注入／非 headless」誇大為 Google 的明確核准。
- A 的安裝、狀態列、解除安裝測試通過；B 的翻譯映射、ConPTY 探測及 Windows 實機檢查通過。
- 截圖、範例輸出、測試日誌與文件不得洩露信箱、個人路徑或其他私密資料。

## 參考資料

- [Google Antigravity FAQ：第三方軟體及 CLI headless mode](https://antigravity.google/docs/faq/)
- [Google Antigravity Additional Terms of Service](https://antigravity.google/terms)
- [Antigravity CLI 狀態列自訂](https://antigravity.google/docs/cli/statusline/)
