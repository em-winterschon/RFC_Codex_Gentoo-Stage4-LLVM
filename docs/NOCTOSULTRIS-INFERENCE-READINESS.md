# Noctosultris Inference Readiness

Audit timestamp: `2026-05-24T03:15:49Z`

Expected target:

```text
inf-rfc99-noctosultris-099165.rfc1918.host
172.16.99.165/24
BMC: 172.16.199.111
```

## Summary

Noctosultris is not ready for inference playbook apply. Its out-of-band BMC path
is reachable, but the intended host management address is not reachable, live
DNS records are absent, and live NetBox has no Noctosultris device or IPAM
records.

Treat Noctosultris as pending source-of-truth and host bring-up before assigning
Ollama, vLLM, SGLang, or Open WebUI workloads to it.

## Live Evidence

| Check | Result |
| --- | --- |
| requested host IP | `172.16.99.165` |
| `172.16.99.165` ICMP | no response |
| `172.16.99.165` TCP 22/80/443/623/8006 | closed or filtered |
| expected FQDN | `inf-rfc99-noctosultris-099165.rfc1918.host` |
| expected FQDN DNS | no A record returned |
| expected short CNAME | `inf-rfc99-noctosultris.rfc1918.host` |
| expected short CNAME DNS | no record returned |
| legacy-looking name | `noctosultris.rfc1918.host` resolves to `172.16.99.65` |
| `172.16.99.65` live NetBox owner | `obs-sun99-vmetrics-099065` / `obs-sun99-vmetrics.rfc1918.host` |
| BMC IP | `172.16.199.111` |
| BMC reachability | ICMP replies |
| BMC TCP ports | `22`, `443`, `623`, and `5900` open |
| live NetBox Noctosultris device query | no results |
| live NetBox `172.16.99.165` query | no results |
| live NetBox `172.16.199.111` query | no results |

## Pending Source-of-Truth Work

A root-owned worktree on M70 contains uncommitted planned Noctosultris source
records:

```text
/root/worktrees/noctosultris-dns-sync
branch: codex/noctosultris-dns-sync
base: 4137659 Add DOCA host source gate
status: dirty
```

That worktree stages:

- device name `inf_rfc99_noctosultris_099165`;
- management IP `172.16.99.165`;
- FQDN `inf-rfc99-noctosultris-099165.rfc1918.host`;
- BMC IP `172.16.199.111`;
- notes describing a Supermicro X12SPA-TF inference host with 4x NVIDIA A4000.

Those records are not live in NetBox or DNS as of this audit.

## Readiness Decision

Noctosultris is OOB-reachable but host-unready. The next safe sequence is:

1. integrate or re-create the pending NetBox/DNS source-of-truth records;
2. verify BMC identity through read-only IPMI/Redfish before any power action;
3. confirm host power state and physical management NIC cabling;
4. bring the host onto `172.16.99.165/24`;
5. verify SSH, OS, kernel, NVIDIA driver, `nvidia-smi`, container runtime, and
   GPU count;
6. only then assign it to inference host groups.

## Proposed Defaults After Bring-Up

Do not apply these until live host validation succeeds:

```yaml
inference_service_architecture: x86_64
inference_service_accelerator_profile: nvidia
inference_service_container_engine: podman
inference_service_service_manager: systemd
```

Expected backend order after validation:

1. Open WebUI as a frontend targeting already-validated model endpoints.
2. Ollama for initial local model serving.
3. vLLM for OpenAI-compatible high-throughput serving after NVIDIA driver and
   CUDA image compatibility are confirmed.
4. SGLang after vLLM-equivalent GPU/runtime validation.

## Blockers

- No live DNS for the intended Noctosultris names.
- `noctosultris.rfc1918.host` currently resolves to `172.16.99.65`, which live
  NetBox assigns to VictoriaMetrics.
- Live NetBox has no Noctosultris device, management IP, or BMC IP records.
- Host management IP `172.16.99.165` is unreachable.
- Host OS, NVIDIA driver, GPU visibility, and container runtime are unverified.

## Non-Mutation Rule

This audit performed read-only network, DNS, and NetBox checks. Do not power
cycle, re-address, or mutate BMC settings for Noctosultris without explicit
operator approval in the active session.
