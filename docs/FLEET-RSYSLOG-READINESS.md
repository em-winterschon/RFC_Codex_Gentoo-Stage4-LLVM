# Fleet Rsyslog Readiness

rsyslog is mandatory on every fleet host.

Build rsyslog with the Elasticsearch output module everywhere. This keeps hosts ready for direct collector promotion, local forwarding, and emergency observability workflows without rebuilding the package under pressure.

Gentoo base profiles install `app-admin/rsyslog`, enable the `rsyslog` OpenRC service, and require the fleet USE policy in `base-minimal-nox.yml`. RHEL-family and Debian-family hosts must provide the same operational result through their native package manager and service manager.

The readiness audit is read-only:

```bash
scripts/audit-fleet-rsyslog-readiness.sh --limit <host-or-group>
```

The audit verifies `rsyslogd`, service state, and the `omelasticsearch` module. M70 failing this audit means the host is not converged to base-minimal-nox.
