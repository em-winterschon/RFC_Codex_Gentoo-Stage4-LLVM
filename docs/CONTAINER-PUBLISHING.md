# Container Publishing

## Current target

The first supported registry target is `GHCR`:

- registry: `ghcr.io`
- namespace: GitHub owner or org
- transport: standard OCI/Docker registry API via Podman

## Immediate workflow

1. Build or import the validated local image.
2. Tag it for `ghcr.io/<namespace>/<image>:<tag>`.
3. Authenticate with a GitHub token that has `write:packages`.
4. Push the image and record the digest.

If you need to create the local image first, use the rootfs/image builder in
`docs/CONTAINER-BUILDING.md`.

## Helper script

Use:

```bash
bash scripts/publish-container-ghcr.sh \
  --local-image localhost/gentoo-stage4-base:latest \
  --image-name gentoo-stage4-base \
  --tag git-$(git rev-parse --short HEAD) \
  --namespace em-winterschon \
  --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --description "Gentoo Stage4 LLVM/Clang hardened base container"
```

Token sources:

- `GHCR_TOKEN` environment variable
- `GHCR_TOKEN_FILE`
- `--token-file`

Optional user override:

- `GHCR_USER`
- `--user`

## Tagging policy

Recommended:

- immutable validation tags:
  - `git-<shortsha>`
  - `YYYYMMDD`
- promoted tags:
  - `latest`
  - release tags only after validation

Always record:

- pushed digest
- git commit SHA
- profile name
- source URL

## Later workflow

Once the container-services VM is validated end-to-end, the next build path should
create a Gentoo container rootfs from the Stage4 profile and feed it into
`buildah`/`podman`, then publish the validated result through the same GHCR helper.
