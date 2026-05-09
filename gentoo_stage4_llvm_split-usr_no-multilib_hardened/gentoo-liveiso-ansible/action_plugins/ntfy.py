#!/usr/bin/python
# ruff: noqa: E402

DOCUMENTATION = r"""
---
module: ntfy
short_description: Send controller-side notifications to ntfy
description:
  - Send push notifications to an ntfy-compatible HTTP endpoint from the Ansible controller.
options:
  msg:
    description:
      - Notification body text.
    required: true
    type: str
  title:
    description:
      - Notification title.
    type: str
  topic:
    description:
      - ntfy topic or channel. Falls back to C(topic) in task vars or environment settings.
    type: str
  url:
    description:
      - ntfy base URL. Configure this explicitly; there is no public fallback.
    type: str
  state:
    description:
      - Logical notification state.
    type: str
    default: info
  severity:
    description:
      - Syslog-style severity name.
    type: str
  attrs:
    description:
      - Additional ntfy JSON attributes such as C(tags), C(priority), or C(actions).
    type: dict
author:
  - Jan-Piet Mens (@jpmens)
  - Codex adaptation
"""

import json
import os
import socket
from datetime import datetime

from ansible.errors import AnsibleActionFail
from ansible.module_utils._text import to_text
from ansible.module_utils.six import string_types
from ansible.module_utils.urls import open_url
from ansible.plugins.action import ActionBase

SYSLOG_SEVERITIES = {
    "emerg": 0,
    "alert": 1,
    "crit": 2,
    "err": 3,
    "error": 3,
    "warning": 4,
    "notice": 5,
    "info": 6,
    "debug": 7,
}
NTFY_PRIORITY_MAP = {0: "5", 1: "5", 2: "4", 3: "4", 4: "3", 5: "3", 6: "2", 7: "1"}


def _state_topic(state, explicit_topic):
    if explicit_topic:
        return explicit_topic
    env_key = f"ANSIBLE_NTFY_TOPIC_{state.strip().upper().replace('-', '_')}"
    return os.getenv(env_key, os.getenv("ANSIBLE_NTFY_TOPIC", os.getenv("NTFY_TOPIC", "")))


def _severity_value(state, explicit):
    if explicit:
        key = explicit.lower()
        if key not in SYSLOG_SEVERITIES:
            raise ValueError(f"Unsupported severity: {explicit}")
        return SYSLOG_SEVERITIES[key]
    return {
        "success": SYSLOG_SEVERITIES["notice"],
        "fail": SYSLOG_SEVERITIES["err"],
        "error": SYSLOG_SEVERITIES["err"],
        "warning": SYSLOG_SEVERITIES["warning"],
    }.get(state, SYSLOG_SEVERITIES["info"])


def _syslog_body(app_name, state, severity, message):
    facility = 16
    pri = facility * 8 + severity
    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    hostname = socket.gethostname()
    sanitized = " ".join(message.splitlines()).replace('"', "'")
    return (
        f"<{pri}>1 {timestamp} {hostname} {app_name} - - - "
        f'state="{state}" severity_code="{severity}" message="{sanitized}"'
    )


class ActionModule(ActionBase):
    BYPASS_HOST_LOOP = False
    TRANSFERS_FILES = False

    def run(self, tmp=None, task_vars=None):
        if task_vars is None:
            task_vars = {}

        result = super().run(tmp, task_vars)
        del tmp

        msg = self._task.args.get("msg")
        if not isinstance(msg, string_types) or not msg:
            raise AnsibleActionFail("msg must be a non-empty string")

        url = self._task.args.get("url", os.getenv("ANSIBLE_NTFY_URL", os.getenv("NTFY_URL", "")))
        if not url:
            raise AnsibleActionFail("No ntfy URL configured")
        topic = _state_topic(
            self._task.args.get("state", "info"),
            self._task.args.get("topic", task_vars.get("topic")),
        )
        if not topic:
            raise AnsibleActionFail("No ntfy topic configured")

        state = self._task.args.get("state", "info").lower()
        severity = _severity_value(state, self._task.args.get("severity"))
        attrs = self._task.args.get("attrs", {}) or {}
        data = {
            "topic": topic,
            "title": self._task.args.get("title", f"Ansible {state}"),
            "message": _syslog_body("ansible-ntfy", state, severity, msg),
            "priority": attrs.get("priority", NTFY_PRIORITY_MAP[severity]),
            "tags": attrs.get("tags", ["ansible", state]),
        }
        for key, value in attrs.items():
            data[key] = value

        headers = {"Content-Type": "application/json", "User-Agent": "Ansible/ntfy"}
        token = os.getenv("ANSIBLE_NTFY_TOKEN", os.getenv("NTFY_TOKEN"))
        if token:
            headers["Authorization"] = f"Bearer {token}"

        response = open_url(
            url, data=json.dumps(data), method="POST", headers=headers, http_agent="Ansible/ntfy"
        )
        response_data = json.loads(to_text(response.read()))

        result.update(
            {
                "changed": False,
                "failed": False,
                "url": url,
                "topic": topic,
            }
        )
        result.update(response_data)
        return result
