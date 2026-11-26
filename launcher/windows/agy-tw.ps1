[CmdletBinding(PositionalBinding=$false)]
param(
    [string]$AgyExe = '',
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$AgyArgument = @()
)

$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public static class AgyPtyProxy
{
    const int STD_INPUT_HANDLE = -10;
    const int STD_OUTPUT_HANDLE = -11;
    const uint ENABLE_LINE_INPUT = 0x0002;
    const uint ENABLE_ECHO_INPUT = 0x0004;
    const uint ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200;
    const uint ENABLE_PROCESSED_OUTPUT = 0x0001;
    const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
    const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
    const int PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016;
    const uint WAIT_INFINITE = 0xFFFFFFFF;

    [StructLayout(LayoutKind.Sequential)]
    struct COORD { public short X; public short Y; public COORD(short x, short y) { X=x; Y=y; } }

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb;
        public IntPtr lpReserved;
        public IntPtr lpDesktop;
        public IntPtr lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct STARTUPINFOEX { public STARTUPINFO StartupInfo; public IntPtr lpAttributeList; }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CreatePipe(out SafeFileHandle hRead, out SafeFileHandle hWrite, IntPtr attrs, uint size);
    [DllImport("kernel32.dll", SetLastError=true)] static extern int CreatePseudoConsole(COORD size, SafeFileHandle hInput, SafeFileHandle hOutput, uint flags, out IntPtr hpc);
    [DllImport("kernel32.dll", SetLastError=true)] static extern void ClosePseudoConsole(IntPtr hpc);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list, int flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returnSize);
    [DllImport("kernel32.dll", SetLastError=true)] static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CreateProcessW(string app, StringBuilder commandLine, IntPtr processAttrs, IntPtr threadAttrs, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFOEX startup, out PROCESS_INFORMATION info);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetConsoleMode(IntPtr handle, out uint mode);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetConsoleMode(IntPtr handle, uint mode);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr GetStdHandle(int kind);
    [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle, uint ms);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern uint GetConsoleCP();
    [DllImport("kernel32.dll")] static extern uint GetConsoleOutputCP();
    [DllImport("kernel32.dll")] static extern bool SetConsoleCP(uint cp);
    [DllImport("kernel32.dll")] static extern bool SetConsoleOutputCP(uint cp);
    [DllImport("kernel32.dll", SetLastError=true)] static extern int ResizePseudoConsole(IntPtr hpc, COORD size);

    static Exception Win32Error(string name) { return new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), name); }

    public static string ProbeConPty()
    {
        SafeFileHandle inputRead=null,inputWrite=null,outputRead=null,outputWrite=null;
        IntPtr hpc=IntPtr.Zero;
        try
        {
            if (!CreatePipe(out inputRead,out inputWrite,IntPtr.Zero,0)) return "CreatePipe(input): " + Win32Error("Create input pipe").Message;
            if (!CreatePipe(out outputRead,out outputWrite,IntPtr.Zero,0)) return "CreatePipe(output): " + Win32Error("Create output pipe").Message;
            int hr=CreatePseudoConsole(new COORD(80,24),inputRead,outputWrite,0,out hpc);
            if (hr != 0) return "CreatePseudoConsole: " + new System.ComponentModel.Win32Exception(hr).Message;
            return null;
        }
        catch (Exception e) { return e.Message; }
        finally
        {
            if (hpc!=IntPtr.Zero) ClosePseudoConsole(hpc);
            if (inputRead!=null) inputRead.Dispose();
            if (inputWrite!=null) inputWrite.Dispose();
            if (outputRead!=null) outputRead.Dispose();
            if (outputWrite!=null) outputWrite.Dispose();
        }
    }

    static string Quote(string s)
    {
        if (s.Length == 0) return "\"\"";
        var b = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in s)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { b.Append('\\', slashes * 2 + 1).Append('"'); slashes=0; continue; }
            b.Append('\\', slashes).Append(c); slashes=0;
        }
        b.Append('\\', slashes * 2).Append('"');
        return b.ToString();
    }

    static readonly KeyValuePair<string,string>[] Maps = new [] {
        new KeyValuePair<string,string>("Keyboard Shortcuts", "鍵盤快速鍵"),
        new KeyValuePair<string,string>("Antigravity CLI understands your codebase, makes edits with your permission, and executes commands — right from your terminal.", "Antigravity CLI 能理解您的程式碼庫，經您同意後修改檔案並執行指令——直接在終端機中完成。"),
        new KeyValuePair<string,string>("Antigravity CLI understands your codebase,", "Antigravity CLI 能理解您的程式碼庫，"),
        new KeyValuePair<string,string>("Antigravity CLI understands your codebase", "Antigravity CLI 能理解您的程式碼庫"),
        new KeyValuePair<string,string>("makes edits with your permission", "經您同意後修改檔案"),
        new KeyValuePair<string,string>("executes commands", "執行指令"),
        new KeyValuePair<string,string>(", and", "，並"),
        new KeyValuePair<string,string>(" — ", "——"),
        new KeyValuePair<string,string>("right from your terminal.", "直接在終端機中完成。"),
        new KeyValuePair<string,string>("←/→ or tab to cycle", "←/→ 或按 Tab 切換"),
        new KeyValuePair<string,string>("Quick Reference", "快速參考"),
        new KeyValuePair<string,string>("/ Type to see available commands", "/ 輸入以查看可用指令"),
        new KeyValuePair<string,string>("Type to see available commands", "輸入以查看可用指令"),
        new KeyValuePair<string,string>("Available Commands", "可用指令"),
        new KeyValuePair<string,string>("Available commands", "可用指令"),
        new KeyValuePair<string,string>("Add a directory to the workspace", "將目錄加入工作區"),
        new KeyValuePair<string,string>("List available custom agents", "列出可用的自訂代理"),
        new KeyValuePair<string,string>("View and review artifacts", "檢視與審閱產物"),
        new KeyValuePair<string,string>("Ask a side question without interrupting the current task", "在不中斷目前工作的情況下提出旁支問題"),
        new KeyValuePair<string,string>("Show release notes and changes", "顯示版本資訊與變更"),
        new KeyValuePair<string,string>("Clear conversation and start a new one", "清除對話並開始新對話"),
        new KeyValuePair<string,string>("Search code in the workspace (usage: /codesearch <query>)", "搜尋工作區程式碼（用法：/codesearch <query>）"),
        new KeyValuePair<string,string>("Open settings panel", "開啟設定面板"),
        new KeyValuePair<string,string>("Visualize current context usage", "顯示目前上下文用量"),
        new KeyValuePair<string,string>("Copy the last planner response to the clipboard, the n-th with '/copy n', or the /btw answer with '/copy btw'", "複製最後一則規劃回覆；用 '/copy n' 複製第 n 則，或用 '/copy btw' 複製旁支回答"),
        new KeyValuePair<string,string>("Show remaining G1 credits and purchase link", "顯示剩餘 G1 點數與購買連結"),
        new KeyValuePair<string,string>("View uncommitted changes and per-turn diffs", "檢視未提交的變更與各回合差異"),
        new KeyValuePair<string,string>("Set the reasoning effort", "設定推理強度"),
        new KeyValuePair<string,string>("Exit the CLI", "離開 CLI"),
        new KeyValuePair<string,string>("Submit qualitative feedback to improve the agent", "提交意見回饋以協助改善代理"),
        new KeyValuePair<string,string>("Create a branch of the current conversation at this point, optionally specifying a project ID to fork into", "在此處為目前對話建立分支，也可指定要分叉到的專案 ID"),
        new KeyValuePair<string,string>("Show available commands and keybindings", "顯示可用指令與按鍵對應"),
        new KeyValuePair<string,string>("Manage hook configurations for tool events", "管理工具事件的 Hook 設定"),
        new KeyValuePair<string,string>("Version ", "版本 "),
        new KeyValuePair<string,string>("Workspace:", "工作區："),
        new KeyValuePair<string,string>("Project Config:", "專案設定："),
        new KeyValuePair<string,string>("Log File:", "記錄檔："),
        new KeyValuePair<string,string>("/keybindings to customize", "輸入 /keybindings 自訂"),
        new KeyValuePair<string,string>("Open slash commands", "開啟斜線指令"),
        new KeyValuePair<string,string>("Insert newline fallback", "插入換行（替代方式）"),
        new KeyValuePair<string,string>("Manage subagent", "管理子代理"),
        new KeyValuePair<string,string>("Send with opposite Queued Messages setting", "依相反的「佇列訊息」設定傳送"),
        new KeyValuePair<string,string>("Paste image/video", "貼上圖片／影片"),
        new KeyValuePair<string,string>("Go back / dismiss", "返回／關閉"),
        new KeyValuePair<string,string>("Go to bottom", "移至底部"),
        new KeyValuePair<string,string>("Open prompt in $EDITOR", "在 $EDITOR 中開啟提示"),
        new KeyValuePair<string,string>("Approve subagent fast", "快速核准子代理"),
        new KeyValuePair<string,string>("Clear CLI screen", "清除 CLI 畫面"),
        new KeyValuePair<string,string>("Toggle trajectory view", "切換軌跡檢視"),
        new KeyValuePair<string,string>("Review artifact", "檢視成品"),
        new KeyValuePair<string,string>("Yank (paste from kill ring)", "從剪貼環貼上"),
        new KeyValuePair<string,string>("[1-18 of 27 items]", "[第 1–18 項，共 27 項]"),
        new KeyValuePair<string,string>("Switch View", "切換檢視"),
        new KeyValuePair<string,string>("? for shortcuts", "? 查看快速鍵"),
        new KeyValuePair<string,string>("Auto is now the default agent mode", "Auto 現為預設代理模式"),
        new KeyValuePair<string,string>("Press Shift+Tab to switch agent modes, or change Agent Mode in /config.", "按 Shift+Tab 切換代理模式，或在 /config 變更代理模式。"),
        new KeyValuePair<string,string>("esc to dismiss", "按 Esc 關閉提示"),
        new KeyValuePair<string,string>("Esc to dismiss", "按 Esc 關閉提示"),
        new KeyValuePair<string,string>("Accessing workspace:", "正在存取工作區："),
        new KeyValuePair<string,string>("Antigravity CLI requires permission to read, edit, and execute files here.", "Antigravity CLI 需要取得此處的讀取、編輯與執行權限。"),
        new KeyValuePair<string,string>("↑/↓ Navigate · enter Confirm", "↑/↓ 導覽 · Enter 確認"),
        new KeyValuePair<string,string>("Do you trust the contents of this project?", "您信任此專案的內容嗎？"),
        new KeyValuePair<string,string>("Yes, I trust this folder", "是，我信任此資料夾"),
        new KeyValuePair<string,string>("No, exit", "否，離開"),
        new KeyValuePair<string,string>("Type / to see available commands", "輸入 / 查看可用指令"),
        new KeyValuePair<string,string>("Send message or confirm", "傳送訊息或確認"),
        new KeyValuePair<string,string>("Insert newline", "插入換行"),
        new KeyValuePair<string,string>("Undo", "復原"),
        new KeyValuePair<string,string>("Suspend CLI", "暫停 CLI"),
        new KeyValuePair<string,string>("Suspend CLI", "暫停 CLI"),
        new KeyValuePair<string,string>("Rename", "重新命名"),
        new KeyValuePair<string,string>("Delete", "刪除"),
        new KeyValuePair<string,string>("Start voice dictation", "開始語音聽寫"),
        new KeyValuePair<string,string>("Half page down", "向下半頁"),
        new KeyValuePair<string,string>("Cycle mode", "切換模式"),
        new KeyValuePair<string,string>("Half page up", "向上半頁"),
        new KeyValuePair<string,string>("Select and copy text", "選取並複製文字"),
        new KeyValuePair<string,string>("Set custom keybindings", "設定自訂按鍵對應"),
        new KeyValuePair<string,string>("Log out", "登出"),
        new KeyValuePair<string,string>("Manage MCP servers", "管理 MCP 伺服器"),
        new KeyValuePair<string,string>("Set a model, or run a single prompt on another model", "設定模型，或使用其他模型執行單次提示"),
        new KeyValuePair<string,string>("Open a file or view opened/edited files", "開啟檔案或檢視已開啟／編輯的檔案"),
        new KeyValuePair<string,string>("Manage tool permissions", "管理工具權限"),
        new KeyValuePair<string,string>("Create and edit projects", "建立與編輯專案"),
        new KeyValuePair<string,string>("Dictate a prompt using your microphone", "使用麥克風聽寫提示"),
        new KeyValuePair<string,string>("Rename the current conversation", "重新命名目前對話"),
        new KeyValuePair<string,string>("Browse and resume past conversations", "瀏覽並繼續過往對話"),
        new KeyValuePair<string,string>("Rewind conversation to a previous message", "將對話倒回先前訊息"),
        new KeyValuePair<string,string>("List available skills", "列出可用技能"),
        new KeyValuePair<string,string>("Toggle the statusline", "切換狀態列"),
        new KeyValuePair<string,string>("View background tasks", "檢視背景工作"),
        new KeyValuePair<string,string>("Toggle custom terminal window title", "切換自訂終端視窗標題"),
        new KeyValuePair<string,string>("View model quota usage", "檢視模型配額用量"),
        new KeyValuePair<string,string>("Invoke a browser agent for web tasks.", "呼叫瀏覽器代理處理網頁工作。"),
        new KeyValuePair<string,string>("Plan carefully before executing a task.", "執行前仔細規劃。"),
        new KeyValuePair<string,string>("Interview me to align on a plan.", "訪談我以對齊計畫。"),
        new KeyValuePair<string,string>("Manage, discover, install, uninstall, enable, and disable plugins", "管理、探索、安裝、解除安裝、啟用與停用外掛"),
        new KeyValuePair<string,string>("Turn on remote control for this session (off to disable)%s", "啟用此工作階段的遠端控制（輸入 off 關閉）%s"),
        new KeyValuePair<string,string>("Toggle streaming the model's full thinking in the transcript", "切換是否在逐字稿中串流顯示模型完整思考過程"),
        new KeyValuePair<string,string>("Dictate a prompt or talk with the agent by voice", "使用語音聽寫提示或與代理對話"),
        new KeyValuePair<string,string>("Run until the specified goal is completely finished.", "持續執行，直到指定目標完成。"),
        new KeyValuePair<string,string>("Compact the conversation now (summarize history to free up the context window).", "立即壓縮對話（摘要歷史內容以釋放上下文視窗）。"),
        new KeyValuePair<string,string>("Run an instruction on a recurring schedule or as a one-time timer.", "依週期排程或單次計時器執行指令。"),
        new KeyValuePair<string,string>("Reflect on recent successes or corrections to capture reusable skills or rules.", "回顧近期成功經驗或修正，整理成可重用的技能或規則。"),
        new KeyValuePair<string,string>("Comprehensive guide and reference for the Antigravity Customization System.", "Antigravity 自訂系統完整指南與參考資料。"),
        new KeyValuePair<string,string>("Provides a comprehensive guide, quick reference, and sitemap for Google Antigravity (AGY), including the Antigravity CLI (agy), Antigravity 2.0, Antigravity IDE, Python SDK, slash commands, keybindings, and customizations (skills, rules, MCP, sidecars). Activate this skill when the user asks questions about how to use, configure, or customize Antigravity, AGY, the agy CLI, the Antigravity IDE, or Antigravity 2.0.", "提供 Google Antigravity（AGY）完整指南、快速參考與網站地圖，涵蓋 CLI、Antigravity 2.0、IDE、Python SDK、斜線指令、快速鍵及自訂功能（技能、規則、MCP、sidecar）。使用者詢問相關使用、設定或自訂方式時啟用此技能。"),
        new KeyValuePair<string,string>("How to write and run a dynamic workflow script with the `run_workflow` tool:", "如何使用 `run_workflow` 工具撰寫並執行動態工作流程指令碼："),
        new KeyValuePair<string,string>("(Preview & Quota Heavy) Run a swarm: several agents working in parallel on", "（預覽／配額消耗較高）執行 Swarm 多代理並行工作…"),
        new KeyValuePair<string,string>(" (←/→ or tab to cycle)", "（←/→ 或按 Tab 切換）"),
        new KeyValuePair<string,string>("Keyboard: ", "鍵盤："),
        new KeyValuePair<string,string>(" · ", " · "),
        new KeyValuePair<string,string>("and executes commands", "並執行指令"),
        new KeyValuePair<string,string>("Go to top", "移至頂端"),
        new KeyValuePair<string,string>("Exit", "離開"),
        new KeyValuePair<string,string>("Redo", "重做"),
        new KeyValuePair<string,string>("Navigate", "導覽"),
        new KeyValuePair<string,string>("Close", "關閉"),
    };

    // The CLI truncates command descriptions to the current terminal width before
    // they reach ConPTY. Translate these visible row prefixes as a fallback when
    // the complete source string is no longer present in the output stream.
    static readonly KeyValuePair<string,string>[] TruncatedRowMaps = new [] {
        new KeyValuePair<string,string>("Ask a side question without interrupting", "在不中斷目前工作的情況下提出旁支問題"),
        new KeyValuePair<string,string>("Search code in the workspace", "搜尋工作區程式碼（用法：/codesearch <query>）"),
        new KeyValuePair<string,string>("Copy the last planner response to the clip", "複製最後一則規劃回覆到剪貼簿…"),
        new KeyValuePair<string,string>("Submit qualitative feedback to improve the", "提交意見回饋以協助改善代理"),
        new KeyValuePair<string,string>("Create a branch of the current conversatio", "從目前對話建立分支…"),
        new KeyValuePair<string,string>("Set a model, or run a single prompt on ano", "設定模型，或使用其他模型執行單次提示…"),
        new KeyValuePair<string,string>("Manage, discover, install, uninstall", "管理、探索、安裝、解除安裝及啟用外掛…"),
        new KeyValuePair<string,string>("Turn on remote control for this session", "啟用此工作階段的遠端控制…"),
        new KeyValuePair<string,string>("Toggle streaming the model's full thinking", "切換模型完整思考過程的串流顯示…"),
        new KeyValuePair<string,string>("Dictate a prompt or talk with the agent", "聽寫提示或與代理語音交談…"),
        new KeyValuePair<string,string>("Run until the specified goal is completely", "持續執行，直到指定目標完成…"),
        new KeyValuePair<string,string>("Compact the conversation now", "立即壓縮對話以釋放上下文…"),
        new KeyValuePair<string,string>("Run an instruction on a recurring schedule", "依週期排程或單次計時器執行指令…"),
        new KeyValuePair<string,string>("Reflect on recent successes or corrections", "回顧近期成功經驗或修正，整理成可重用技能／規則…"),
        new KeyValuePair<string,string>("Comprehensive guide and reference for the", "Antigravity CLI 完整指南與參考資料…"),
        new KeyValuePair<string,string>("Provides a comprehensive guide, quick refe", "提供 Antigravity 完整指南、快速參考與網站地圖…"),
        new KeyValuePair<string,string>("How to write and run a dynamic workflow", "使用 run_workflow 撰寫與執行動態工作流程…"),
        new KeyValuePair<string,string>("(Preview & Quota Heavy) Run a swarm", "（預覽／配額消耗較高）執行 Swarm 多代理工作…"),
    };

    static readonly Dictionary<string,string> LabelMaps = new Dictionary<string,string>(StringComparer.Ordinal) {
        { "general", "一般" }, { "commands", "指令" }, { "shortcuts", "快速鍵" },
        { "Navigate", "導覽" }, { "Undo", "復原" }, { "Redo", "重做" },
        { "Exit", "結束" }, { "Go to top", "移至頂端" }, { "Close", "關閉" },
        { "Keyboard:", "鍵盤：" }, { "Confirm", "確認" },
    };

    sealed class VtTranslator
    {
        readonly Stream output;
        readonly StringBuilder text = new StringBuilder();
        readonly StringBuilder escape = new StringBuilder();
        bool inEscape = false;
        bool osc = false;
        bool oscEsc = false;
        readonly byte[] byteBuffer = new byte[16384];
        readonly char[] charBuffer = new char[16384];
        readonly Decoder decoder = new UTF8Encoding(false, false).GetDecoder();

        public VtTranslator(Stream outputStream) { output=outputStream; }

        void WriteText()
        {
            if (text.Length == 0) return;
            string value = text.ToString();
            foreach (var pair in Maps.OrderByDescending(x => x.Key.Length))
                value = value.Replace(pair.Key, pair.Value);
            foreach (var pair in TruncatedRowMaps)
                value = Regex.Replace(value, Regex.Escape(pair.Key) + @"[^\r\n]*", pair.Value);
            value = Regex.Replace(value, @"\band\b", "並");
            value = Regex.Replace(value, @"\[(\d+)-(\d+) of (\d+) items\]", "[第 $1–$2 項，共 $3 項]");
            string trimmed = value.Trim();
            string translatedLabel;
            if (LabelMaps.TryGetValue(trimmed, out translatedLabel))
                value = value.Substring(0, value.Length - value.TrimStart().Length) + translatedLabel + value.Substring(value.TrimEnd().Length);
            else if (Regex.IsMatch(trimmed, "^(general|commands|shortcuts)(\\s+(general|commands|shortcuts))*$"))
                value = Regex.Replace(value, "\\b(general|commands|shortcuts)\\b", m => LabelMaps[m.Value]);
            byte[] bytes = Encoding.UTF8.GetBytes(value);
            output.Write(bytes, 0, bytes.Length);
            text.Clear();
        }
        void WriteChars(char[] chars, int count)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(chars, 0, count);
            output.Write(bytes, 0, bytes.Length);
        }
        void WriteEscape()
        {
            if (escape.Length == 0) return;
            byte[] bytes = Encoding.UTF8.GetBytes(escape.ToString());
            output.Write(bytes, 0, bytes.Length);
            escape.Clear(); inEscape=false; osc=false; oscEsc=false;
        }
        bool EscapeDone(char c)
        {
            if (escape.Length == 2)
            {
                if (c == '[') return false;
                if (c == ']') { osc=true; return false; }
                return true;
            }
            if (osc)
            {
                if (c == '\a') return true;
                if (oscEsc && c == '\\') return true;
                oscEsc = (c == '\x1b');
                return false;
            }
            if (escape.Length > 1 && escape[1] == '[') return c >= 0x40 && c <= 0x7e;
            if (escape.Length > 1 && escape[1] == 'P') return c == '\x1b';
            return true;
        }
        public void Process(char[] chars, int count)
        {
            for (int i=0; i<count; i++)
            {
                char c=chars[i];
                if (inEscape)
                {
                    escape.Append(c);
                    if (EscapeDone(c)) WriteEscape();
                    continue;
                }
                if (c == '\x1b')
                {
                    WriteText(); inEscape=true; escape.Append(c); continue;
                }
                if (c < 0x20 || c == 0x7f)
                {
                    WriteText(); WriteChars(chars, i, 1); continue;
                }
                text.Append(c);
                if (text.Length >= 65536) WriteText();
            }
            output.Flush();
        }
        void WriteChars(char[] chars, int start, int count)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(chars, start, count);
            output.Write(bytes, 0, bytes.Length);
        }
        public void Pump(Stream input)
        {
            int read;
            while ((read=input.Read(byteBuffer,0,byteBuffer.Length)) > 0)
            {
                int chars=decoder.GetChars(byteBuffer,0,read,charBuffer,0,false);
                Process(charBuffer, chars);
            }
            int finalChars=decoder.GetChars(new byte[0],0,0,charBuffer,0,true);
            Process(charBuffer, finalChars);
            WriteText(); WriteEscape(); output.Flush();
        }
    }

    public static int Run(string exe, string[] args)
    {
        if (!File.Exists(exe)) throw new FileNotFoundException("agy.exe not found", exe);
        IntPtr inputConsole=GetStdHandle(STD_INPUT_HANDLE), outputConsole=GetStdHandle(STD_OUTPUT_HANDLE);
        uint oldIn=0,oldOut=0,oldCP=GetConsoleCP(),oldOutCP=GetConsoleOutputCP();
        bool haveIn=GetConsoleMode(inputConsole,out oldIn), haveOut=GetConsoleMode(outputConsole,out oldOut);
        if (haveIn) SetConsoleMode(inputConsole, (oldIn & ~(ENABLE_LINE_INPUT|ENABLE_ECHO_INPUT)) | ENABLE_VIRTUAL_TERMINAL_INPUT);
        if (haveOut) SetConsoleMode(outputConsole, oldOut | ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        SetConsoleCP(65001); SetConsoleOutputCP(65001);

        SafeFileHandle inputRead=null,inputWrite=null,outputRead=null,outputWrite=null;
        IntPtr hpc=IntPtr.Zero, attrList=IntPtr.Zero;
        PROCESS_INFORMATION pi=new PROCESS_INFORMATION();
        FileStream inputPipe=null,outputPipe=null;
        Thread readThread=null,inputThread=null,resizeThread=null;
        int keepResizing=1;
        try
        {
            if (!CreatePipe(out inputRead,out inputWrite,IntPtr.Zero,0)) throw Win32Error("Create input pipe");
            if (!CreatePipe(out outputRead,out outputWrite,IntPtr.Zero,0)) throw Win32Error("Create output pipe");
            short width=120,height=32;
            try { width=(short)Math.Max(40,Console.WindowWidth); height=(short)Math.Max(12,Console.WindowHeight); } catch {}
            int hr=CreatePseudoConsole(new COORD(width,height),inputRead,outputWrite,0,out hpc);
            if (hr != 0) throw new System.ComponentModel.Win32Exception(hr,"CreatePseudoConsole failed (HRESULT)");

            IntPtr attrSize=IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref attrSize);
            attrList=Marshal.AllocHGlobal(attrSize);
            if (!InitializeProcThreadAttributeList(attrList,1,0,ref attrSize)) throw Win32Error("Initialize attribute list");
            if (!UpdateProcThreadAttribute(attrList,0,new IntPtr(PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE),hpc,new IntPtr(IntPtr.Size),IntPtr.Zero,IntPtr.Zero)) throw Win32Error("Set pseudoconsole attribute");

            var startup=new STARTUPINFOEX();
            startup.StartupInfo.cb=Marshal.SizeOf(typeof(STARTUPINFOEX));
            startup.lpAttributeList=attrList;
            string command=Quote(exe)+String.Concat(args.Select(Quote).Select(x=>" "+x));
            var mutableCommand=new StringBuilder(command);
            if (!CreateProcessW(exe,mutableCommand,IntPtr.Zero,IntPtr.Zero,false,EXTENDED_STARTUPINFO_PRESENT,IntPtr.Zero,Directory.GetCurrentDirectory(),ref startup,out pi)) throw Win32Error("Create agy process");

            CloseHandle(pi.hThread); pi.hThread=IntPtr.Zero;
            // Free the two ends owned by the pseudoconsole after CreateProcess, as required by the ConPTY lifecycle.
            inputRead.Dispose(); inputRead=null; outputWrite.Dispose(); outputWrite=null;
            DeleteProcThreadAttributeList(attrList); Marshal.FreeHGlobal(attrList); attrList=IntPtr.Zero;

            inputPipe=new FileStream(inputWrite,FileAccess.Write,4096,false);
            outputPipe=new FileStream(outputRead,FileAccess.Read,4096,false);
            Stream hostIn=Console.OpenStandardInput();
            Stream hostOut=Console.OpenStandardOutput();
            var translator=new VtTranslator(hostOut);
            readThread=new Thread(()=>{ try { translator.Pump(outputPipe); } catch (Exception e) { Console.Error.WriteLine("PTY output pump failed: " + e); } }) { IsBackground=true, Name="agy-pty-output" };
            inputThread=new Thread(()=>{
                byte[] buffer=new byte[4096];
                try { int n; while ((n=hostIn.Read(buffer,0,buffer.Length))>0) { inputPipe.Write(buffer,0,n); inputPipe.Flush(); } } catch {}
            }) { IsBackground=true, Name="agy-pty-input" };
            IntPtr resizeConsole=hpc;
            short lastWidth=width,lastHeight=height;
            resizeThread=new Thread(()=>{
                while (Interlocked.CompareExchange(ref keepResizing,1,1)==1)
                {
                    Thread.Sleep(250);
                    try {
                        short currentWidth=(short)Math.Max(40,Math.Min(300,Console.WindowWidth));
                        short currentHeight=(short)Math.Max(12,Math.Min(120,Console.WindowHeight));
                        if (currentWidth!=lastWidth || currentHeight!=lastHeight) {
                            if (ResizePseudoConsole(resizeConsole,new COORD(currentWidth,currentHeight))==0) {
                                lastWidth=currentWidth; lastHeight=currentHeight;
                            }
                        }
                    } catch {}
                }
            }) { IsBackground=true, Name="agy-pty-resize" };
            readThread.Start(); inputThread.Start(); resizeThread.Start();
            WaitForSingleObject(pi.hProcess,WAIT_INFINITE);
            uint exitCode=0; GetExitCodeProcess(pi.hProcess,out exitCode);
            Interlocked.Exchange(ref keepResizing,0);
            if (resizeThread != null) resizeThread.Join(1000);
            ClosePseudoConsole(hpc); hpc=IntPtr.Zero;
            inputPipe.Dispose(); inputPipe=null;
            if (readThread != null) readThread.Join();
            outputPipe.Dispose(); outputPipe=null;
            return unchecked((int)exitCode);
        }
        finally
        {
            Interlocked.Exchange(ref keepResizing,0);
            if (resizeThread!=null) resizeThread.Join(1000);
            if (hpc!=IntPtr.Zero) ClosePseudoConsole(hpc);
            if (attrList!=IntPtr.Zero) { DeleteProcThreadAttributeList(attrList); Marshal.FreeHGlobal(attrList); }
            if (pi.hThread!=IntPtr.Zero) CloseHandle(pi.hThread);
            if (pi.hProcess!=IntPtr.Zero) CloseHandle(pi.hProcess);
            if (inputPipe!=null) inputPipe.Dispose();
            if (outputPipe!=null) outputPipe.Dispose();
            if (inputRead!=null) inputRead.Dispose();
            if (inputWrite!=null) inputWrite.Dispose();
            if (outputRead!=null) outputRead.Dispose();
            if (outputWrite!=null) outputWrite.Dispose();
            if (haveIn) SetConsoleMode(inputConsole,oldIn);
            if (haveOut) SetConsoleMode(outputConsole,oldOut);
            if (oldCP!=0) SetConsoleCP(oldCP);
            if (oldOutCP!=0) SetConsoleOutputCP(oldOutCP);
        }
    }
}
'@

if ([string]::IsNullOrWhiteSpace($AgyExe)) {
    if ($env:AGY_EXE) {
        $AgyExe = $env:AGY_EXE
    } else {
        $agyCommand = Get-Command agy.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($agyCommand) { $AgyExe = $agyCommand.Source }
        else { $AgyExe = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe' }
    }
}
if (-not (Test-Path -LiteralPath $AgyExe -PathType Leaf)) {
    Write-Error "找不到 agy.exe：$AgyExe。請安裝 Antigravity CLI，或設定 AGY_EXE。"
    exit 2
}
if ($null -eq ('AgyPtyProxy' -as [type])) { Add-Type -TypeDefinition $source -Language CSharp }
$conPtyError = [AgyPtyProxy]::ProbeConPty()
if ($conPtyError) {
    [Console]::Error.WriteLine("此環境無法建立 Windows ConPTY：$conPtyError。請改用途徑 A（官方設定增補包）。")
    exit 3
}
try {
    exit [AgyPtyProxy]::Run($AgyExe, $AgyArgument)
} catch {
    [Console]::Error.WriteLine("外部啟動器執行失敗：$($_.Exception.Message)")
    exit 3
}
