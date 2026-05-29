# QNAP MCP Assistant (`qmcp`) Assessment

Observed on `NAS7F281B-QNAP` / `172.16.254.28` on 2026-05-29.  This is a
non-critical-path assessment for operator convenience only; it must not become a
hard dependency for FreeIPA, NFS, Slurm, DNS, or host enrollment workflows.

## Installed component map

`/etc/config/qpkg.conf` reports:

| Field | Observed value |
| --- | --- |
| QPKG name | `qmcp` |
| Display name | `MCP Assistant` |
| Version | `0.10.0.797` |
| Install path | `/share/CACHEDEV1_DATA/.qpkg/qmcp` |
| Web UI | `/qmcp/` |
| Shell wrapper | `/share/CACHEDEV1_DATA/.qpkg/qmcp/qmcp.sh` |
| Runtime socket | `/var/run/qmcp.sock` |
| Health endpoint | `GET /api/_/health` over the Unix socket |

The QNAP wrapper writes QTS Apache proxy config for `/qmcp/` and `/qmcp/api/`:

```apache
ProxyPass        /qmcp/api/ unix:/var/run/qmcp.sock|http://127.0.0.1:10007/api/
ProxyPassReverse /qmcp/api/ unix:/var/run/qmcp.sock|http://127.0.0.1:10007/api/
ProxyPass        /qmcp/     unix:/var/run/qmcp.sock|http://127.0.0.1:10007/
ProxyPassReverse /qmcp/     unix:/var/run/qmcp.sock|http://127.0.0.1:10007/
```

## Command functions

### QPKG lifecycle wrapper

`qmcp.sh` supports:

| Command | Function chain |
| --- | --- |
| `start` | `link_world` -> `web_proxy_start` -> `nc_register` -> `daemon_start` |
| `stop` | `daemon_stop` -> `nc_unregister` -> `web_proxy_stop` -> `unlink_world` |
| `restart` | `stop`, sleep, `start` |
| `status` | QTS QPKG status query |

`daemon_start` removes stale pid/socket files, starts `./qmcp daemon --daemonize
--loglevel info`, then probes `GET /api/_/health` through `/var/run/qmcp.sock`.

### Native binary commands

`./qmcp --help` reports:

| Command | Purpose |
| --- | --- |
| `daemon` | Run the backend daemon |
| `env` | Print runtime environment information |
| `version` | Print version |
| `completion` | Generate shell completion |

Global flags:

| Flag | Default | Notes |
| --- | --- | --- |
| `--listen` | `/var/run/qmcp.sock` | Unix-domain socket address. |
| `--loglevel` | `error` | Wrapper starts daemon with `info`. |
| `--runtime` | `production` | `production` or `development`. |
| `daemon --daemonize` | false | Background daemon mode. |

## API option map

The UI assets expose the following REST API calls.  Direct unauthenticated
requests to `/api/v1/*` return `401 unauthenticated: unknown token`; the health
endpoint is unauthenticated.

| Path | Method(s) | Parameters / body | Observed purpose |
| --- | --- | --- | --- |
| `/api/_/health` | `GET` | none | Daemon health; returns `{"status":"ok"}`. |
| `/api/v1/system` | `GET` | auth token/session | System metadata used by UI. |
| `/api/v1/settings` | `GET`, `PUT` | settings JSON | Service settings: HTTP/HTTPS enablement, ports, localhost-only flags. |
| `/api/v1/settings/server-certificate` | `PUT` | multipart `certificate`, `key` | Replace service TLS cert/key. |
| `/api/v1/statistics` | `GET` | auth token/session | Provider/tool usage counters. |
| `/api/v1/certificates` | `GET`, `POST` | certificate/profile JSON on `POST` | List/create MCP agent credentials. |
| `/api/v1/certificates/{name}` | `GET`, `PUT`, `DELETE` | JSON on `PUT`; query `os`, `arch`, `server_url` for binary/blob download path | Get/update/delete/download a certificate or agent bundle. |
| `/api/v1/nas/users` | `GET` | auth token/session | List NAS users for certificate ownership/selection UI. |
| `/api/v1/logs` | `GET` | query params; `download=true` for blob export | List or download QMCP logs. |
| `/api/v1/diagnostic-report` | `GET` | auth token/session | Download diagnostic bundle. |
| `/api/v1/management/resource-changes` | `GET` | `count`, timestamp-like poll params inferred from UI | UI event polling; direct probe returned 404 in this environment, so treat as unconfirmed. |
| `/nc/api/policy?owner=A284&sid=${NAS_SID}` | `GET` | QTS `NAS_SID` cookie/session | QTS policy lookup; base URL is QTS origin, not the QMCP socket proxy. |

Known UI settings fields:

| Field | Meaning |
| --- | --- |
| `enableHttp`, `enableHttps` | Enable API/UI listener modes. |
| `httpPort`, `httpsPort` | Listener ports. |
| `httpLocalhostOnly`, `httpsLocalhostOnly` | Bind exposure controls. |
| `certCommonName`, `certNotAfter` | Current certificate display metadata. |

Known API error-code mappings in UI:

| Code | UI label |
| --- | --- |
| `10000` | `ErrCredentialNameDuplicate` |
| `10001` | `ErrHTTPPortInUsed` |
| `10002` | `ErrHTTPSPortInUsed` |
| `10003` | `ErrSettingPortInvalid` |

## MCP provider/tool map

`statistics.json` lists providers and tool counts:

| Provider | Count | Tools observed from UI labels |
| --- | ---: | --- |
| `sharedfolder` | 4 | `list_shared_folder`, `get_shared_folder`, `create_shared_folder`, `delete_shared_folder`, `update_shared_folder_permission` is also present in UI labels and may be grouped here or exposed conditionally. |
| `usergroup` | 9 | `list_users`, `get_user`, `create_user`, `delete_user`, `list_groups`, `get_group`, `create_group`, `delete_group`, `update_group`. |
| `nasstatus` | 7 | `get_system_info`, `list_logs`, `list_qpkgs`, `list_storages`, `query_load_avg`, `query_top_processes`, `get_qvr_logs`. |
| `filestation` | 3 | `list_files`, `create_folder`, `generate_share_link`. |
| `qsirch` | 1 | `advanced_search` / `search_files` labels are present; verify exact tool name before automation. |

## Command workflows

### Health probe

```bash
ssh qnap 'curl --unix-socket /var/run/qmcp.sock -sS http://qmcp/api/_/health'
```

Expected:

```json
{"status":"ok"}
```

### Read-only inventory scrape

Use only for operator dashboards or drift hints:

1. Acquire an explicit QTS/QMCP token/session through the UI or approved
   operator secret path.
2. Query `GET /api/v1/statistics`, `GET /api/v1/system`, and log endpoints.
3. Persist only redacted summaries in Git or tickets.
4. Never treat QMCP state as authoritative for identity, DNS, NetBox, or FreeIPA.

### NAS admin assist

Candidate non-critical operations:

1. List shared folders before planned NFS/SMB changes.
2. Inspect NAS storage status and high-load process lists before heavy rsync/NFS
   migration windows.
3. Generate ad-hoc operator share links for temporary human file transfer.
4. Pull QMCP diagnostic reports for vendor/support troubleshooting.
5. Search file metadata with Qsirch as an operator convenience.

Do not use QMCP for unattended critical-path mutation of:

- FreeIPA users/groups or SSH keys.
- `/etc/exports`, QNAP NFS settings, or floating-home ownership.
- DNS, NetBox, Slurm, or host enrollment.
- Emergency break-glass access.

## Swagger UI / OpenAPI feasibility

### Feasible architecture

Swagger UI can be useful as an operator quick-reference if we generate and own a
small OpenAPI document for the REST endpoints above.  QMCP does not appear to
publish an OpenAPI schema itself.

Recommended low-risk shape:

```text
operator browser
  -> nginx container on an operator-only VLAN
    -> static Swagger UI + qmcp-openapi.yaml
    -> reverse proxy /qmcp/ to existing QTS Apache /qmcp/
      -> QTS Apache unix-socket proxy
        -> /var/run/qmcp.sock
```

Prefer proxying to the existing QTS `/qmcp/` Apache path instead of mounting
`/var/run/qmcp.sock` into a container.  Direct socket mounts make the container a
QNAP-local privilege boundary concern and are not needed for quick-reference UI.

### Nginx sketch

```nginx
server {
    listen 8444 ssl;
    server_name qmcp-swagger.rfc1918.host;

    # Serve static Swagger UI and qmcp-openapi.yaml here.
    root /usr/share/nginx/html;

    location /qmcp/ {
        proxy_pass https://172.16.254.28:8081/qmcp/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

### Authentication model

Use one of these, in order of preference:

1. **Read-only docs mode:** Swagger UI renders endpoint docs with `try it out`
   disabled.  Lowest risk.
2. **Operator session mode:** Browser already has QTS/QMCP session cookies and
   uses `/qmcp/` same-origin proxy rules.  Useful but must be operator-only.
3. **Bearer/app token mode:** Explicit token pasted into Swagger UI.  Highest
   leakage risk; never persist token in the OpenAPI document or container env.

### Risk assessment

| Risk | Severity | Control |
| --- | --- | --- |
| Swagger UI leaks QTS/QMCP token in browser history, logs, or screenshots | High | Prefer read-only docs mode; disable nginx access logging for auth headers; avoid bearer token persistence. |
| Nginx container gains direct access to QMCP Unix socket | Medium/High | Proxy through QTS Apache instead of mounting socket. |
| Operators mistake QMCP for source-of-truth | Medium | Banner the UI as convenience-only; link NetBox/FreeIPA runbooks as authoritative paths. |
| Incomplete OpenAPI schema causes bad writes | Medium | Mark mutation endpoints as `x-operator-reviewed: true`; start with read-only endpoints only. |

## Critical-path-adjacent workflow fit

Good fits:

- Pre-flight NAS status snapshots before QNAP-backed home-directory migrations.
- Operator quick reference for QNAP shared-folder/user visibility.
- Read-only log/diagnostic bundle capture when NFS behavior looks odd.
- File Station/Qsirch convenience searches during manual data recovery.
- Cross-checking QNAP UI state after Ansible/QNAP CLI changes have already been
  applied and validated by authoritative workflows.

Bad fits:

- Authoritative inventory or identity source.
- Automated FreeIPA/SSSD/NFS enrollment gates.
- Slurm execution dependencies.
- Any workflow that must continue if the QNAP app layer is broken.

## Recommendation

Proceed with a Swagger UI **read-only documentation container** first.  Keep
`try it out` disabled until we have a hand-reviewed OpenAPI file and explicit
operator auth handling.  Use QMCP for non-critical operator insight, not
critical-path automation.
