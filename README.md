# OneiOS

**This repository** ([denis0001-dev/OneiOS-S25-Ultra](https://github.com/denis0001-dev/OneiOS-S25-Ultra)) is a fork of [akshaynexus/OneiOS](https://github.com/akshaynexus/OneiOS) that adds an experimental **Galaxy S25 Ultra** bring-up (**SM-S938***, `pa3q`, **SM8750** / Adreno 830). Upstream targets the **Galaxy S24 Ultra** (`SM-S928`, **SM8650**). Both run **iOS 27.0.1** (`24A446`, iPhone 18,2) next to One UI: nothing is flashed; runtime and image live under `/data/local/tmp/oneios`; **xnuhost** runs source-built **XNU** as a process on One UI’s Linux kernel.

How it fits together: [docs/architecture.md](docs/architecture.md). How to build: [docs/building.md](docs/building.md). **S25 port details:** [docs/port-s25-ultra.md](docs/port-s25-ultra.md).

## Galaxy S25 Ultra (this fork)

| | |
|---|---|
| **Host** | Rooted Snapdragon S25 Ultra; KernelSU tested; OneOS **oneios** branch with `s-ultra-8750` gating (app + `oneios_switch.sh` live in a sibling **OneOS** checkout — not in this git tree). |
| **Guest** | Same iOS 27 image set and `kernel.kc` series as upstream until integration forces a change. |
| **Runtime** | Build or ship `oneios-runtime-*-s25dev-arm64` from this tree; staged `bin/xnuhost` **must** include SM8750 **drm2kgsl** fixes (patch `0007-a830-waittimestamp-fences`, `virgl_fence_table_init`, `ONEIOS_XNUHOST` — see port doc). Stock release `xnuhost` alone is not enough on Adreno 830. |
| **On-device (Nov 2025)** | `gpuctl` OK (chip `0x44050000`, **192 GiB** GPU VA). CPU topology checks pass. Sessions with fork-built `xnuhost` reached **SpringBoard**; logo-only stalls traced to bad overlays / wrong `xnuhost` / boot-args replacing defaults — recovery steps in the port doc. Thermals and Spotlight can end long sessions. Wi‑Fi: default bridge; join once in iOS Settings (persists on `data.img`). |

### Run iOS on the phone

**One-time:** Import runtime + image set (OneOS app → **iOS 27 (OneiOS)** → *I have the file*, or [building.md](docs/building.md) §6 via `adb`). Install the patched OneOS APK. Stage the SM8750 `xnuhost` if you built locally.

**Switch** (after staging, no PC required):

```sh
su -c 'sh /data/local/tmp/oneios/oneios_switch.sh --check'
su -c 'sh /data/local/tmp/oneios/oneios_switch.sh'
```

Or: OneOS → **Choose a system** → **iOS 27 (OneiOS)** → experimental acknowledgment → **Switch**. Preflight may refuse if the battery is hot (~42 °C).

**Return to One UI:** Volume **Up + Down** for **3 seconds**; or `oneios_return.sh`; **Power + Volume Down** reboot if stuck.

**Samsung switch note:** bind+remount read-only on session **files** fails on some kernels; directories only, `chmod 555` on the session scripts (see port doc).

### What this fork changes in tree

- Hosted GPU path for **Adreno 830** / KGSL fence behaviour.
- Host profile [profiles/host-galaxy-s25-ultra-sm8750.toml](profiles/host-galaxy-s25-ultra-sm8750.toml), SM8750 CPU tests in `runtime/bridges/tests/`.
- Documentation: [docs/port-s25-ultra.md](docs/port-s25-ultra.md).

**Not in scope:** Exynos S25 models; passcode, Face ID, Wallet, cellular calls/SMS; treating this as a consumer ROM.

---

## What OneiOS is (upstream model)

OneOS guests are Android systems on One UI’s Linux kernel. iOS userland needs Apple’s kernel (XNU), so OneiOS runs XNU **inside** `runtime/xnuhost`. The image, switch, and return stay OneOS-shaped ([OneOS `oneios`](https://github.com/akshaynexus/OneOS/tree/oneios)).

## Status (upstream S24 Ultra)

The paragraphs below record **akshaynexus/OneiOS** phone and QEMU progress on the **S24 Ultra**. They are kept for context; **S25 validation is in the port doc and the section above.**

**Experimental.** On the phone (S24 Ultra, 2026-11-11) the boot reaches launchd, backboardd and SpringBoard, and backboardd's first frames are on the panel: the Apple boot logo at 1440x3120. Whether it goes on to SpringBoard's own screen is not yet seen.

Touch on the phone: in that session the DriverKit event driver was waited for, so the touch screen and the buttons
reached backboardd only 233 s after they started (then 447 events, 11 contacts). The kernel now gives both to
Apple's kernel event driver at once (`kernel/patches/oneios-hosted/hid/README.md`, "Which event driver"); built,
not yet run on the phone. Whether a swipe up unlocks is not known.

Second phone session (2026-11-11, with the Metal plug-in mounted): touch attached at once, the battery was
published, backboardd opened the AGX device user client, and the kernel then died in a data abort: a wrong pair in
the collection (`IOMemoryDescriptor::setOwnership` bound to `CreateMapping`, `kernel/prelink/README.md`). Corrected;
the collection builds; not yet run on the phone.

Later sessions (2026-11-11): with the corrected collection and the Metal plug-in's grant the phone reaches the
lock screen and, after unlock, the Home Screen, composited on the GPU at 40 to 60 frames a second; touch works.
The Home Screen had no apps and SpringBoard died once on unlock (an assertion about a missing process identity):
the removable system apps were never shown in `/Applications`. Hosted `0035` shows them, `0037` keeps them
registered after the first boot of a Data store, `0036` drops icons drawn blank by earlier boots; built, not yet run.

First Mac builds on the phone (2026-11-12): the Mac `kernel.kc` panics in the first 2 s, in both builds tried
(507 stubs pointing past the collection with XnuPrelink `b74ed7c`; then an original kernel function left on the
stub, called by Sandbox; `kernel/prelink/README.md`, "On the phone"; agent prelink audits it). The Mac runtime
0.1.7-dev with the Linux `kernel.kc` of 2026-11-11 boots to `session/ready` in about 80 s and to the lock screen;
the Linux runtime 0.1.6 does the same, and the owner unlocked it to the Home Screen (empty: that kernel has no
0035-0037). In both, the screen drew far fewer frames than on 2026-11-11 (0-20 per 10 s; cause not known) and the
Volume Up + Volume Down chord did not return; five returns by `session/return.request` or after a panic all came back
to One UI in place. Numbers per area: `docs/hardware.md` 0.1; the test cycle: `docs/building.md` section 6.

The Mac `kernel.kc` with the known-good pairs (2026-11-12, agent prelink; `kernel/prelink/README.md`, "Known-good
pairs" and "On the phone (2026-11-12, prelink)"): kernel and collection from origin/main `924a0d9` (series through
0039), runtime 0.1.8-dev. Boot frame at +102 s, then about 11 minutes of lsd registering the staged apps (the first
boot of 0035/0037 on this Data store) while SpringBoard waited for the LaunchServices database; then the lock screen,
the owner's swipe unlocked it, and the Home Screen showed the apps (their icons do not draw right yet). No panic and
no call to the panic stub in 23 minutes. This set is the phone's baseline now.

On the PC (xnuhost under `qemu-aarch64`, 8 vCPUs, the real iOS 27.0.1 `24A446` image set, `kernel.kc` with the
iPhone18,2 kexts), the boot gets through corecrypto, AMFI, launchd, **`backboardd` and `SpringBoard`**, and SpringBoard
in `UIApplicationMain`’s run loop ([full upstream paragraph in history / agents board](docs/agents.md)). The PC guest has no 3D GPU; the phone with KGSL is where compositing is proven on S24.

Detail on hosted patches: [kernel/patches/oneios-hosted/README.md](kernel/patches/oneios-hosted/README.md), [docs/agents.md](docs/agents.md).

## Layout

```
docs/architecture.md  how the parts fit; docs/building.md  how to build and test; docs/*.md  each part in detail
docs/port-s25-ultra.md  Galaxy S25 Ultra port (this fork)
profiles/             the pinned IPSW profile (iPhone18,2 iOS 27.0.1 24A446)
scripts/fetch/        fetch only the needed IPSW members from Apple's CDN (never from here)
scripts/image/        build the image set (MysticGSI-style manifest, SHA-256, .tar.zst)
userland/             iOS 27 root and Data tweaks (the image hook), guest helpers, the camera plug-in
kernel/               XNU 12377 (UniXNU / Droid-VM fork) built on Linux; oneios-hosted/ patches; prelink/ (kernel.kc)
runtime/              xnuhost and its loader, the display helper, the hardware bridges, the runtime package
drivers/              iOS-side drivers for the bridges (CPU, network, Bluetooth, haptics, audio, brightness, camera)
oneos/                the contract with the OneOS fork (akshaynexus/OneOS, branch oneios)
```

## Rules

- **No Apple files in git or in releases.** IPSWs, cryptexes, kernelcaches, kexts, `kernel.kc` and every image built
  from them stay in `out/` and `inputs/` (git-ignored). Scripts fetch them from Apple and build them on the owner's
  machine. Releases carry only this project's own code (scripts, runtime binaries, the OneOS patches); the kernel is
  built locally (it links Apple's corecrypto).
- Long jobs run in tmux: `scripts/bg.sh NAME COMMAND...`.
- Every change updates the docs that describe it: [CLAUDE.md](CLAUDE.md).

## Credits

[OneOS](https://github.com/fahadalijaved/OneOS) (fahadalijaved) and
[OneLineage](https://github.com/WeWaffles/OneLineage) (WeWaffles): the container hot-switch.
[MysticGSI](https://github.com/MysticGSI/mysticgsi): the image build model.
[UniXNU](https://github.com/UniXNU/UniXNU) and [Droid-VM](https://github.com/Droid-VM): XNU on non-Apple
ARM64, drm2kgsl, the guest drivers. [iOSPlus10](https://github.com/akshaynexus/iOSPlus10): XNU and iOS userland on
Qualcomm phones, haptics and brightness. [Darling](https://github.com/darlinghq/darling): Mach and XNU on Linux.

Upstream: [akshaynexus/OneiOS](https://github.com/akshaynexus/OneiOS).