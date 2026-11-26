#!/usr/bin/env bash
set -eu

if ! command -v python3 >/dev/null 2>&1; then
  printf '狀態：準備就緒  │  繁體中文狀態列需要 Python 3\n'
  exit 0
fi

python3 -c '
import json, os, sys

try:
    data = json.load(sys.stdin)
except Exception:
    print("Antigravity CLI 狀態列：等待工作階段資料")
    raise SystemExit(0)

labels = {
    "initializing": "初始化中", "idle": "準備就緒", "thinking": "思考中",
    "working": "執行中", "tool_use": "呼叫工具中", "reviewing": "等待審查",
    "approval": "等待核准",
}
state = str(data.get("agent_state") or "idle")
state_text = labels.get(state, state)
model = str((data.get("model") or {}).get("display_name") or "")
vcs = data.get("vcs") or {}
branch = str(vcs.get("branch") or "")
if branch and vcs.get("dirty"):
    branch += "*"
sandbox = "開啟" if (data.get("sandbox") or {}).get("enabled") else "關閉"
context = data.get("context_window") or {}
try:
    percentage = max(0.0, min(100.0, float(context.get("used_percentage") or 0)))
except (TypeError, ValueError):
    percentage = 0.0
agents = data.get("subagents")
agent_count = len(agents) if isinstance(agents, list) else 0
tasks = int(data.get("task_count") or 0)
artifacts = int(data.get("artifact_count") or 0)
width = int(os.environ.get("COLUMNS") or data.get("terminal_width") or 100)

parts = ["狀態：" + state_text]
if model:
    parts.append("模型：" + model)
if branch:
    parts.append("分支：" + branch)
usage = "上下文：{:.1f}%".format(percentage)
work = "代理：{}  工作：{}".format(agent_count, tasks)
tail = [usage, work, "成品：{}".format(artifacts), "沙箱：" + sandbox]

if width >= 112:
    print("  │  ".join(parts + tail))
elif width >= 78:
    print("  │  ".join(parts))
    print("  │  ".join(tail))
else:
    print("狀態：{}  │  {}".format(state_text, usage))
    print("代理：{}  工作：{}  │  沙箱：{}".format(agent_count, tasks, sandbox))
'
