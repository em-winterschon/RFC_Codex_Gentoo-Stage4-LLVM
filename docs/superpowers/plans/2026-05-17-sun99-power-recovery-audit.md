# SUN99 Power Recovery Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the 2026-05-17 SUN99 power incident follow-up into a repeatable read-only recovery gate and an actionable UPS/PDU/ATS audit sequence.

**Architecture:** Keep the validator read-only and split hard recovery failures from audit-stage warnings. Repo checks validate the runbook, while live checks validate Hasslehoff service autostart, M70 continuity, K10 reachability, ntfy awareness, and management visibility for power endpoints.

**Tech Stack:** Bash, OpenSSH, curl, ping, optional SNMP, OpenRC service checks, Proxmox `qm`, local ntfy.

---

### Task 1: Define The Recovery Gate Contract

**Files:**
- Create: `tests/shell/test_sun99_power_recovery.sh`
- Modify: `tests/shell/run-tests.sh`

- [x] **Step 1: Write the failing test**

```bash
bash tests/shell/test_sun99_power_recovery.sh
```

Expected: FAIL with missing `scripts/validate-sun99-power-recovery.sh`.

- [x] **Step 2: Add the test to the shell suite**

Add:

```bash
bash "${SCRIPT_DIR}/test_sun99_power_recovery.sh"
```

Expected: the full shell suite can discover the new validator contract.

### Task 2: Implement The Read-Only Validator

**Files:**
- Create: `scripts/validate-sun99-power-recovery.sh`

- [x] **Step 1: Add repo-only checks**

The validator must accept:

```bash
SUN99_POWER_SKIP_LIVE=1 scripts/validate-sun99-power-recovery.sh
```

Expected: `summary: failures=0`.

- [x] **Step 2: Add live checks**

The validator must check:

```text
Hasslehoff service VM onboot/startup policy
M70 SSH, chronyd, OpenVPN, FMT2 route, and ZFS health
K10 SSH and current-year clock
local ntfy HTTP and HTTPS health
AP7901, APC network candidates, and Zyxel management reachability
```

Expected: recovered core services fail hard if broken; unresolved audit targets warn.

### Task 3: Document The Audit And Cable Plan

**Files:**
- Create: `docs/SUN99-POWER-RECOVERY.md`
- Create: `docs/wiki/Sun99-Power-Recovery.md`

- [x] **Step 1: Document resolved items**

Record Hasslehoff VM autostart, M70 chronyd/OpenVPN, K10 reachability, and ntfy local awareness as resolved recovery items.

- [x] **Step 2: Document UPS/PDU/ATS audit**

Record:

```text
CyberPower CP1500PFCRM2U USB -> M70, NUT/usbhid-ups first
APC SRT1500RMXLA/AP9641 -> network SNMP/apcupsd-compatible audit
AP7901 -> SNMP/HTTP/serial only, TLS-exempt
Blackbox -> useful later, not immediate recovery blocker
```

### Task 4: Verify And Publish

**Files:**
- No additional file changes required.

- [ ] **Step 1: Run focused repo test**

```bash
bash tests/shell/test_sun99_power_recovery.sh
```

Expected: PASS.

- [ ] **Step 2: Run live validator**

```bash
SUN99_POWER_NOTIFY=1 scripts/validate-sun99-power-recovery.sh
```

Expected: `failures=0`; warnings only for unresolved audit-stage work such as unverified SNMP arguments or CyberPower USB not yet cabled.

- [ ] **Step 3: Commit and push**

```bash
git add scripts/validate-sun99-power-recovery.sh tests/shell/test_sun99_power_recovery.sh tests/shell/run-tests.sh docs/SUN99-POWER-RECOVERY.md docs/wiki/Sun99-Power-Recovery.md docs/superpowers/plans/2026-05-17-sun99-power-recovery-audit.md
git commit -m "Add SUN99 power recovery validation gate"
git push -u origin codex/sun99-power-recovery-audit
```
