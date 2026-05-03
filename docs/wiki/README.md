# Wiki Source Policy

`docs/wiki/` is the source of truth for the repository wiki.

Policy:

- all wiki content must be authored and reviewed in the main repository
- GitHub wiki content is a deployment target, not the canonical source
- wiki updates should travel through the same PR and review path as code and configuration
- publishing to `<repo>.wiki.git` is a separate step that happens only after the PR is approved

Operational rules:

- create or edit wiki pages under `docs/wiki/`
- keep page names aligned with GitHub wiki conventions such as `Home.md` and `_Sidebar.md`
- use `scripts/publish-wiki.sh` to mirror `docs/wiki/` into a local wiki checkout
- add `--push` only when the branch has been reviewed and is ready to publish

Current mirrored pages:

- `Home.md`
- `Architecture-and-Design.md`
- `Workflows.md`
- `Proxmox-NetBox-RouterOS-Action-Plan.md`
- `Hasslehoff-Inventory.md`
- `NetBox-Essentials.md`
- `Infrastructure-Inventory-Intake.md`
- `NetBox-IPAM-DCIM-Completion-Plan.md`
- `CRS309-RouterOS-Replacement-Plan.md`
- `Configurations-and-Examples.md`
- `CI-Builder-Farm.md`
- `Binpkg-Repository.md`
- `Container-Services-Validation.md`
- `Container-Building.md`
- `Container-Publishing.md`
- `Identity-AAA.md`
- `Telemetry-Observability.md`
- `Observability-Access.md`
- `Changelog.md`
- `EOD-Status-2026-05-02.md`
- `EOD-Status-2026-04-30.md`
- `EOD-Status-2026-04-29.md`
- `EOD-Status-2026-04-28.md`
- `Repository-Layout.md`
- `Roadmap-and-TODO.md`
- `_Sidebar.md`

Typical workflow:

```bash
# refresh the local wiki checkout without publishing
bash scripts/publish-wiki.sh

# after PR approval, publish the mirrored wiki content
bash scripts/publish-wiki.sh --push
```
