# CCR2004 Gateway Swap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swap the current CRS309/temporary gateway path to the rackable CCR2004 while preserving a documented emergency backout path.

**Architecture:** Keep the CCR2004 serial console on `/dev/ttyUSB2` active throughout the change. Apply the already-rendered RouterOS config in reviewed phases, starting with backups and management reachability before WAN/LAN gateway cutover. Maintain an Emergency Gateway Ethernet WAN Link from the Codex host to the AT&T gateway L2 so local serial repair remains available even if primary routing is offline.

**Tech Stack:** RouterOS `7.19.6` observed on CCR2004, Ansible render role `routeros_rfc99_gateway`, local serial `/dev/ttyUSB2`, on-host operator-private backups, Git-tracked ITIL documentation.

---

### Task 1: Pre-Change Safety Setup

**Files:**
- Read: `docs/ROUTEROS-RFC99-GATEWAY.md`
- Read: `docs/CRS309-ROUTEROS-REPLACEMENT-PLAN.md`
- Read: `/tmp/routeros-rfc99-gateway/gw_rfc99_mkccr2004_16g-rfc99-gateway.rsc`

- [ ] **Step 1: Prepare emergency physical cable**

Patch an Ethernet cable from the on-host Codex system to the AT&T gateway L2 or
to a switch port that still reaches `192.168.1.254/24` if the primary gateway is
offline.

- [ ] **Step 2: Validate emergency path**

Run:

```bash
ip -br link
ping -c 3 192.168.1.254
```

Expected: the emergency NIC is visible and `192.168.1.254` responds after either
DHCP or temporary static host addressing is applied.

- [ ] **Step 3: Open serial console**

Run:

```bash
picocom -b 115200 /dev/ttyUSB2
```

Expected: RouterOS login prompt or command prompt is visible.

### Task 2: Backup Current State

**Files:**
- Run: `scripts/backup-hasslehoff-config.sh`
- Output: `/root/operator-private/hasslehoff/backups/<timestamp>/`

- [ ] **Step 1: Backup Hasslehoff**

Run:

```bash
bash scripts/backup-hasslehoff-config.sh
```

Expected: a tarball and SHA256 file exist under
`/root/operator-private/hasslehoff/backups/<timestamp>/`.

- [ ] **Step 2: Backup CCR2004 before mutation**

From RouterOS:

```routeros
/system backup save name=pre-rfc99-ccr2004
/export file=pre-rfc99-ccr2004 hide-sensitive
```

Expected: RouterOS creates both backup and export artifacts before import.

### Task 3: Management-First CCR2004 Apply

**Files:**
- Source: `/tmp/routeros-rfc99-gateway/gw_rfc99_mkccr2004_16g-rfc99-gateway.rsc`

- [ ] **Step 1: Review generated RSC**

Confirm these lines before import:

```text
sfp-sfpplus1 is WAN
sfp-sfpplus2 is LAN trunk
ether1 through ether16 rename to ge1 through ge16
telnet/FTP/HTTP/API/WinBox disabled
SSH/HTTPS/API-SSL enabled only for management CIDRs
```

- [ ] **Step 2: Import through serial or SSH**

Use RouterOS import only after review:

```routeros
/import verbose=yes file-name=gw_rfc99_mkccr2004_16g-rfc99-gateway.rsc
```

Expected: import completes without error and serial remains responsive.

### Task 4: Validation

**Files:**
- Read: `/root/operator-private/routeros/ccr2004-16g/`

- [ ] **Step 1: Validate management services**

Run from allowed management network:

```bash
ssh admin@172.16.99.1 '/system identity print'
curl -k https://172.16.99.1/
```

Expected: SSH and HTTPS respond; telnet, FTP, HTTP, plaintext API, and WinBox do
not.

- [ ] **Step 2: Validate egress**

Run from a LAN host behind CCR2004:

```bash
ping -c 3 9.9.9.9
dig @9.9.9.9 gentoo.org
```

Expected: ICMP and DNS egress work through CCR2004 SNAT.

### Task 5: Backout

**Files:**
- RouterOS backup: `pre-rfc99-ccr2004`

- [ ] **Step 1: Trigger backout if outage exceeds tolerance**

Back out if management or internet gateway functionality cannot be restored
within the agreed window.

- [ ] **Step 2: Restore RouterOS backup**

From serial:

```routeros
/system backup load name=pre-rfc99-ccr2004.backup
/system reboot
```

Expected: CCR2004 returns to pre-change state.

- [ ] **Step 3: Use Emergency Gateway Ethernet WAN Link**

Keep the Codex host connected directly to the AT&T gateway L2 until primary
gateway routing is stable. Use `/dev/ttyUSB2` to repair CCR2004 or re-run a
known-good import.
