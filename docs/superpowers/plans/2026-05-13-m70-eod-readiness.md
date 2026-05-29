# M70 EOD Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `admin-sun99-forge-099070.rfc1918.host` ready to replace X12AGAIN as Forge's automation-admin host before X12AGAIN reimage work starts.

**Architecture:** Keep the current SATADOM ESP iPXE chainloader as the boot entry, but stop relying on the shared K10 live-rootfs identity. Add an M70-specific profile overlay, enroll it into FreeIPA with a host OTP, install or persist the automation-admin root, then restore Forge continuity data and run E2ET gates.

**Tech Stack:** Gentoo LOX/Stage5, OpenRC, dracut live/netboot, iPXE, FreeIPA/SSSD/Kerberos, Ansible, ZFS, GitHub CLI, APC PDU SNMPv3, Supermicro IPMI SoL.

---

### Task 1: Preserve Current Recovery Evidence

**Files:**
- Modify: `docs/M70-FORGE-AUTOMATION-ADMIN.md`
- Modify: `docs/wiki/M70-Forge-Automation-Admin.md`
- Test: `tests/shell/test_m70_forge_admin_provisioning.sh`

- [ ] **Step 1: Capture live state from the M70**

```bash
ssh -o BatchMode=yes root@172.16.99.70 \
  'hostname; ip -br addr; ip route; rc-service dhcpcd status || true; rc-service sssd status || true; cat /etc/conf.d/hostname'
```

Expected: `netboot0` has `172.16.99.70/24`, `dhcpcd` is not a reliable service state, `sssd` is stopped until enrollment exists, and hostname still references the K10 image.

- [ ] **Step 2: Record the evidence in docs**

Add a dated note that the host was not SSH-filtering; it was not answering ARP until PDU outlet 4 rebooted it. Include that the root cause is the non-durable K10-derived live rootfs identity/network profile.

- [ ] **Step 3: Verify docs tests**

```bash
bash tests/shell/test_m70_forge_admin_provisioning.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add docs/M70-FORGE-AUTOMATION-ADMIN.md docs/wiki/M70-Forge-Automation-Admin.md tests/shell/test_m70_forge_admin_provisioning.sh
git commit -m "docs: record M70 recovery evidence"
```

### Task 2: Render M70-Specific Boot Identity

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/metal-forge-automation-admin.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-service-atoms/stage5-role-service-atoms.yml`
- Modify: `tests/shell/test_m70_forge_admin_provisioning.sh`

- [ ] **Step 1: Add an M70 firstboot file payload**

Ensure the profile writes these files into the installed root or M70-specific overlay:

```text
/etc/conf.d/hostname:
hostname="admin-sun99-forge-099070"

/etc/hosts:
127.0.0.1 localhost
172.16.99.70 admin-sun99-forge-099070.rfc1918.host admin-sun99-forge-099070 admin-sun99-forge
172.16.99.63 ipa01.rfc1918.host ipa01

/etc/conf.d/net:
config_netboot0="172.16.99.70/24"
routes_netboot0="default via 172.16.99.1"
dns_servers_netboot0="9.9.9.9 8.8.8.8 172.16.99.63"
```

- [ ] **Step 2: Disable unmanaged DHCP on this static management role**

Ensure the installed profile does not start `dhcpcd` on `netboot0`. The required OpenRC services are `hostname`, `net.netboot0`, and `sshd`; `dhcpcd` is not required for this static management node.

- [ ] **Step 3: Add shell assertions**

Update `tests/shell/test_m70_forge_admin_provisioning.sh` to assert the profile contains `admin-sun99-forge-099070`, `config_netboot0`, `routes_netboot0`, and does not require DHCP for the management interface.

- [ ] **Step 4: Run tests**

```bash
bash tests/shell/test_m70_forge_admin_provisioning.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-definitions/metal-forge-automation-admin.yml \
        gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/profile-service-atoms/stage5-role-service-atoms.yml \
        tests/shell/test_m70_forge_admin_provisioning.sh
git commit -m "feat: render static M70 automation-admin identity"
```

### Task 3: Create FreeIPA Host Principal and OTP

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/host_vars/admin_sun99_forge_099070.yml`
- Test: `tests/shell/test_live_ipa_client_enrollment.sh`

- [ ] **Step 1: Create the host entry with admin privilege**

Run on `svc_identity_ipa01` with an admin Kerberos ticket:

```bash
ipa host-add admin-sun99-forge-099070.rfc1918.host \
  --ip-address=172.16.99.70 \
  --description="M70 Forge automation-admin host" \
  --force
ipa host-mod admin-sun99-forge-099070.rfc1918.host --random
```

Expected: FreeIPA returns a random host password or OTP. Put it into the secure firstboot secret path or Ansible Vault; do not commit it in plaintext.

- [ ] **Step 2: Enable one-time enrollment in host vars**

Set only the non-secret switches in `host_vars/admin_sun99_forge_099070.yml`:

```yaml
freeipa_client_apply_required: true
secure_firstboot_enrollment_enabled: true
```

The OTP itself must be injected from Vault or an age/tang/clevis protected bundle at runtime.

- [ ] **Step 3: Run enrollment validation**

```bash
ansible-playbook \
  -i gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/hosts.yml \
  gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/playbooks/ipa-client-live-apply.yml \
  --limit admin_sun99_forge_099070
```

Expected: `/etc/sssd/sssd.conf` exists, `sssd` starts, `getent passwd codex-admin` resolves, and `sss_ssh_authorizedkeys codex-admin` returns a key.

- [ ] **Step 4: Run tests**

```bash
bash tests/shell/test_live_ipa_client_enrollment.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/local-network/host_vars/admin_sun99_forge_099070.yml
git commit -m "feat: enable M70 FreeIPA enrollment gates"
```

### Task 4: Install Persistent Automation-Admin Root

**Files:**
- Modify: `docs/M70-FORGE-AUTOMATION-ADMIN.md`
- Create: `docs/runbooks/m70-automation-admin-install.md`
- Test: `tests/shell/test_m70_forge_admin_provisioning.sh`

- [ ] **Step 1: Confirm storage target**

Use the SATADOM ESP for iPXE boot only. Prefer the two NVMe devices as a mirrored ZFS root/data pool for the automation-admin host if both are healthy:

```bash
ssh root@172.16.99.70 'lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE; zpool status || true; nvme list || true'
```

Expected: `sda` is the 32GB SATADOM; `nvme0n1` and `nvme1n1` are available for the installed root/data layout.

- [ ] **Step 2: Run the install workflow**

Run the existing Stage5 install workflow for `metal-forge-automation-admin` after confirming the exact disk targets. The workflow must not overwrite the SATADOM ESP chainloader unless a new iPXE binary is intentionally staged.

- [ ] **Step 3: Reboot and validate persistent identity**

```bash
ssh root@172.16.99.70 'hostname -f; mount; ip -br addr; rc-service dhcpcd status || true; rc-service sssd status'
```

Expected: hostname is `admin-sun99-forge-099070.rfc1918.host`, management networking is static, `dhcpcd` is absent or stopped, and `sssd` is started.

- [ ] **Step 4: Commit runbook**

```bash
git add docs/M70-FORGE-AUTOMATION-ADMIN.md docs/runbooks/m70-automation-admin-install.md tests/shell/test_m70_forge_admin_provisioning.sh
git commit -m "docs: add M70 automation-admin install runbook"
```

### Task 5: Restore Forge Continuity and Run E2ET

**Files:**
- Modify: `docs/M70-FORGE-AUTOMATION-ADMIN.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Test: `tests/shell/run-tests.sh`

- [ ] **Step 1: Restore required state paths**

Restore or sync only the approved continuity paths:

```bash
rsync -aHAX --numeric-ids /backup/x12again/root/ root@172.16.99.70:/root/
rsync -aHAX --numeric-ids /backup/x12again/opt/ root@172.16.99.70:/opt/
```

Expected: Forge keys, vault files, repo clones, SoL wrappers, and operator-private backup tooling exist on the M70.

- [ ] **Step 2: Validate remote automation dependencies**

```bash
ssh root@172.16.99.70 'ansible --version; ansible-vault --version; git --version; gh --version; ipmitool -V'
ssh root@172.16.99.70 '/root/.ssh/codex.d/ipmi.d/ipmi-prinzessin -h 2>&1 | head || true'
```

Expected: tools are installed and X12AGAIN SoL wrapper is present.

- [ ] **Step 3: Validate non-root AAA account**

```bash
ssh root@172.16.99.70 'getent passwd codex-admin; sss_ssh_authorizedkeys codex-admin >/tmp/codex-admin.keys; test -s /tmp/codex-admin.keys'
ssh -o BatchMode=yes codex-admin@admin-sun99-forge-099070.rfc1918.host 'id; hostname -f'
```

Expected: `codex-admin` logs in using centralized SSH keys and returns the M70 hostname.

- [ ] **Step 4: Run local shell suite**

```bash
bash tests/shell/run-tests.sh
```

Expected: PASS.

- [ ] **Step 5: Commit and push**

```bash
git add docs/M70-FORGE-AUTOMATION-ADMIN.md docs/ROADMAP-AND-TODO.md
git commit -m "docs: mark M70 automation-admin E2ET gates"
git push origin codex/m70-forge-admin-provisioning
```
