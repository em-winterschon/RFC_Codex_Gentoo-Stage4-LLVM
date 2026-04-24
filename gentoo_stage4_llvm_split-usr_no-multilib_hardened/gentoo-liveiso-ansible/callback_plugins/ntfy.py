#!/usr/bin/python

DOCUMENTATION = r"""
---
name: ntfy
type: aggregate
short_description: Send playbook lifecycle notifications to ntfy
requirements:
  - Configure ANSIBLE_NTFY_ENABLED=true and ANSIBLE_NTFY_TOPIC or state-specific topics.
options:
  ntfy_enabled:
    description: Enable controller-side ntfy callback notifications.
    type: bool
    default: false
    env:
      - name: ANSIBLE_NTFY_ENABLED
    ini:
      - section: ntfy_callback
        key: enabled
  ntfy_url:
    description: Base ntfy URL.
    type: str
    default: https://ntfy.sh
    env:
      - name: ANSIBLE_NTFY_URL
    ini:
      - section: ntfy_callback
        key: url
  ntfy_topic:
    description: Default ntfy topic.
    type: str
    env:
      - name: ANSIBLE_NTFY_TOPIC
    ini:
      - section: ntfy_callback
        key: topic
"""

import json
import os
import socket
from datetime import datetime

from ansible.module_utils.urls import open_url
from ansible.plugins.callback import CallbackBase

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


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "aggregate"
    CALLBACK_NAME = "ntfy"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super(CallbackModule, self).__init__()
        self.playbook_name = "ansible-playbook"
        self.failures = []
        self.unreachable = []
        self.warnings = []

    def set_options(self, task_keys=None, var_options=None, direct=None):
        super(CallbackModule, self).set_options(
            task_keys=task_keys, var_options=var_options, direct=direct
        )

    def _enabled(self):
        enabled = self.get_option("ntfy_enabled")
        return enabled or bool(self._topic_for_state("info"))

    def _url(self):
        return os.getenv("ANSIBLE_NTFY_URL", os.getenv("NTFY_URL", self.get_option("ntfy_url")))

    def _topic_for_state(self, state):
        env_key = "ANSIBLE_NTFY_TOPIC_%s" % state.strip().upper().replace("-", "_")
        return os.getenv(
            env_key,
            os.getenv(
                "ANSIBLE_NTFY_TOPIC", os.getenv("NTFY_TOPIC", self.get_option("ntfy_topic") or "")
            ),
        )

    def _severity_value(self, state):
        return {
            "success": SYSLOG_SEVERITIES["notice"],
            "fail": SYSLOG_SEVERITIES["err"],
            "error": SYSLOG_SEVERITIES["err"],
            "warning": SYSLOG_SEVERITIES["warning"],
            "start": SYSLOG_SEVERITIES["info"],
        }.get(state, SYSLOG_SEVERITIES["info"])

    def _syslog_body(self, state, severity, message):
        pri = 16 * 8 + severity
        timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        hostname = socket.gethostname()
        sanitized = " ".join(str(message).splitlines()).replace('"', "'")
        return '<%d>1 %s %s ansible-callback - - - state="%s" severity_code="%d" message="%s"' % (
            pri,
            timestamp,
            hostname,
            state,
            severity,
            sanitized,
        )

    def _notify(self, state, title, message, tags=None):
        if not self._enabled():
            return
        topic = self._topic_for_state(state)
        if not topic:
            return
        severity = self._severity_value(state)
        payload = {
            "topic": topic,
            "title": title,
            "message": self._syslog_body(state, severity, message),
            "priority": NTFY_PRIORITY_MAP[severity],
            "tags": tags or ["ansible", state],
        }
        headers = {"Content-Type": "application/json", "User-Agent": "Ansible/ntfy-callback"}
        token = os.getenv("ANSIBLE_NTFY_TOKEN", os.getenv("NTFY_TOKEN"))
        if token:
            headers["Authorization"] = "Bearer %s" % token
        try:
            open_url(
                self._url(),
                data=json.dumps(payload),
                method="POST",
                headers=headers,
                http_agent="Ansible/ntfy-callback",
            ).read()
        except Exception as exc:  # noqa: BLE001
            self._display.warning("ntfy callback send failed: %s" % exc)

    def v2_playbook_on_start(self, playbook):
        self.playbook_name = getattr(playbook, "_file_name", None) or "ansible-playbook"
        self._notify(
            "start",
            "Ansible started: %s" % self.playbook_name,
            "playbook=%s" % self.playbook_name,
            ["ansible", "start"],
        )

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self.failures.append(result)
        task_name = result.task_name or "unnamed-task"
        host = result._host.get_name()
        self._notify(
            "fail",
            "Ansible task failed: %s" % task_name,
            "playbook=%s host=%s task=%s ignore_errors=%s"
            % (self.playbook_name, host, task_name, ignore_errors),
            ["ansible", "failure"],
        )

    def v2_runner_on_unreachable(self, result):
        self.unreachable.append(result)
        host = result._host.get_name()
        self._notify(
            "error",
            "Ansible host unreachable: %s" % host,
            "playbook=%s host=%s" % (self.playbook_name, host),
            ["ansible", "unreachable"],
        )

    def v2_on_warning(self, msg, *args, **kwargs):
        self.warnings.append(msg)
        self._notify(
            "warning",
            "Ansible warning: %s" % self.playbook_name,
            "playbook=%s warning=%s" % (self.playbook_name, msg),
            ["ansible", "warning"],
        )

    def v2_playbook_on_stats(self, stats):
        hosts = sorted(stats.processed.keys())
        summary = []
        has_failures = False
        for host in hosts:
            s = stats.summarize(host)
            summary.append(
                "%s ok=%s changed=%s failed=%s unreachable=%s skipped=%s rescued=%s ignored=%s"
                % (
                    host,
                    s.get("ok", 0),
                    s.get("changed", 0),
                    s.get("failures", 0),
                    s.get("unreachable", 0),
                    s.get("skipped", 0),
                    s.get("rescued", 0),
                    s.get("ignored", 0),
                )
            )
            if s.get("failures", 0) or s.get("unreachable", 0):
                has_failures = True

        state = "fail" if has_failures else "success"
        title = "Ansible %s: %s" % (state, self.playbook_name)
        message = 'playbook=%s hosts="%s"' % (self.playbook_name, "; ".join(summary))
        self._notify(state, title, message, ["ansible", state])
