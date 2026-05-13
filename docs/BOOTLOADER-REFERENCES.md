# Bootloader References

This repo currently treats ZFSBootMenu as the default EFI boot path for Gentoo
Stage4/Stage5 systems. rEFInd remains a relevant alternate or adjunct boot
manager for workstation and multi-boot validation work.

## Local rEFInd Mirror

A local mirror of Rod Smith's rEFInd documentation is available on-host:

`/opt/repos/local/wget-synclocal/www.rodsbooks.com/refind`

Use this mirror before external browsing when working on:

- rEFInd boot stanzas and EFI loader discovery behavior.
- Workstation or multi-boot test hosts where ZFSBootMenu is not the only boot
  path under evaluation.
- UEFI fallback behavior, ESP layout decisions, and boot manager comparison
  notes.

Do not commit mirrored website content into this repository. Track distilled
implementation notes, decisions, and repo-local automation only.
