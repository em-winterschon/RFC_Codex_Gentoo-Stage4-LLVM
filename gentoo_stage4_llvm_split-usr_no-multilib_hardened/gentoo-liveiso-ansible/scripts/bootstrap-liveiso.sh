#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

emerge --verbose app-admin/ansible-core
ansible-galaxy collection install -r collections/requirements.yml

echo
echo "Bootstrap complete. Review inventories/examples/group_vars/install_targets.yml"
echo "and then run one of:"
echo "  ansible-playbook playbooks/install.yml -l target_system_local --connection=local"
echo "  ansible-playbook playbooks/install.yml -l target_system_remote"
