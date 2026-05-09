#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
ANSIBLE_ROOT = (
    REPO_ROOT / "gentoo_stage4_llvm_split-usr_no-multilib_hardened" / "gentoo-liveiso-ansible"
)
PROFILE_DIR = ANSIBLE_ROOT / "profile-definitions"
INVENTORY_TARGETS = [
    ANSIBLE_ROOT / "inventories" / "examples" / "group_vars" / "install_targets.yml",
    ANSIBLE_ROOT / "inventories" / "qemu-alias" / "group_vars" / "install_targets.yml",
    ANSIBLE_ROOT / "inventories" / "vm-stage4" / "group_vars" / "install_targets.yml",
]
DEFAULT_PROFILE_REFERENCE = (
    "{{ playbook_dir }}/../profile-definitions/llvm-clang-hardened-portage.yml"
)
ALLOWED_PROFILE_KEYS = {
    "metadata",
    "profile_id",
    "repository_enable",
    "make_conf_append",
    "env_files",
    "package_env_files",
    "package_use_files",
    "package_accept_keywords_files",
    "package_license_files",
    "package_mask_files",
    "package_unmask_files",
    "package_mask_symlinks",
    "kernel_config_fragment_files",
    "kernel_config",
    "kernel_config_requirements",
    "profile_parents",
    "package_atoms",
    "package_list_files",
    "openrc_services_enable",
    "modules_load_files",
    "local_user_accounts",
    "cloud_init",
    "aaa_policy_files",
    "aaa_policy",
    "freeipa_controller",
    "ipa_client",
    "freeradius_bridge",
    "rsyslog",
    "elasticsearch_cluster",
    "kibana",
    "netbox_connector",
    "netbox_essentials",
    "netbox_server",
    "zerotier",
    "telemetry",
    "binpkg_repo",
    "nexus_repo",
    "nfs_storage_client",
    "nscde_workstation",
    "haproxy_service_types",
    "service_readiness",
    "container_base_image",
    "container_app_build_defaults",
    "container_services",
    "container_app_profiles",
    "container_service_segments",
    "site_security_profile",
    "memory_storage",
    "storage_protocols",
    "jenkins_controller",
    "distcc_farm",
    "vm_redfish_emulator",
    "workstation_session_stack",
}


def load_yaml(path: Path) -> object:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def validate_profile_definition(path: Path) -> None:
    document = load_yaml(path)
    if not isinstance(document, dict):
        fail(f"{path} must contain a top-level mapping")
    profile = document.get("gentoo_profile_definition")
    if not isinstance(profile, dict):
        fail(f"{path} must define gentoo_profile_definition as a mapping")

    unknown_keys = sorted(set(profile) - ALLOWED_PROFILE_KEYS)
    if unknown_keys:
        fail(
            f"{path} contains unsupported gentoo_profile_definition keys: {', '.join(unknown_keys)}"
        )

    env_files = profile.get("env_files", {})
    if env_files is not None and not isinstance(env_files, dict):
        fail(f"{path} env_files must be a mapping")

    package_env_files = profile.get("package_env_files", {})
    if package_env_files is not None and not isinstance(package_env_files, dict):
        fail(f"{path} package_env_files must be a mapping")

    env_names = set(env_files or {})
    for fragment_name, fragment_body in (package_env_files or {}).items():
        if not isinstance(fragment_body, str):
            fail(f"{path} package_env_files[{fragment_name}] must be a string fragment")
        for line in fragment_body.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            parts = stripped.split()
            if len(parts) != 2:
                line_context = f"{path} package_env_files[{fragment_name}]"
                fail(
                    f"{line_context} line '{stripped}' must contain exactly "
                    "an atom and env filename"
                )
            env_name = parts[1]
            if env_name not in env_names:
                fail(f"{line_context} references unknown env file '{env_name}'")

    metadata = profile.get("metadata", {})
    if metadata:
        if not isinstance(metadata, dict):
            fail(f"{path} metadata must be a mapping")
        metadata_reference = metadata.get("version_pin_metadata_file")
        if metadata_reference:
            metadata_path = ANSIBLE_ROOT / metadata_reference
            if not metadata_path.is_file():
                fail(f"{path} references missing metadata file {metadata_reference}")


def validate_profile_metadata(path: Path) -> None:
    document = load_yaml(path)
    if not isinstance(document, dict):
        fail(f"{path} must contain a top-level mapping")
    portage_metadata = document.get("portage_profile_metadata")
    system_metadata = document.get("gentoo_system_profile_metadata")

    if isinstance(portage_metadata, dict):
        source_profile = portage_metadata.get("source_profile_definition")
        if not isinstance(source_profile, str) or not source_profile:
            fail(f"{path} must define source_profile_definition")
        if not (PROFILE_DIR / source_profile).is_file():
            fail(f"{path} references missing source_profile_definition {source_profile}")
        if "package_pins" not in portage_metadata:
            fail(f"{path} must define package_pins")
        return

    if isinstance(system_metadata, dict):
        if "package_pins" not in system_metadata:
            fail(f"{path} must define package_pins")
        return

    fail(f"{path} must define portage_profile_metadata or gentoo_system_profile_metadata")


def validate_inventory_defaults(path: Path) -> None:
    document = load_yaml(path)
    if not isinstance(document, dict):
        fail(f"{path} must contain a top-level mapping")
    profile_files = document.get("profile_definition_files")
    if not isinstance(profile_files, list):
        fail(f"{path} must define profile_definition_files as a list")
    if DEFAULT_PROFILE_REFERENCE not in profile_files:
        fail(f"{path} must include default profile {DEFAULT_PROFILE_REFERENCE}")
    for entry in profile_files:
        if not isinstance(entry, str):
            fail(f"{path} profile_definition_files entries must be strings")
        if entry.startswith("{{ playbook_dir }}/../profile-definitions/"):
            referenced = entry.removeprefix("{{ playbook_dir }}/../profile-definitions/")
            if not (PROFILE_DIR / referenced).is_file():
                fail(f"{path} references missing profile definition {entry}")


def main() -> int:
    for path in sorted(PROFILE_DIR.glob("*.yml")):
        if path.name.endswith(".metadata.yml"):
            validate_profile_metadata(path)
        else:
            validate_profile_definition(path)

    for inventory_path in INVENTORY_TARGETS:
        validate_inventory_defaults(inventory_path)

    print("PASS: lint_portage_profiles.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
