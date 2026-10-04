# Windows 11 gaming setup

Repeatable Windows settings for an i5-8400 / GTX 1660 SUPER desktop, with a modest removal list and recovery for configuration changes. Compatible with Windows PowerShell 5.1 on Windows 11. No downloads, package managers, external debloat scripts, or dependencies are needed to run it.

## Fresh install or existing PC

Download this repository as a ZIP and extract it, or clone it:

```powershell
git clone https://github.com/ruanbeets/win11.git
cd win11
.\install.cmd
```

Run from your normal Windows account. User changes run first; Windows then asks for administrator access for machine settings and SSD maintenance. No reboot is forced. Sign out or restart afterwards to refresh shell settings and startup behavior. Launch Steam, EA, Docker and Ollama manually when needed. Their running processes are not terminated.

Review the plan without changing anything:

```powershell
.\install.cmd -WhatIf
```

Read hardware, storage health, recent storage errors, startup apps, current settings and process memory:

```powershell
.\install.cmd -Audit
.\install.cmd -Audit -AuditPath "C:\path\to\audit.json"
```

The audit reads system state and prints JSON, or saves it when `-AuditPath` is provided (the parent directory must exist). Administrator access is needed for some storage reliability counters. Missing counters are reported as unavailable, not healthy. WMI's startup inventory can be cached; use the direct `StartupRegistry` and `StartupShortcuts` fields to verify startup changes. Save private audit output outside the repository, or in the gitignored `reports/` directory. A single disk activity sample is not a benchmark.

## Changes

- Enable Game Mode; disable Windows background game capture and recording. Xbox and Gaming Services are preserved; recording must be re-enabled if you want Windows capture.
- Reduce taskbar/window animations and transparency, hide the Widgets taskbar button, disable several Windows tips, advertising and promotional app suggestions. Windows version and edition can affect which shell/policy settings are honored; hiding Widgets does not uninstall its shared runtime.
- Disable **current-user** login entries for Docker Desktop, Steam, EA, Epic, GOG, Battle.net and Canva, when present. Move Ollama and Send to OneNote startup shortcuts to the rollback folder. Per-app updaters can re-create startup entries; rerun the installer when needed. This does not disable their services, scheduled tasks, or machine-wide startup entries.
- Remove only the exact optional packages in `config.json`, for the current user: Clipchamp, News, Weather, Solitaire, Feedback Hub, Get Help, Tips, People, 3D Viewer, Mixed Reality Portal, Skype, legacy Cortana, Maps, legacy Music/Movies, and To Do. Missing packages are skipped. Other accounts and provisioned packages are preserved; run user scope for each account if wanted.
- Keep Outlook, Phone Link, OneDrive, Office, Store, App Installer/winget, Edge/WebView, codecs, runtimes, Xbox, gaming services, NVIDIA/Realtek controls, DS4Windows, DualSenseX, Logitech G HUB, audio software, games, development tools and personal files.
- Select the built-in **High Performance** plan on desktops; leave battery devices' current plan alone. This may increase idle power and heat and is not a guaranteed FPS gain. Set `powerPlan` to `Keep` to retain your current plan.
- Configure Storage Sense for weekly temporary-file cleanup. Never automatically empty Downloads or Recycle Bin or dehydrate OneDrive content. Storage Sense works on the Windows system volume.
- Run **ReTrim**, not defragmentation, on healthy internal NTFS SSD volumes. USB drives, unrecognized media, unhealthy drives, and unlettered partitions are skipped. Windows' scheduled Optimize Drives maintenance is preserved.

`config.json` is the persistent preference file. Reduce its removal/startup lists to preserve more apps; `ssdRetrim: false` skips maintenance. The reviewed allowlists deliberately reject unrelated app/startup removal. The installer can run repeatedly; it writes a new pre-change journal each time.

## Recovery and logs

Each run prints its exact `state.json` path. Backups are stored outside the repo:

- User: `%LOCALAPPDATA%\Win11Tune\<run>\state.json`
- Machine: `%ProgramData%\Win11Tune\<run>\state.json`

Each folder contains `install.log`. Changes are journaled to disk **before** mutation, so a partial failure can be restored. Backup files stay on the computer being tuned; do not commit them. There is no automatic System Restore snapshot.

```powershell
.\install.cmd -Restore -StatePath "C:\Users\YOUR_USER\AppData\Local\Win11Tune\RUN\state.json"
```

For a machine journal, run the restore command from an administrator terminal. Restore as the original user for a user journal. Preview restore with `-WhatIf`. Restore runs in reverse order, preserves unrelated registry values and skips startup shortcuts that already exist. If you ran the installer multiple times, restore the journals newest to oldest to return to the original baseline. Do not restore over later settings you want to keep.

**App uninstall is not automatically reversible:** use Microsoft Store to reinstall the removed apps listed in the journal. Existing app data might be lost during uninstall. ReTrim requires no rollback. Temporary files later cleaned by Storage Sense are not backed up. Registry values created by the installer are removed on restore; empty registry keys may remain.

For user settings only, without requesting administrator access:

```powershell
.\install.cmd -Scope User
```

For machine settings only, in an administrator terminal:

```powershell
.\install.cmd -Scope Machine
```

## Observed hardware and limits (4 October 2026)

- Gigabyte B360M D3H, Intel i5-8400 (6 cores), GTX 1660 SUPER, 16 GB RAM in four 4 GB modules at 2133 MT/s.
- C: is a 250 GB SATA SSD, with about 88 GiB free. D: is a 1 TB NVMe SSD with about 418 GiB free in its Windows data partition. Both report Healthy. Detailed reliability counters require an administrator; this is not a complete SMART diagnostic.
- The final administrator audit read 38 C on the SATA SSD and 52 C on the NVMe. The SATA drive reported 24,236 power-on hours and zero uncorrected read errors; several other reliability fields were unavailable. A reported wear value of zero alone does not establish remaining drive life.
- The pagefile is already system-managed on D: (16 GB allocated during inspection, about 243 MB used). Preserve it. The machine-wide automatic-pagefile flag being false does not mean the D: pagefile is manually sized: its initial/maximum sizes are both zero (system-managed).
- Ultimate Performance was already active; this installer uses High Performance for a portable fresh-install configuration. Power plans cannot eliminate storage latency or make this locked CPU overclockable.
- Windows 11 Pro build 22631 is 23H2, out of support since November 11, 2025. Upgrade to a supported Windows release through Windows Update; upgrades and automatic reboots are deliberately separate from this script. Verify ExplorerPatcher and other shell customizations against the target Windows version first.
- The NVMe disk contains other unlettered partitions. The installer never changes partition layouts, moves Windows, migrates games, or changes boot configuration.

No gaming benchmark, SSD throughput benchmark, thermal test, or memory stability test is implied. Measure the same game, scene, graphics settings and background apps before/after; compare frame-time percentiles and 1% lows, not just average FPS. Keep changes that measurably help your actual games.

For the next Windows reinstall, choose the faster NVMe for Windows **only after backing up its existing partitions and checking the install target carefully**. Using it for Windows and active games is likely to help disk-heavy work compared with the SATA SSD, but the benefit has not been measured here.

## Settings that need hardware/game validation

- In Settings > System > Display > Advanced display, use each monitor's highest supported refresh rate. The script never guesses display modes.
- Enable Optimizations for windowed games in Windows Graphics settings for compatible DX10/DX11 games. Test individual games if presentation issues appear. HAGS is left as configured; compare on/off and reboot between tests rather than assuming one is fastest on the GTX 1660 SUPER.
- Use current official NVIDIA and motherboard drivers. Driver updates and BIOS flashes are separate steps and need rollback/stability checks. Use NVIDIA Reflex in supported games; prefer per-game GPU settings over globally forcing maximum power or disabling synchronization.
- Check the DIMMs' rated speeds and BIOS profile support before changing XMP. The i5-8400/B360 combination has memory limits; 2133 MT/s could be the actual module rating. Never assume the RAM supports 2666 or a higher XMP speed.
- Keep Defender, Windows Update, firewall, UAC, Secure Boot, memory integrity, Hyper-V/WSL/Docker support, pagefile, Search and normal maintenance. They are not removed for speculative gains. Disabling the hypervisor would break this PC's development workflow. Existing undocumented tweaks are not reset wholesale.
- No HPET/BCD timer edits, interrupt-affinity guesses, network latency registry folklore, RAM cleaners, global process priority hacks, CPU parking hacks, forced SSD defrag, automatic overclocking, or manual fan/voltage changes.

## Validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test.ps1 -RegistryIntegration
```

The optional integration test writes only a unique temporary registry fixture and verifies raw value/type recovery, absence recovery, preservation of unrelated values, and repeat restores. It deletes its own fixtures afterwards. Tests do not remove apps or alter real tuning settings.

## References

- [Microsoft: PC performance](https://support.microsoft.com/en-us/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows)
- [Microsoft: Storage Sense configuration](https://learn.microsoft.com/en-us/windows/configuration/storage/storage-sense)
- [Microsoft: Storage policy registry mapping](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-storage)
- [Microsoft: Optimize Drives](https://support.microsoft.com/en-us/windows/defragment-optimize-your-data-drives-in-windows-54d4fed1-c96e-46db-b843-8c6b34bd27a4)
- [Microsoft: Windowed gaming optimization](https://support.microsoft.com/en-us/windows/hardware/display-graphics/optimizations-for-windowed-games-in-windows-11)
- [Microsoft: Windows 11 Pro 23H2 lifecycle](https://learn.microsoft.com/en-us/lifecycle/announcements/windows-11-23h2-end-of-updates-home-pro)
