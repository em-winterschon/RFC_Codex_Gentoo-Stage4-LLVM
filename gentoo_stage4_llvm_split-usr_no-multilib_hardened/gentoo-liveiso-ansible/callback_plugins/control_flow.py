#!/usr/bin/python
# ruff: noqa: E402

DOCUMENTATION = r"""
---
name: control_flow
type: aggregate
short_description: Write a structured JSONL control-flow stream for remote install observation
requirements:
  - Configure ANSIBLE_CONTROL_FLOW_ENABLED=true to emit JSONL events during playbook execution.
options:
  control_flow_enabled:
    description: Enable structured control-flow event logging.
    type: bool
    default: false
    env:
      - name: ANSIBLE_CONTROL_FLOW_ENABLED
    ini:
      - section: control_flow_callback
        key: enabled
  control_flow_path:
    description: Explicit JSONL output path for the control-flow stream.
    type: str
    env:
      - name: ANSIBLE_CONTROL_FLOW_PATH
    ini:
      - section: control_flow_callback
        key: path
  control_flow_dir:
    description: Output directory used when no explicit path is configured.
    type: str
    default: /tmp/ansible-control-flow
    env:
      - name: ANSIBLE_CONTROL_FLOW_DIR
    ini:
      - section: control_flow_callback
        key: dir
"""

import json
import os
import socket
from datetime import datetime
from pathlib import Path

from ansible.plugins.callback import CallbackBase


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "aggregate"
    CALLBACK_NAME = "control_flow"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super().__init__()
        self.controller_host = socket.gethostname()
        self.playbook_name = "ansible-playbook"
        self.current_play = None
        self._stream = None
        self._stream_path = None

    def set_options(self, task_keys=None, var_options=None, direct=None):
        super().set_options(task_keys=task_keys, var_options=var_options, direct=direct)

    def _enabled(self):
        return self.get_option("control_flow_enabled") or bool(
            os.getenv("ANSIBLE_CONTROL_FLOW_PATH")
        )

    def _timestamp(self):
        return datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    def _ensure_stream(self):
        if self._stream is not None:
            return self._stream

        explicit_path = os.getenv(
            "ANSIBLE_CONTROL_FLOW_PATH", self.get_option("control_flow_path")
        )
        if explicit_path:
            output_path = Path(explicit_path)
        else:
            output_dir = Path(
                os.getenv("ANSIBLE_CONTROL_FLOW_DIR", self.get_option("control_flow_dir"))
            )
            playbook_stem = Path(self.playbook_name).stem or "ansible-playbook"
            timestamp = datetime.utcnow().strftime("%Y-%m%d-%H%M_%s.UTC+0000")
            output_path = output_dir / f"{playbook_stem}.{timestamp}.jsonl"

        output_path.parent.mkdir(parents=True, exist_ok=True)
        self._stream_path = output_path
        self._stream = output_path.open("a", encoding="utf-8")
        return self._stream

    def _stringify(self, value):
        if isinstance(value, (str, int, float, bool)) or value is None:
            return value
        if isinstance(value, list):
            return [self._stringify(item) for item in value]
        if isinstance(value, dict):
            return {str(key): self._stringify(item) for key, item in value.items()}
        return str(value)

    def _result_fields(self, result):
        payload = getattr(result, "_result", {}) or {}
        fields = {
            "host": result._host.get_name(),
            "task": getattr(result, "task_name", "") or getattr(result._task, "name", ""),
            "action": getattr(result._task, "action", ""),
            "changed": bool(payload.get("changed", False)),
        }
        for key in ("msg", "stdout", "stderr", "rc", "skip_reason"):
            if key in payload and payload[key] not in ("", None):
                fields[key] = self._stringify(payload[key])
        if "ansible_stats" in payload:
            fields["ansible_stats"] = self._stringify(payload["ansible_stats"])
        if "msg" in payload and isinstance(payload["msg"], dict):
            fields["checkpoint"] = self._stringify(payload["msg"])
        return fields

    def _emit(self, event, **fields):
        if not self._enabled():
            return
        stream = self._ensure_stream()
        payload = {
            "ts": self._timestamp(),
            "event": event,
            "controller_host": self.controller_host,
            "playbook": self.playbook_name,
            "play": self.current_play,
            "log_path": str(self._stream_path) if self._stream_path else None,
        }
        payload.update(
            {
                key: self._stringify(value)
                for key, value in fields.items()
                if value is not None
            }
        )
        stream.write(json.dumps(payload, sort_keys=True) + "\n")
        stream.flush()

    def v2_playbook_on_start(self, playbook):
        self.playbook_name = getattr(playbook, "_file_name", None) or "ansible-playbook"
        self._emit("playbook_start")

    def v2_playbook_on_play_start(self, play):
        self.current_play = play.get_name()
        self._emit("play_start", play=self.current_play)

    def v2_playbook_on_task_start(self, task, is_conditional):
        self._emit(
            "task_start",
            task=task.get_name(),
            action=getattr(task, "action", ""),
            is_conditional=bool(is_conditional),
        )

    def v2_runner_on_ok(self, result):
        self._emit("task_ok", **self._result_fields(result))

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._emit(
            "task_failed",
            ignore_errors=bool(ignore_errors),
            **self._result_fields(result),
        )

    def v2_runner_on_unreachable(self, result):
        self._emit("task_unreachable", **self._result_fields(result))

    def v2_runner_on_skipped(self, result):
        self._emit("task_skipped", **self._result_fields(result))

    def v2_playbook_on_stats(self, stats):
        summary = {}
        for host in sorted(stats.processed.keys()):
            summary[host] = self._stringify(stats.summarize(host))
        self._emit("playbook_stats", summary=summary)
        if self._stream is not None:
            self._stream.close()
            self._stream = None
