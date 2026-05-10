# CCR2004 Service VIP Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Elasticsearch service VIP front door into CCR2004-managed RouterOS configuration while keeping HAProxy/nginx on the Stage4 container-services VM.

**Architecture:** CCR2004 owns the SUN99 service VIP address and DNATs only the explicit published service port to the existing container-services HAProxy listener. The former temporary static routes for Path-B Elasticsearch endpoints via X12AGAIN were removed after VLAN1098-backed Elasticsearch moved to Hasslehoff.

**Tech Stack:** RouterOS RSC rendered by Ansible, HAProxy container-service profile, NetBox/IPAM inventory intake, shell render tests.

---

### Task 1: Add Failing RouterOS Render Coverage

**Files:**
- Modify: `tests/shell/test_routeros_rfc99_gateway_role.sh`

- [ ] **Step 1: Add assertions for CCR2004 service VIP, static routes, DNAT, and RouterOS 7.22.3 artifact metadata.**

Expected assertions:

```bash
assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_rfc99_gateway/defaults/main.yml" "routeros_rfc99_gateway_service_vips: []"
assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_rfc99_gateway/defaults/main.yml" "routeros_rfc99_gateway_static_routes: []"
assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_rfc99_gateway/defaults/main.yml" "routeros_rfc99_gateway_dst_nat_rules: []"
assert_file_contains "${ANSIBLE_ROOT}/roles/routeros_rfc99_gateway/defaults/main.yml" "routeros_rfc99_gateway_target_version: 7.22.3"
assert_file_contains "${rsc}" '/ip address add address=172.16.99.92/32 interface=br-lan comment="RFC99 service VIP obs-sun99-esvip-099092"'
if grep -q 'X12AGAIN transit' "${rsc}"; then
  fail "rendered RouterOS config still contains obsolete X12AGAIN transit routes"
fi
assert_file_contains "${rsc}" '/ip firewall nat add chain=dstnat action=dst-nat protocol=tcp dst-address=172.16.99.92 dst-port=9200 to-addresses=172.16.99.89 to-ports=9200 comment="RFC99 service dstnat obs-sun99-esvip-099092 elasticsearch to container-services HAProxy"'
assert_file_contains "${manifest}" '"targetVersion": "7.22.3"'
assert_file_contains "${manifest}" '"serviceVips":'
assert_file_contains "${manifest}" '"dstNatRules":'
```

- [ ] **Step 2: Run the focused test and verify it fails.**

Run:

```bash
bash tests/shell/test_routeros_rfc99_gateway_role.sh
```

Expected: `FAIL` because the RouterOS role does not yet expose the new variables or render the requested RSC.

### Task 2: Implement CCR2004 VIP and DNAT Rendering

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/routeros_rfc99_gateway/defaults/main.yml`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/routeros_rfc99_gateway/templates/routeros-rfc99-gateway.rsc.j2`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/roles/routeros_rfc99_gateway/templates/routeros-rfc99-gateway-manifest.json.j2`
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventories/examples/group_vars/routeros_rfc99_gateways.yml`

- [ ] **Step 1: Add default render-only variables.**

Add:

```yaml
routeros_rfc99_gateway_target_version: 7.22.3
routeros_rfc99_gateway_local_artifact_root: /opt/routeros/mikrotik-official
routeros_rfc99_gateway_routeros_package_path: /opt/routeros/mikrotik-official/os-systems/arm64/routeros-7.22.3-arm64.npk
routeros_rfc99_gateway_container_package_path: /opt/routeros/mikrotik-official/containers/arm64/container-7.22.3-arm64.npk
routeros_rfc99_gateway_service_vips: []
routeros_rfc99_gateway_static_routes: []
routeros_rfc99_gateway_dst_nat_rules: []
```

- [ ] **Step 2: Render managed service VIP addresses after normal L3 addresses.**

Template shape:

```jinja
/ip address remove [find comment~"RFC99 service VIP"]
{% for service_vip in routeros_rfc99_gateway_service_vips %}
/ip address add address={{ service_vip.address }} interface={{ service_vip.interface | default(routeros_rfc99_gateway_lan_bridge) }} comment="RFC99 service VIP {{ service_vip.name }}"
{% endfor %}
```

- [ ] **Step 3: Render static routes after WAN setup.**

Template shape:

```jinja
/ip route remove [find comment~"RFC99 static route"]
{% for static_route in routeros_rfc99_gateway_static_routes %}
/ip route add dst-address={{ static_route.dst_address }} gateway={{ static_route.gateway }} distance={{ static_route.distance | default(1) }} comment="RFC99 static route {{ static_route.comment }}"
{% endfor %}
```

- [ ] **Step 4: Render DNAT rules before generic WAN SNAT.**

Template shape:

```jinja
/ip firewall nat remove [find comment~"RFC99 service dstnat"]
{% for dnat_rule in routeros_rfc99_gateway_dst_nat_rules %}
/ip firewall nat add chain=dstnat action=dst-nat protocol={{ dnat_rule.protocol | default('tcp') }} dst-address={{ dnat_rule.dst_address }} dst-port={{ dnat_rule.dst_port }} to-addresses={{ dnat_rule.to_address }} to-ports={{ dnat_rule.to_port | default(dnat_rule.dst_port) }} comment="RFC99 service dstnat {{ dnat_rule.comment }}"
{% endfor %}
```

- [ ] **Step 5: Add example inventory values for the SUN99 Elasticsearch VIP.**

Use:

```yaml
routeros_rfc99_gateway_service_vips:
  - name: obs-sun99-esvip-099092
    address: 172.16.99.92/32
    interface: br-lan
routeros_rfc99_gateway_static_routes:
  []
routeros_rfc99_gateway_dst_nat_rules:
  - name: obs-sun99-esvip-099092-elasticsearch
    protocol: tcp
    dst_address: 172.16.99.92
    dst_port: 9200
    to_address: 172.16.99.89
    to_port: 9200
    comment: obs-sun99-esvip-099092 elasticsearch to container-services HAProxy
```

- [ ] **Step 6: Run the focused test and verify it passes.**

Run:

```bash
bash tests/shell/test_routeros_rfc99_gateway_role.sh
```

Expected: `PASS: test_routeros_rfc99_gateway_role.sh`

### Task 3: Track VIP in Inventory and Docs

**Files:**
- Modify: `gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/inventory-intake/sites/local-rfc1918-lab.yml`
- Modify: `docs/ROUTEROS-RFC99-GATEWAY.md`
- Modify: `docs/OBSERVABILITY-ACCESS.md`
- Modify: `docs/ROADMAP-AND-TODO.md`
- Modify: matching `docs/wiki/*` mirrors
- Modify: `docs/CHANGELOG.md`

- [ ] **Step 1: Add service VIP inventory.**

Add `obs-sun99-esvip-099092` at `172.16.99.92` with TCP `9200`, owner `observability`, and alias `obs-sun99-esvip.rfc1918.host`.

- [ ] **Step 2: Document the operational intent.**

State that CCR2004 owns the SUN99 service VIP and DNATs to `svc-container-services-safe-move-01:9200`; HAProxy/nginx containers remain on the VM; RouterOS container support is deferred to a lab-only experiment.

- [ ] **Step 3: Record RouterOS 7.22.3 local artifacts.**

Document `/opt/routeros/mikrotik-official` as the on-host artifact root and call out the `arm64` RouterOS and container packages.

- [ ] **Step 4: Run inventory/docs validation.**

Run:

```bash
bash tests/shell/run-tests.sh
```

Expected: all shell tests pass.

### Task 4: Commit

**Files:**
- All changed files from Tasks 1-3.

- [ ] **Step 1: Review diff.**

Run:

```bash
git diff --stat
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 2: Commit.**

Run:

```bash
git add docs gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible tests/shell/test_routeros_rfc99_gateway_role.sh
git commit -m "Add CCR2004 service VIP routing"
```

Expected: commit created on the active branch.
