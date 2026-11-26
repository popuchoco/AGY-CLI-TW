#!/usr/bin/env python3
"""Cross-platform tests for the macOS/Linux settings installer."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANAGER = ROOT / "scripts" / "manage_unix.py"


def run(action: str, home: Path) -> None:
    env = os.environ.copy()
    env["AGY_CLI_TW_HOME"] = str(home)
    subprocess.run([sys.executable, str(MANAGER), action], env=env, check=True, capture_output=True, text=True)


with tempfile.TemporaryDirectory(prefix="agy-cli-tw-unix-") as temp:
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
    assert "statusline-tw.sh" in installed["statusLine"]["command"]
    assert agents.read_text(encoding="utf-8").count("<!-- BEGIN AGY-CLI-TW -->") == 1
    assert (cli_dir / "skills" / "zh-tw" / "SKILL.md").exists()

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
    modified = json.loads(no_status_settings.read_text(encoding="utf-8"))
    modified["statusLine"] = {"type": "command", "command": "user-custom-statusline"}
    no_status_settings.write_text(json.dumps(modified), encoding="utf-8")
    run("uninstall", empty_home)
    preserved = json.loads(no_status_settings.read_text(encoding="utf-8"))
    assert preserved["statusLine"]["command"] == "user-custom-statusline"
    assert preserved["colorScheme"] == "light"

print("PASS: Unix installer settings merge, repeat install, restore, and user-change preservation.")
