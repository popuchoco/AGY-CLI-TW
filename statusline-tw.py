#!/usr/bin/env python3
"""Print a Traditional Chinese Antigravity CLI status line."""

from __future__ import annotations

import json
import os
import sys
import unicodedata
from typing import Any


def char_display_width(char: str) -> int:
    """Return terminal-cell width for one code point."""
    category = unicodedata.category(char)
    if unicodedata.combining(char) or category in {"Cc", "Cf", "Mn", "Me"}:
        return 0
    return 2 if unicodedata.east_asian_width(char) in {"F", "W"} else 1


def display_width(text: str) -> int:
    """Return terminal-cell width (wide/fullwidth characters take two cells)."""
    return sum(char_display_width(char) for char in text)


def clip_cells(text: str, limit: int) -> str:
    if limit <= 0:
        return ""
    if display_width(text) <= limit:
        return text
    result: list[str] = []
    used = 0
    ellipsis = "…"
    budget = max(0, limit - char_display_width(ellipsis))
    for char in text:
        char_width = char_display_width(char)
        if used + char_width > budget:
            break
        result.append(char)
        used += char_width
    return "".join(result) + ellipsis


def wrap_fields(fields: list[str], width: int) -> list[str]:
    separator = "  │  "
    limit = max(1, width)
    lines: list[str] = []
    current = ""
    for field in fields:
        if not field:
            continue
        field = clip_cells(field, limit)
        candidate = field if not current else current + separator + field
        if current and display_width(candidate) > limit:
            lines.append(current)
            current = field
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines


def as_count(value: Any) -> int:
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError, OverflowError):
        return 0


def main() -> int:
    try:
        data = json.load(sys.stdin)
        if not isinstance(data, dict):
            raise ValueError("expected an object")
    except (json.JSONDecodeError, ValueError, TypeError):
        print("Antigravity CLI 狀態列：等待工作階段資料")
        return 0

    state_labels = {
        "initializing": "初始化中",
        "idle": "準備就緒",
        "thinking": "思考中",
        "working": "執行中",
        "tool_use": "呼叫工具中",
        "reviewing": "等待審查",
        "approval": "等待核准",
    }
    state = str(data.get("agent_state") or "idle")
    model_data = data.get("model")
    model = str(model_data.get("display_name") or "") if isinstance(model_data, dict) else ""
    vcs = data.get("vcs") if isinstance(data.get("vcs"), dict) else {}
    branch = str(vcs.get("branch") or "")
    if branch and vcs.get("dirty"):
        branch += "*"
    sandbox_data = data.get("sandbox") if isinstance(data.get("sandbox"), dict) else {}
    sandbox = "開啟" if sandbox_data.get("enabled") else "關閉"
    context = data.get("context_window") if isinstance(data.get("context_window"), dict) else {}
    try:
        percentage = max(0.0, min(100.0, float(context.get("used_percentage") or 0)))
    except (TypeError, ValueError, OverflowError):
        percentage = 0.0

    subagents = data.get("subagents")
    agent_count = len(subagents) if isinstance(subagents, list) else 0
    task_count = as_count(data.get("task_count"))
    artifact_count = as_count(data.get("artifact_count"))
    width_value = os.environ.get("COLUMNS") or data.get("terminal_width") or 100
    try:
        width = max(1, int(width_value))
    except (TypeError, ValueError, OverflowError):
        width = 100

    fields = ["狀態：" + state_labels.get(state, state)]
    if model:
        fields.append("模型：" + model)
    if branch:
        fields.append("分支：" + branch)
    fields.extend(
        [
            "上下文：{:.1f}%".format(percentage),
            "代理：{}  工作：{}".format(agent_count, task_count),
            "成品：{}".format(artifact_count),
            "沙箱：" + sandbox,
        ]
    )
    for line in wrap_fields(fields, width):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
