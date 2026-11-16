# Port: Galaxy S25 Ultra (SM8750)

Experimental port workspace: `~/OneiOS-s25-port` ([denis0001-dev/OneiOS-S25-Ultra](https://github.com/denis0001-dev/OneiOS-S25-Ultra)). Upstream product scope is still **S24 Ultra** in [plan.md](plan.md); this page tracks **S25 Ultra** bring-up and device results.

## Device validation (2025‑11)

On **SM-S938B**, `pa3q`, **SM8750**, KernelSU:

- Switch preflight and **CPU** layout match the SM8750 fixture (8 CPUs, 2P+6E).
- **gpuctl** baseline below; **`submit` / `large`** pass on device.
- Full sessions with the **fork-built `xnuhost`** (Adreno 830 fence path) reached **SpringBoard**; stock release `xnuhost` alone is insufficient for SM8750.
- **Stuck Apple logo** sessions correlated with bad overlays (custom `boot-args` replacing defaults, SSH seed / trust cache drift, release `xnuhost`). Recovery: restore tarball `data.seed`, `owner-trust`, `overlay/userland/xnuhost.conf` (`scale=3` only), stage `manifest.json` + trust reports, wipe `data.img` only when you mean to reset Data.
- Long runs can **thermally** throttle or return to One UI; guest Spotlight/indexers worsen heat — see [Spotlight](#spotlight--search-indexing-heat-and-lag).
- **Wi‑Fi:** default bridge mode; join network in iOS Settings once; networks live on `data.img` (avoid wiping if you want persistence).

## Running a session

One-time: stage **runtime** + **image set** under `/data/local/tmp/oneios` ([building.md](building.md) §6, or the OneOS app import). Install the patched **OneOS `oneios`** APK. Push the SM8750 **`xnuhost`** into the staged runtime if you built locally.

**Switch** (phone only, after staging):

```sh
su -c 'sh /data/local/tmp/oneios/oneios_switch.sh --check'
su -c 'sh /data/local/tmp/oneios/oneios_switch.sh'
```

Or OneOS → **Choose a system** → **iOS 27 (OneiOS)** → experimental acknowledgement → **Switch**.

Preflight may refuse while the battery is warm (~**42 °C**); cool down and retry.

**Return:** Volume **Up + Down** held **3 s**; or `oneios_return.sh`; **Power + Volume Down** reboot as last resort.

**Samsung note:** `oneios_switch.sh` must not bind+remount,ro the session **script files** (kernel error: not in `/proc/mounts`); directories are bound RO; scripts use `chmod 555` (fix in the port’s OneOS fork).

## Hardware delta from S24 Ultra

| | S24 Ultra (baseline) | S25 Ultra (port) |
|---|---|---|
| SoC | SM8650 (Snapdragon 8 Gen 3) | SM8750 (Snapdragon 8 Elite) |
| GPU | Adreno 750, KGSL id **6770** (documented) | Adreno 830 — **run `gpuctl` on device** |
| CPU topology | Cortex X4/A720/A520 (8 cores) | 8x Oryon — capacities from sysfs |
| OneOS profile | `s-ultra-8650` | `s-ultra-8750` |
| Codename | `e3q` | `pa3q` |

The **guest** (iOS 27, iPhone18,2, `kernel.kc`) is unchanged until host integration fails.

## Software changes in this port

1. **OneOS** (`OneOS-oneios`): offer iOS on `s-ultra-8750`; `oneios_switch.sh` preflight for `SM-S938*` / `pa3q` / `SM8750`.
2. **Tests**: `make_sm8750()` fake sysfs in `runtime/bridges/tests/test_bridges.c` (8 cores, 2E+6P plan).
3. **Profile**: [profiles/host-galaxy-s25-ultra-sm8750.toml](../profiles/host-galaxy-s25-ultra-sm8750.toml).

## Checklist on a rooted S25 Ultra

1. Root (KernelSU tested upstream on S24; same expected).
2. Stage runtime + image set per [building.md](building.md).
3. **Hardware checks → GPU** (`gpuctl`): record chip id, `GPU addresses …`, udmabuf `size_limit_mb` / `list_limit`, VBO import (see [gpu.md](gpu.md) §4.1).
4. **CPU** (`bridgectl cpu`): sysfs capacities and cpufreq tables.
5. First switch; compare `session/xnuhost.log` stages to fork `OneiosLogs` summary.
6. If kernel panics in GPU path: compare KGSL module to `samsung-sm8650` vs SM8750 module sources (VBO headroom patch may need different `DRM2KGSL_VBO_HEADROOM_GB`).

### SM8750 gpuctl baseline (2026-11-15)

On **pa3q / CP2A.260605.016**, `gpuctl` reports chip **0x44050000**, gpu id **6850**, **192 GiB** GPU VA (256 GiB VBO leaves no room for imports), gmem **12288 KiB**, udmabuf **64 MiB / 1024** runs.

**Host fixes (SM8750):**

1. **Patch `0007-a830-waittimestamp-fences`:** Adreno 830’s `KGSL_TIMESTAMP_EVENT(FENCE)` path **SIGSEGV**’d after the first `GPU_COMMAND`. Default to **`WAITTIMESTAMP_CTXTID`** (`NCTX_NO_WAITTS=1` for A/B only).
2. **`virgl_fence_table_init()`** in `gpu3d_kgsl.c` (full virglrenderer init is not linked in xnuhost).
3. **`ONEIOS_XNUHOST`:** skip `virgl_fence_set_fd()` in `drm_fence.c` (sync-file export table unused in xnuhost).

`gpuctl submit` / `large` pass with no env vars; xnuhost must be the rebuilt `bin/xnuhost` on stage (MD5 checked after `cp` via `su`). Preflight may refuse switch while the SoC is hot (~42 °C) after a failed session—cool down, then switch again.

### Spotlight / search indexing (heat and lag)

**Most indexing is already off** in the image: `userland/config/daemons.toml` group `base` disables `com.apple.spotlightknowledged`, `.updater`, and `com.apple.hybridsearchd` in the Data seed’s `disabled.plist` at image build.

If the phone’s **Data volume predates** that policy, or a job was re-enabled, the guest can still spin **Spotlight** / background indexers after boot (especially with Settings open). Fix without wiping Data:

1. Stage an image `overlay/userland/xnuhost.conf` whose `boot-args=` includes the normal hosted kernel switches **and**  
   `oneios-disable-jobs=com.apple.accessibility.axassetsd,com.apple.spotlightknowledged,com.apple.spotlightknowledged.updater,com.apple.hybridsearchd`  
   (kernel [0053](../kernel/patches/oneios-hosted/0053-disable-jobs.patch); console lines `oneios-jobs: … disabled …`).
2. On the next boot, confirm those lines in `session/xnuhost.log`.

You **cannot** fully remove the home-screen Search UI (SpringBoard) without breaking search; avoid pulling down Search while thermals are high. In Settings → Siri & Search, turning off suggestions reduces work further.

## References

Droid-VM lists **SM8750 / A8xx** as in scope for drm2kgsl (see [references.md](references.md) row 9). Turnip in Mesa supports Adreno 830; integration is still **device-tested** work.

## Not in scope of this patch

- Exynos S25 models
- Changing hosted XNU VA layout (`0x2000000000` on S24) until probed on SM8750
- Wi‑Fi / camera / audio bridge re-validation (copy S24 procedure on S25)
