# Package Version Pinning

Stage4 and Stage5 profiles track application version locks in:

```text
gentoo_stage4_llvm_split-usr_no-multilib_hardened/gentoo-liveiso-ansible/app-version-locks/stage5-service-apps.yml
```

Gentoo package atoms remain authoritative for OS packages. Service applications
outside the Gentoo tree must have explicit upstream version and checksum locks.
Metadata files include `package_pins`, and `pin_gaps` are explicit follow-up
items for Portage-resolved services.
