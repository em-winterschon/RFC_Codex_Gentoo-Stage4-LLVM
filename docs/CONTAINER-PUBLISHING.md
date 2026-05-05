# Container Publishing

## Current target

The first supported registry target is `GHCR`:

- registry: `ghcr.io`
- namespace: GitHub owner or org
- transport: standard OCI/Docker registry API via Podman, or host-side `crane`
  from a docker archive when VM egress is slow

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
- published digest:
  - `sha256:4c0cc158b9ab55f7b126dcd80deb8327959a0fd8cd132af7fa09a438df4e85b6`
- digest-pinned reference:
  - `ghcr.io/em-winterschon/gentoo-stage3-llvm-clang-openrc@sha256:4c0cc158b9ab55f7b126dcd80deb8327959a0fd8cd132af7fa09a438df4e85b6`
- service-layer profile:
  - `profile-definitions/container-service-base-image.yml`

The container host role renders the resolved profile to
`/etc/container-services/base-image.yml` so service-image build automation can
use the same base image, immutable source tag, binpkg repo ID, and publication
namespace.

## Later workflow

Once service-specific images are validated, publish them through the same GHCR
helper using image names derived from the Stage5 service profile.

Current published service images:

- `ghcr.io/em-winterschon/gentoo-stage5-nginx:git-d5104ae`
- `ghcr.io/em-winterschon/gentoo-stage5-nginx:latest`
- nginx digest:
  - `sha256:8604b39531e508348a3ac3094621b3aef51ca8927721f17087742b888e6e9c90`
- `ghcr.io/em-winterschon/gentoo-stage5-haproxy:git-d5104ae`
- `ghcr.io/em-winterschon/gentoo-stage5-haproxy:latest`
- HAProxy digest:
  - `sha256:322699f05e1109f63fff3796ce7dbbddb7200c7933c2eb7ae7aaaa6e88bc8f37`
- `ghcr.io/em-winterschon/gentoo-stage5-rsyslog-collector:git-396998a`
- `ghcr.io/em-winterschon/gentoo-stage5-rsyslog-collector:latest`
- rsyslog collector digest:
  - `sha256:2acfd8f06d7aa3a9524a95bade090793543c228bd62b6bf38e76302324195287`

Current validation note:

- the active base image is the standard Gentoo `amd64-llvm-openrc` stage3 with
  a small Stage5 service-container package layer
- the hardened Stage4 image path remains deferred until the first service layer
  is stable
