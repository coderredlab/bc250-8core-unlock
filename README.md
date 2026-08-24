<div align="center">

# 🔓 BC-250 8-Core Unlock Firmware

**Single-boot 8-core / 16-thread unlock for BC-250 boards running BIOS P3.00**

[English](README.md) | [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-AMD%20BC--250-00a4e4)
![BIOS](https://img.shields.io/badge/BIOS-P3.00-orange)
![Result](https://img.shields.io/badge/result-6C%2F12T%20%E2%86%92%208C%2F16T-brightgreen)
![Tested](https://img.shields.io/badge/tested%20on-real%20hardware-8A2BE2)
![License](https://img.shields.io/badge/code%20license-MIT-green)

*Cold power-on → one automatic reset → boots with all 8 cores enabled.*

</div>

---

## ✨ What makes this different

| | This firmware | Many other releases |
|---|---|---|
| Cold-boot unlock | ✅ automatic | ❌ manual tool + manual warm reboot |
| Presence validation | ✅ must read exactly `0x77` | often missing |
| SMU queue polling | ✅ bounded — gives up after 2,500 tries | often infinite loop |
| Factory fuse check | ✅ respects defective-core markings | none |
| Failure behavior | ✅ clean fallback to stock 6-core boot | undefined |
| Reset on success | ✅ one automatic reset, verified flip first | varies |

**Tested and confirmed working on real hardware (2026-08-24):**
cold boot → automatic reset once → `nproc` = 16, stable daily driver since.

---

## ⛔ STOP — read this before anything else

> [!CAUTION]
> ### This unlock does NOT repair dead cores
>
> The BC-250 ships gated to 6 cores **in software**. This firmware removes that
> software gate — nothing more.
>
> It **cannot revive physically defective silicon.** If your particular chip was
> binned down because its extra cores are genuinely faulty, forcing them online
> can cause boot failure or instability — and because the unlocked state persists
> across reboots, recovery would require an external SPI programmer.

### ✅ Mandatory pre-flight check (do this BEFORE flashing)

1. Boot your stock system and run the volatile unlock first:
   [rw-r-r-0644/bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock)
2. Warm-reboot when it completes.
3. **Stable 8C/16T?** (`nproc` = 16, handles stress fine) → your cores are alive,
   this permanent firmware is appropriate for you. ✔️
4. **Won't boot / crashes / stays 6C or unstable?** → your disabled cores are
   probably genuinely defective → **do NOT flash this ROM.** Stay on stock. ✖️

> [!NOTE]
> The author's own board passed this check (days of stable 8C/16T as a daily
> system plus per-core compute verification) before this image was ever built.

The firmware also performs its own hardware checks at runtime: host-bridge ID,
exact mask value, factory fuse register (`0x5D25C`) — any anomaly and it stands
down, letting stock logic run.

---

## 📦 Release contents

| File | Description |
|---|---|
| `BC250-P3.00-8Core.rom` | Full 16 MiB flash image, ready to program |

**SHA-256:**
```
1b7bcaa65e247363ad19e6a1dd3e296ae54b254fdeeeb32c8fb8ac505c86ac17
```

---

## 🚀 Flashing

> [!WARNING]
> - Only use on a BC-250 running **P3.00**. Other versions are untested.
> - Never interrupt power during the write.
> - Flashing firmware always carries risk — proceed at your own responsibility.

### Option 1 — Linux + flashrom *(recommended; proven working on this board)*

```bash
# 0) Save YOUR current BIOS first — that is your rollback!
sudo flashrom -p internal -r my-stock-backup.rom

# 1) Write
sudo flashrom -p internal -w BC250-P3.00-8Core.rom

# 2) Independent read-back (do not skip!)
sudo flashrom -p internal -r verify.rom
sha256sum verify.rom   # must equal the SHA-256 above
```

### Option 2 — External SPI programmer (CH341A etc.)

With the chip desoldered/socketed, program the image directly. Desolder +
external reflash has been demonstrated to work on this board.

---

## 🔎 After flashing — verify your unlock

```bash
nproc                       # expect: 16
grep -c ^processor /proc/cpuinfo
dmesg | grep -i "mce\|machine check"   # should be empty
```

Optional stress validation:

```bash
sudo apt install stress-ng
stress-ng --cpu 16 --cpu-method all --timeout 30m --metrics-brief
```

---

## 🔄 Behavior reference

| Scenario | Result |
|---|---|
| Cold power-on | PEIM unlocks → **one automatic reset** (~seconds) → boots 8C/16T |
| Warm reboot | Stays 8C/16T, no reset |
| Unlock fails at runtime | Clean stock 6-core boot (never hangs by design) |
| Full power loss | Cycle repeats exactly once |

> [!NOTE]
> The single extra reset on cold boot is a structural constraint: the SMU
> latches core bring-up before any inserted PEIM can run. Removing it would
> require reverse-engineering proprietary SMU messages.

> [!TIP]
> The image carries the author's NVRAM values. If the setup menu looks odd
> after first boot, do a CMOS/NVRAM clear.

---

## ↩️ Rollback

Flash back **your own saved stock dump** (made in step 0 of quick start) using
the same method. Reference hashes for orientation:

| Image | SHA-256 (first 16) |
|---|---|
| Stock P3.00 base used for development | `2854b3863b447e71` |
| Pre-flash snapshot of the test board | `ddb7f88e70bddcb7` |

If Linux won't boot at all after a bad write: external SPI programmer with your
stock dump. Desoldering + external reflash has been demonstrated on this board.

---

## 🧠 How it works

Three layers in the shipped image:

| Layer | Source | Content |
|---|---|---|
| 1 | Vendor stock P3.00 BIOS (AMI Aptio + AMD AGESA) | foundation |
| 2 | [TuxThePenguin0/bc250-bios](https://gitlab.com/TuxThePenguin0/bc250-bios) | chipset menu exposure (~260 KB form/IFR changes) |
| 3 | **This project** | CCX byte patch + unlock PEIM (below) |

<details>
<summary><b>Technical changes (click to expand)</b></summary>

1. **AmdCcxVhAriPei**: one immediate byte (`07 → 00`) in the OPN-to-downcore-token conversion, so CCX never applies core gating itself (OPN Auto behavior).
2. **Inserted PEIM (`Bc250CoreUnlockPei`)**: registers a notify on the AMD NBIO SMU service PPI, validates the core-presence register reads exactly `0x77`, checks the factory core-disable fuse register (`0x5D25C`) is clean — refusing to unlock boards whose disabled cores were factory-marked as defective — then flips presence to `0xff` through SMU Queue 3 (message `0x98`) with bounded polling and read-back verification. On success it requests a PEI reset so the SMU re-initializes with all cores enabled.

Everything else in the image is byte-identical to the CHIPSETMENU base described above.

</details>

### Why the auto-reset exists

The SMU latches core bring-up **before any inserted PEIM can run**, so a fresh
presence flip only becomes effective after a reset. Presence survives a warm
reset, which is what makes the single automatic reboot sufficient. This mirrors
what stock CCX itself does whenever downcore settings change.

Full reverse-engineering notes (SMU Queue 3 protocol, PEI dispatch analysis,
CCX downcore decision path) live in the research wiki of the main project.

---

## 🙏 Credits

- [rw-r-r-0644/bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock) — SMU Queue 3 protocol & volatile unlock discovery
- [TuxThePenguin0/bc250-bios](https://gitlab.com/TuxThePenguin0/bc250-bios) — base image (`BC250_3.00_CHIPSETMENU.ROM`: chipset menu exposure)
- [RescueMei/BC250-DXE-SMU-Core-Unlock](https://github.com/RescueMei/BC250-DXE-SMU-Core-Unlock) — prior art
- [GabriWar/bc250-core-cu-unlock](https://github.com/GabriWar/bc250-core-cu-unlock) — prior art
- [bc250-collective/amd_smu_reverse_engineering](https://github.com/bc250-collective/amd_smu_reverse_engineering) — SMU reverse engineering

---

## 📄 License

Source code and build tooling: **MIT License** (see [`LICENSE`](LICENSE)).

The `.rom` image contains firmware derived from the board vendor's stock P3.00
BIOS (AMI Aptio + AMD AGESA). Provided as-is for owners of BC-250 hardware; all
respective copyrights remain with their owners.
