from __future__ import annotations

import argparse
import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts" / "service_validator.py"

spec = importlib.util.spec_from_file_location("service_validator", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"unable to load {MODULE_PATH}")
service_validator = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = service_validator
spec.loader.exec_module(service_validator)


OPEN_XML = """<?xml version="1.0"?>
<nmaprun>
  <host>
    <ports>
      <port protocol="tcp" portid="443">
        <state state="open"/>
        <service name="https"/>
      </port>
    </ports>
  </host>
</nmaprun>
"""

OPEN_FILTERED_XML = """<?xml version="1.0"?>
<nmaprun>
  <host>
    <ports>
      <port protocol="udp" portid="514">
        <state state="open|filtered"/>
      </port>
    </ports>
  </host>
</nmaprun>
"""


class ServiceValidatorUnitTests(unittest.TestCase):
    def test_build_nmap_command_uses_tcp_connect_scan(self) -> None:
        args = argparse.Namespace(
            nmap_bin="/usr/bin/nmap",
            protocol="tcp",
            port=443,
            target="netbox-http.rfc1918.host",
        )

        command = service_validator.build_nmap_command(args)

        self.assertEqual(
            command,
            ["/usr/bin/nmap", "-sT", "-Pn", "-p", "443", "-oX", "-", "netbox-http.rfc1918.host"],
        )

    def test_build_nmap_command_uses_udp_scan(self) -> None:
        args = argparse.Namespace(
            nmap_bin="nmap",
            protocol="udp",
            port=514,
            target="syslog.rfc1918.host",
        )

        command = service_validator.build_nmap_command(args)

        self.assertEqual(
            command,
            ["nmap", "-sU", "-Pn", "-p", "514", "-oX", "-", "syslog.rfc1918.host"],
        )

    def test_extract_port_state_returns_state_and_service(self) -> None:
        state, service = service_validator.extract_port_state(OPEN_XML, "tcp", 443)

        self.assertEqual(state, "open")
        self.assertEqual(service, "https")

    def test_extract_port_state_returns_missing_for_absent_port(self) -> None:
        state, service = service_validator.extract_port_state(OPEN_XML, "tcp", 8443)

        self.assertEqual(state, "missing")
        self.assertEqual(service, "")

    def test_validate_allows_open_filtered_when_requested(self) -> None:
        args = argparse.Namespace(
            nmap_bin="nmap",
            protocol="udp",
            port=514,
            target="syslog.rfc1918.host",
            timeout=30,
            allow_open_filtered=True,
            service_name="syslog",
        )

        with mock.patch.object(service_validator, "run_nmap", return_value=OPEN_FILTERED_XML):
            result = service_validator.validate(args)

        self.assertTrue(result.success)
        self.assertEqual(result.status, "open|filtered")
        self.assertEqual(result.protocol, "udp")


if __name__ == "__main__":
    unittest.main()
