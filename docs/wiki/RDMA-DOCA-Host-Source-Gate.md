# RDMA DOCA Host Source Gate

Issue #111 uses `docs/workflows/doca-host-source-of-truth.yml` as the current
DOCA Host source-of-truth gate.

DOCA 2.9.4 LTS is the ConnectX-4 lane. Rocky Linux 10 is the primary current
DOCA host lane for BlueField-2 and ConnectX-5. The tracked DOCA Host 3.x version
is `3.3.0`, with Rocky Linux 10 kernel `6.12.0-124.8.1.el10_1.x86_64` and RPM
repository installation through `dnf`.

kernel.org 6.18 is tracked as `doca-ofed-only`; it is not the first production
RoCEv2 storage lane.

ConnectX-4 firmware must be updated before the DOCA 2.9.4 lane is evaluated.

Finished artifacts should publish under separate NASA repos:

```bash
/opt/storage/nfs/nasa/nasa-yum-repo-doca-host/doca-2.9.4/el9/x86_64/
/opt/storage/nfs/nasa/nasa-yum-repo-doca-host/doca-3.3.0/el10/x86_64/
```
