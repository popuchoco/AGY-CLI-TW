#!/usr/bin/env python3
"""Install or remove the Antigravity CLI zh-TW customization on macOS/Linux."""

from __future__ import annotations

import json
import os
import shlex
import shutil
import sys
import tempfile
from pathlib import Path

BEGIN = "<!-- BEGIN AGY-CLI-TW -->"
END = "<!-- END AGY-CLI-TW -->"
ROOT = Path(__file__).resolve().parents[1]
HOME = Path(os.environ.get("AGY_CLI_TW_HOME") or Path.home())
GEMINI = HOME / ".gemini"
CONFIG_DIR = GEMINI / "config"
CLI_DIR = GEMINI / "antigravity-cli"
AGENTS = CONFIG_DIR / "AGENTS.md"
SETTINGS = CLI_DIR / "settings.json"
STATE = CLI_DIR / ".agy-cli-tw-state.json"
STATUSLINE = CLI_DIR / "statusline-tw.sh"
SKILL_DIR = CLI_DIR / "skills" / "zh-tw"
SKILL = SKILL_DIR / "SKILL.md"


def read_json(path: Path, default: dict) -> dict:
    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        return default
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def atomic_write(path: Path, text: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    old_mode = path.stat().st_mode & 0o777 if path.exists() else mode
    fd, temp_name = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
        os.chmod(temp_name, old_mode)
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def merge_agents(existing: str, block: str) -> str:
    start = existing.find(BEGIN)
    end = existing.find(END)
    if start >= 0 and end >= start:
        end += len(END)
        return existing[:start] + block + existing[end:]
    prefix = existing
    if prefix and not prefix.endswith("\n"):
        prefix += "\n"
    return prefix + "\n" + block + "\n"


def install() -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CLI_DIR.mkdir(parents=True, exist_ok=True)
    SKILL_DIR.mkdir(parents=True, exist_ok=True)
    agents_existed = AGENTS.exists()
    old_agents = AGENTS.read_text(encoding="utf-8") if AGENTS.exists() else ""
    block = (ROOT / "resources" / "AGENTS.zh-TW.md").read_text(encoding="utf-8").strip()
    atomic_write(AGENTS, merge_agents(old_agents, block), 0o600)
    shutil.copy2(ROOT / "statusline-tw.sh", STATUSLINE)
    STATUSLINE.chmod(STATUSLINE.stat().st_mode | 0o111)
    shutil.copy2(ROOT / "skills" / "zh-tw" / "SKILL.md", SKILL)

    settings = read_json(SETTINGS, {})
    state = read_json(STATE, {})
    current = settings.get("statusLine")
    command = "python3 " + shlex.quote(str(STATUSLINE))
    if not state:
        state = {
            "schemaVersion": 1,
            "agentsFileExisted": agents_existed,
            "originalStatusLinePresent": "statusLine" in settings,
            "originalStatusLine": current,
            "managedCommand": command,
        }
    if current and current.get("command") != state.get("managedCommand") and STATE.exists():
        print("偵測到安裝後另行變更的 statusLine；保留目前設定。", file=sys.stderr)
    else:
        settings["statusLine"] = {"type": "command", "command": command}
    atomic_write(STATE, json.dumps(state, ensure_ascii=False, indent=2) + "\n")
    atomic_write(SETTINGS, json.dumps(settings, ensure_ascii=False, indent=2) + "\n")
    print("已安裝 Antigravity CLI 台灣繁體中文增補包。")
    print(f"全域規則：{AGENTS}")
    print(f"狀態列設定：{SETTINGS}")
    print("請重新啟動 agy 以載入設定。")


def uninstall() -> None:
    state = read_json(STATE, {})
    if AGENTS.exists():
        existing = AGENTS.read_text(encoding="utf-8")
        start, end = existing.find(BEGIN), existing.find(END)
        if start >= 0 and end >= start:
            end += len(END)
            remaining = existing[:start] + existing[end:]
            if not remaining.strip() and not state.get("agentsFileExisted", True):
                AGENTS.unlink()
            else:
                atomic_write(AGENTS, remaining, 0o600)

    if SETTINGS.exists() and state:
        settings = read_json(SETTINGS, {})
        current = settings.get("statusLine")
        if current and current.get("command") == state.get("managedCommand"):
            settings.pop("statusLine", None)
            if state.get("originalStatusLinePresent"):
                settings["statusLine"] = state.get("originalStatusLine")
            atomic_write(SETTINGS, json.dumps(settings, ensure_ascii=False, indent=2) + "\n")
        elif current:
            print("目前的 statusLine 與本套件安裝值不同；保留目前設定。", file=sys.stderr)

    STATUSLINE.unlink(missing_ok=True)
    SKILL.unlink(missing_ok=True)
    STATE.unlink(missing_ok=True)
    try:
        SKILL_DIR.rmdir()
    except OSError:
        pass
    print("已移除 Antigravity CLI 台灣繁體中文增補包。")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in {"install", "uninstall"}:
        raise SystemExit("Usage: manage_unix.py install|uninstall")
    (install if sys.argv[1] == "install" else uninstall)()
