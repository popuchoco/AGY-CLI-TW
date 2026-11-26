#!/usr/bin/env python3
"""Cross-platform tests for the macOS/Linux settings installer."""

import json
import os
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANAGER = ROOT / "scripts" / "manage_unix.py"
STATUSLINE = ROOT / "statusline-tw.py"


def run(action: str, home: Path) -> None:
    env = os.environ.copy()
    env["AGY_CLI_TW_HOME"] = str(home)
    subprocess.run([sys.executable, str(MANAGER), action], env=env, check=True, capture_output=True, text=True)


def run_expect_failure(action: str, home: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["AGY_CLI_TW_HOME"] = str(home)
    return subprocess.run([sys.executable, str(MANAGER), action], env=env, capture_output=True, text=True)


def display_width(text: str) -> int:
    return sum(
        0 if unicodedata.combining(ch) or unicodedata.category(ch) in {"Cc", "Cf", "Mn", "Me"}
        else 2 if unicodedata.east_asian_width(ch) in {"F", "W"}
        else 1
        for ch in text
    )


with tempfile.TemporaryDirectory(prefix="agy cli tw unix-") as temp:
    home = Path(temp)
    gemini = home / ".gemini"
    config_dir = gemini / "config"
    cli_dir = gemini / "antigravity-cli"
    config_dir.mkdir(parents=True)
    cli_dir.mkdir(parents=True)
    agents = config_dir / "AGENTS.md"
    agents.write_text("# Existing global rule\nUse concise responses.\n", encoding="utf-8")
    settings_path = cli_dir / "settings.json"
    original = {"colorScheme": "dark", "statusLine": {"type": "command", "command": "old-statusline"}}
    settings_path.write_text(json.dumps(original), encoding="utf-8")

    run("install", home)
    installed = json.loads(settings_path.read_text(encoding="utf-8"))
    assert installed["colorScheme"] == "dark"
    assert "statusline-tw.py" in installed["statusLine"]["command"]
    assert "python3 -c" not in installed["statusLine"]["command"]
    configured_command = installed["statusLine"]["command"]
    assert agents.read_text(encoding="utf-8").count("<!-- BEGIN AGY-CLI-TW -->") == 1
    assert (cli_dir / "skills" / "zh-tw" / "SKILL.md").exists()
    if os.name != "nt":
        assert stat.S_IMODE((config_dir / "AGENTS.md").stat().st_mode) == 0o644
        assert stat.S_IMODE((cli_dir / ".agy-cli-tw-state.json").stat().st_mode) == 0o600

    payload = {
        "agent_state": "thinking",
        "context_window": {"used_percentage": 12.4},
        "vcs": {"branch": "feature/繁體中文-very-long-branch", "dirty": True},
        "sandbox": {"enabled": True},
        "artifact_count": 3,
        "subagents": {"unexpected": "object, not a list"},
        "task_count": 2,
        "model": {"display_name": "Gemini 4 Hydrogen"},
        "terminal_width": 40,
    }
    status_env = os.environ.copy()
    status_env.pop("COLUMNS", None)
    if os.name == "nt":
        # The Unix settings command is POSIX shell syntax; execute its parsed
        # argument vector with the current interpreter when exercising tests on
        # Windows, where `python3` may be exposed under a different alias.
        command_args = shlex.split(configured_command)
        if command_args[0] == "python3" and not shutil.which("python3"):
            command_args[0] = sys.executable
        status_run = subprocess.run(
            command_args,
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=status_env,
            check=True,
        )
    else:
        # Exercise the exact command that Antigravity CLI will hand to its
        # shell, including shlex quoting for installation paths with spaces.
        status_run = subprocess.run(
            ["/bin/sh", "-c", configured_command],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=status_env,
            check=True,
        )
    assert "思考中" in status_run.stdout and "Gemini 4 Hydrogen" in status_run.stdout
    assert "代理：0" in status_run.stdout
    assert all(display_width(line) <= payload["terminal_width"] for line in status_run.stdout.splitlines())
    malformed = subprocess.run(
        [sys.executable, str(cli_dir / "statusline-tw.py")],
        input="not-json",
        capture_output=True,
        text=True,
        check=True,
    )
    assert "等待工作階段資料" in malformed.stdout

    run("install", home)
    assert agents.read_text(encoding="utf-8").count("<!-- BEGIN AGY-CLI-TW -->") == 1
    run("uninstall", home)
    restored = json.loads(settings_path.read_text(encoding="utf-8"))
    assert restored == original, restored
    assert "Use concise responses." in agents.read_text(encoding="utf-8")
    assert "BEGIN AGY-CLI-TW" not in agents.read_text(encoding="utf-8")
    assert not (cli_dir / "skills" / "zh-tw" / "SKILL.md").exists()

    empty_home = home / "no-original-statusline"
    (empty_home / ".gemini" / "config").mkdir(parents=True)
    (empty_home / ".gemini" / "antigravity-cli").mkdir(parents=True)
    (empty_home / ".gemini" / "antigravity-cli" / "settings.json").write_text(
        json.dumps({"colorScheme": "light"}), encoding="utf-8"
    )
    run("install", empty_home)
    no_status_settings = empty_home / ".gemini" / "antigravity-cli" / "settings.json"
    if os.name != "nt":
        assert stat.S_IMODE((empty_home / ".gemini" / "config" / "AGENTS.md").stat().st_mode) == 0o644
    modified = json.loads(no_status_settings.read_text(encoding="utf-8"))
    modified["statusLine"] = {"type": "command", "command": "user-custom-statusline"}
    no_status_settings.write_text(json.dumps(modified), encoding="utf-8")
    run("uninstall", empty_home)
    preserved = json.loads(no_status_settings.read_text(encoding="utf-8"))
    assert preserved["statusLine"]["command"] == "user-custom-statusline"
    assert preserved["colorScheme"] == "light"

    broken_home = home / "invalid-json"
    broken_cli = broken_home / ".gemini" / "antigravity-cli"
    broken_config = broken_home / ".gemini" / "config"
    broken_cli.mkdir(parents=True)
    broken_config.mkdir(parents=True)
    (broken_cli / "settings.json").write_text("{ invalid json", encoding="utf-8")
    failed = run_expect_failure("install", broken_home)
    assert failed.returncode != 0 and "Invalid JSON" in failed.stderr
    assert not (broken_config / "AGENTS.md").exists()
    assert not (broken_cli / "statusline-tw.py").exists()
    assert not (broken_cli / "skills" / "zh-tw" / "SKILL.md").exists()

print("PASS: Unix installer settings merge, repeat install, restore, and user-change preservation.")
