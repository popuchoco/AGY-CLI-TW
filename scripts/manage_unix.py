#!/usr/bin/env python3
"""Install or remove the Antigravity CLI zh-TW customization on macOS/Linux."""

from __future__ import annotations

import json
import os
import shlex
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
STATUSLINE = CLI_DIR / "statusline-tw.py"
SKILL_DIR = CLI_DIR / "skills" / "zh-tw"
SKILL = SKILL_DIR / "SKILL.md"


def read_json(path: Path, default: dict) -> dict:
    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        return default
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {path} at line {exc.lineno}, column {exc.colno}") from exc
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


def validate_sources() -> tuple[str, str, str]:
    required = [
        ROOT / "resources" / "AGENTS.zh-TW.md",
        ROOT / "statusline-tw.py",
        ROOT / "skills" / "zh-tw" / "SKILL.md",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("Required package file(s) are missing: " + ", ".join(missing))
    agents_block = required[0].read_text(encoding="utf-8").strip()
    statusline_source = required[1].read_text(encoding="utf-8")
    skill_source = required[2].read_text(encoding="utf-8")
    return agents_block, statusline_source, skill_source


def preflight_writable_directories(create_missing: bool = True) -> None:
    for directory in (CONFIG_DIR, CLI_DIR, SKILL_DIR):
        if create_missing:
            directory.mkdir(parents=True, exist_ok=True)
        elif not directory.is_dir():
            continue
        fd, probe_name = tempfile.mkstemp(prefix=".agy-cli-tw-write-test-", dir=directory)
        os.close(fd)
        os.unlink(probe_name)


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
    agents_block, statusline_source, skill_source = validate_sources()
    settings = read_json(SETTINGS, {})
    state = read_json(STATE, {})
    preflight_writable_directories()

    agents_existed = AGENTS.exists()
    old_agents = AGENTS.read_text(encoding="utf-8") if AGENTS.exists() else ""
    atomic_write(AGENTS, merge_agents(old_agents, agents_block), 0o644)
    atomic_write(STATUSLINE, statusline_source, 0o644)
    atomic_write(SKILL, skill_source, 0o644)

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
    managed_is_current = isinstance(current, dict) and current.get("command") == state.get("managedCommand")
    if current is not None and not managed_is_current and STATE.exists():
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
    settings = read_json(SETTINGS, {}) if SETTINGS.exists() else {}
    preflight_writable_directories(create_missing=False)
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
        current = settings.get("statusLine")
        if isinstance(current, dict) and current.get("command") == state.get("managedCommand"):
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
    try:
        (install if sys.argv[1] == "install" else uninstall)()
    except (OSError, ValueError) as exc:
        print(f"安裝作業失敗，未能完成：{exc}", file=sys.stderr)
        raise SystemExit(1) from exc
