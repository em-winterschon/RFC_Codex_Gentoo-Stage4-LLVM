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
  --local-image localhost/gentoo-stage3-llvm-clang-openrc:latest \
  --image-name gentoo-stage3-llvm-clang-openrc \
  --tag git-$(git rev-parse --short HEAD) \
  --namespace em-winterschon \
  --source-url https://github.com/em-winterschon/RFC_Codex_Gentoo-Stage4-LLVM \
  --description "Gentoo stage3 LLVM/Clang OpenRC service-container base"
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

## Active base image

The current service-container base image is:

- local source image:
  - `localhost/gentoo-stage3-llvm-clang-openrc:latest`
- GHCR immutable tag:
  - `ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc:git-e5bf45f`
- GHCR promoted tag:
  - `ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc:latest`
- service-layer profile:
  - `profile-definitions/container-service-base-image.yml`

The container host role renders the resolved profile to
`/etc/container-services/base-image.yml` so service-image build automation can
use the same base image, immutable source tag, binpkg repo ID, and publication
namespace.

## Later workflow

Once service-specific images are validated, publish them through the same GHCR
helper using image names derived from the Stage5 service profile.

Current validation note:

- the active base image is the standard Gentoo `amd64-llvm-openrc` stage3 with
  a small Stage5 service-container package layer
- the hardened Stage4 image path remains deferred until the first service layer
  is stable
