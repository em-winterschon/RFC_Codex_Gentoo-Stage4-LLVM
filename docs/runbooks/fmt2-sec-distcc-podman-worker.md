# FMT2 `sec` Distcc Podman Worker

## Purpose

`kvm-sfo200-sec-9923` is the first FMT2 R630 host promoted into immediate
compile-offload capacity while `pri` remains on the iDRAC/reimage path. The
host stays Rocky for the current cycle, but the compiler payload runs inside a
Gentoo container so M70/X12AGAIN Portage jobs do not consume Rocky compiler
state.

## Live State

- Host: `kvm-sfo200-sec-9923`
- Address: `10.200.99.23`
- Runtime host OS: Rocky Linux 10.x
- Container runtime: Podman
- Worker image: `localhost/forge-distcc-gentoo:llvm21`
- Container name: `forge-distcc-gentoo`
- Distcc port: `3632/tcp`
- Worker slots: `56`
- Allowed clients:
  - `172.16.99.0/24`
  - `10.200.99.0/24`
  - `192.168.132.0/24`

The `192.168.132.0/24` allowance is intentional: M70 reaches FMT2 through the
current OpenVPN/overlay path and was observed by `sec` as `192.168.132.2`.

## Ansible

Primary playbook:

```bash
cd gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible
ansible-playbook \
  -i inventories/local-network/hosts.yml \
  playbooks/distcc-podman-worker.yml \
  -l kvm_sfo200_sec_9923
```

The role is `distcc_podman_worker`. It renders:

- `/usr/local/sbin/forge-distcc-gentoo-start`
- `/etc/init.d/forge-distcc-gentoo` on OpenRC hosts
- `/etc/systemd/system/forge-distcc-gentoo.service` only on native systemd
  distributions such as Rocky/Debian

Repo policy remains OpenRC-first. The systemd unit exists because Rocky does not
provide an OpenRC service substrate in this deployment.

## Validation

From M70:

```bash
tmp=$(mktemp -d)
printf 'int main(void){return 0;}\n' > "${tmp}/hello.c"
DISTCC_HOSTS='10.200.99.23/4,lzo localhost/1' \
  DISTCC_VERBOSE=1 distcc clang -c "${tmp}/hello.c" -o "${tmp}/hello.o"
file "${tmp}/hello.o"
```

On `sec`:

```bash
sudo podman ps --filter name=forge-distcc-gentoo
ss -ltn sport = :3632
sudo podman exec forge-distcc-gentoo tail -20 /var/log/distcc/distccd.log
```

Expected result: M70 creates an object file and `sec` logs `COMPILE_OK`.
