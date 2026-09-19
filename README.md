<p align="center">
  <img src="https://user-images.githubusercontent.com/14722250/93017676-1a009c00-f5fd-11ea-9b8e-c69c2cd4fa89.png" height=64 />
</p>

# eul

![Preview](https://user-images.githubusercontent.com/14722250/105626766-f718ab00-5e6c-11eb-9761-661ff85c8faf.jpg)

macOS menu bar system monitor. **Version 2.0.0** in this repository is an Apple Silicon–focused continuation of [gao-sun/eul](https://github.com/gao-sun/eul), maintained as the public line at **[wendyeq/eul2](https://github.com/wendyeq/eul2)** (install **`eul2.app`**, bundle ID **`com.wendyeq.eul2`**).

## Highlights

- Apple Silicon sensors (CPU/GPU temperature, fans, GPU usage, ANE, memory bandwidth where available)
- macOS 13+ menu bar extras, Big Sur–style widgets, and an **expanded interface** dropdown on recent macOS (Liquid Glass shell on macOS 27)
- Bluetooth battery per device, disk space plus live read/write rates, memory pressure, cumulative network totals
- Dark Mode, light/dark/auto appearance, VoiceOver-friendly labels, and preferences styled closer to System Settings
- Written in SwiftUI (as much as possible)

## OS and chip support

**This fork is Apple Silicon (`arm64`) only, minimum macOS 13.0** (2.0.0 was 12.0).

| | **Upstream gao-sun/eul 1.6.2** | **This fork 2.1.0** |
|---|---|---|
| CPU | Intel + Apple Silicon | Apple Silicon only |
| macOS | Older releases through Intel-capable versions | **13.0+** |
| Install | [Official release](https://github.com/gao-sun/eul/releases/tag/1.6.2) / Homebrew / App Store → **`eul.app`** | [wendyeq/eul2 Release](https://github.com/wendyeq/eul2/releases/latest) **`eul2.app.zip`**, or build from source → **`/Applications/eul2.app`** (not Homebrew) |

- **Intel Macs:** stay on **[gao-sun/eul 1.6.2](https://github.com/gao-sun/eul/releases/tag/1.6.2)** (or earlier). There is no `x86_64` slice in 2.0.0; Rosetta is not supported for this build.
- **Bundle ID:** 2.0.0 uses **`com.wendyeq.eul2`** (not `com.gaosun.eul`), so **`eul2.app`** can run alongside Homebrew’s **`eul.app`** (1.6.2) without fighting for the same identifier or preferences.
- **Build:** `ARCHS = arm64` only. Widgets, SharedLibrary, and SelfUpdate share the same deployment target.
- **Sensors on Apple Silicon:** temperatures and fan RPM use Apple Silicon SMC keys (`eul/Utilities/SMC.swift`) with `IOHIDEventSystemClient` fallback (`SmcControl.swift`) when keys are empty. Package memory temperature is not exposed on M-series the way Intel `MEM_SLOTS_PROXIMITY` was.

## Repositories

- **[gao-sun/eul](https://github.com/gao-sun/eul)** — original open-source project (last widely used Intel build: **1.6.2**).
- **[wendyeq/eul2](https://github.com/wendyeq/eul2)** — **this repository**; Apple Silicon **2.0.0** source and releases (`eul2.app`).

## What’s new in 2.0.0 vs 1.6.2

Compared to **[gao-sun/eul 1.6.2](https://github.com/gao-sun/eul/releases/tag/1.6.2)** (last upstream build aimed at Intel + older Apple Silicon support):

### Platform

- **Apple Silicon only** — drops Intel SMC/SP78 paths; targets M-series IOKit / SMC / IOReport instead.
- **Minimum macOS 12** across app, widgets, and helpers.

### Menu bar and dropdown

- **Expanded status menu** (keyboard-focusable panel) with **Liquid Glass** styling on macOS 27; flatter rows, header actions (preferences, quit, pin menu open).
- **Four-column network grid** in the menu (live up/down plus session/today/boot totals where enabled).
- **Process lists** for CPU, memory, and network with Finder / kill actions; **pin a process to the top of a section** without dismissing the menu (list pin, not “bring app forward”).
- **Cumulative network traffic** shown by default in extras/menu where configured.
- **Compact two-line status extras** driven by your component chips (upload/download on network extra, and related layout fixes).
- Menu bar **visibility** aligned with System Settings → Menu Bar (`isVisible`, user-controlled show/hide).

### Metrics and hardware

- **Apple Silicon:** CPU/GPU temperature, fan RPM, GPU utilization, **ANE** activity, memory **bandwidth** (when IOReport exposes it).
- **Memory pressure** (VM pressure style readout in menu).
- **Disk:** used/available space plus **live read/write rates**; per-volume selection in preferences.
- **Battery:** improved **time-to-full / time-to-empty** style readouts using IOPS fields where available.
- **Bluetooth:** **one row per device** with battery level in the menu block.

### Preferences and system fit

- Preferences window **chrome** closer to System Settings (sidebar material, grouped inset rows).
- **Appearance:** light / dark / **automatic** (follows macOS when set to auto).
- **Components** page: list + switches (not capsule strips) for status bar and per-metric text toggles; drag to reorder.
- Form controls: **mini switches**, trailing alignment, single-line labels (System Settings–like rows).
- **SF Symbols** and template-friendly menu bar icons; accessibility/contrast pass on key controls.

### Widgets

- **GPU widget** and `containerBackground` alignment with current widget APIs.

### Not in 2.0.0 (unchanged intent vs this fork’s scope)

- No return to **Intel** builds.
- No fan **control** (monitoring only), no BLE GATT battery recovery, no notarized Developer ID build in-tree.
- Fan curves, sensor walls, public IP, Bartender-style hiding, and full historical CSV export remain out of scope.

## Installation

### 2.0.0 (Apple Silicon, this fork) — **`eul2.app`**

**Homebrew does not install 2.0.0.** The `eul` cask still points at **[gao-sun/eul 1.6.2](https://github.com/gao-sun/eul/releases/tag/1.6.2)** and installs **`/Applications/eul.app`**.

To run **2.0.0** alongside (or instead of) that build:

1. On an **Apple Silicon** Mac (**macOS 13+**), open `eul.xcodeproj` and build the **eul** scheme (Release), or use a prebuilt `eul.app` from someone who built this tree.
2. Ad-hoc sign if needed: `CODE_SIGN_IDENTITY=-` (not notarized; no Developer ID in-tree).
3. Copy the product to **`/Applications/eul2.app`** (rename on copy — the Xcode product folder is still named `eul.app`, but the installed name must be **`eul2.app`** so it does not overwrite Homebrew’s `eul.app`).
4. First launch: if macOS blocks the app, **right-click → Open** once (Gatekeeper for ad-hoc builds), or allow in **System Settings → Privacy & Security**.
5. In preferences, the app reports version **2.0.0**; update checks and the GitHub button use **[wendyeq/eul2](https://github.com/wendyeq/eul2)** (after a Release is published there).

You can keep **`/Applications/eul.app`** (1.6.2) for Intel-era workflows on another machine, or uninstall it on Apple Silicon if you only need 2.0.0. Only one should own the menu bar at a time.

### 1.6.2 (Intel + official Homebrew / App Store) — **`eul.app`**

```bash
brew install --cask eul
```

This installs upstream **1.6.2**, not 2.0.0. You can also download [gao-sun/eul 1.6.2](https://github.com/gao-sun/eul/releases/tag/1.6.2) directly. App Store builds may omit SMC-based features and lag behind source releases.

### Release notes

[gao-sun/eul releases](https://github.com/gao-sun/eul/releases/latest) — tags through **1.6.x** (Intel / Homebrew). **2.0.0** ships from **[wendyeq/eul2 releases](https://github.com/wendyeq/eul2/releases/latest)** as **`eul2.app.zip`** (not via Homebrew until a cask is added separately).

## Contributors

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tr>
    <td align="center"><a href="https://github.com/XaoflySho"><img src="https://avatars3.githubusercontent.com/u/13835089?v=4?s=48" width="48px;" alt=""/><br /><sub><b>XaoflySho</b></sub></a><br /><a href="https://github.com/gao-sun/eul/commits?author=XaoflySho" title="Code">💻</a></td>
    <td align="center"><a href="https://github.com/akeschmidi"><img src="https://avatars1.githubusercontent.com/u/10963753?v=4?s=48" width="48px;" alt=""/><br /><sub><b>akeschmidi</b></sub></a><br /><a href="#translation-akeschmidi" title="Translation">🌍</a></td>
    <td align="center"><a href="http://artkost.ru/"><img src="https://avatars2.githubusercontent.com/u/62051?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Nikolay Kostyurin</b></sub></a><br /><a href="#translation-JiLiZART" title="Translation">🌍</a></td>
    <td align="center"><a href="http://jesusm.github.io/"><img src="https://avatars3.githubusercontent.com/u/752469?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Jesus</b></sub></a><br /><a href="#translation-JesusM" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/kant"><img src="https://avatars1.githubusercontent.com/u/32717?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Darío Hereñú</b></sub></a><br /><a href="#translation-kant" title="Translation">🌍</a></td>
    <td align="center"><a href="http://opensource.generali-cloud.net/"><img src="https://avatars2.githubusercontent.com/u/25303664?v=4?s=48" width="48px;" alt=""/><br /><sub><b>R. Fuehrer</b></sub></a><br /><a href="#translation-rfuehrer" title="Translation">🌍</a></td>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/jorgeclaro"><img src="https://avatars2.githubusercontent.com/u/10659042?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Jorge Claro</b></sub></a><br /><a href="#translation-jorgeclaro" title="Translation">🌍</a></td>
    <td align="center"><a href="https://medium.com/@zorig"><img src="https://avatars0.githubusercontent.com/u/1277672?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Zorig</b></sub></a><br /><a href="#translation-Zorig" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/lill74"><img src="https://avatars2.githubusercontent.com/u/12353597?v=4?s=48" width="48px;" alt=""/><br /><sub><b>lill74</b></sub></a><br /><a href="#translation-lill74" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/strafe"><img src="https://avatars0.githubusercontent.com/u/15663890?v=4?s=48" width="48px;" alt=""/><br /><sub><b>strafe</b></sub></a><br /><a href="#translation-strafe" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/AndyH0ng"><img src="https://avatars0.githubusercontent.com/u/60703412?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Andy Hong</b></sub></a><br /><a href="#translation-AndyH0ng" title="Translation">🌍</a></td>
    <td align="center"><a href="https://treastrain.jp/"><img src="https://avatars2.githubusercontent.com/u/13805382?v=4?s=48" width="48px;" alt=""/><br /><sub><b>treastrain / Tanaka Ryoga</b></sub></a><br /><a href="#translation-treastrain" title="Translation">🌍</a></td>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/baptistecdr"><img src="https://avatars3.githubusercontent.com/u/11665396?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Baptiste C.</b></sub></a><br /><a href="#translation-baptistecdr" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/b3z"><img src="https://avatars2.githubusercontent.com/u/47346598?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Luca</b></sub></a><br /><a href="#translation-b3z" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/40uf411"><img src="https://avatars0.githubusercontent.com/u/29804103?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Ali AOUF &#124; علي عوف</b></sub></a><br /><a href="#translation-40uf411" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/sboh1214"><img src="https://avatars0.githubusercontent.com/u/30364442?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Seungbin Oh</b></sub></a><br /><a href="#translation-sboh1214" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/nrudnyk"><img src="https://avatars.githubusercontent.com/u/20221382?v=4?s=48" width="48px;" alt=""/><br /><sub><b>nrudnyk</b></sub></a><br /><a href="#translation-nrudnyk" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/kawarimidoll"><img src="https://avatars.githubusercontent.com/u/8146876?v=4?s=48" width="48px;" alt=""/><br /><sub><b>カワリミ人形</b></sub></a><br /><a href="https://github.com/gao-sun/eul/commits?author=kawarimidoll" title="Documentation">📖</a></td>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/ivyjsgit"><img src="https://avatars.githubusercontent.com/u/34287279?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Ivy Jackson</b></sub></a><br /><a href="https://github.com/gao-sun/eul/commits?author=ivyjsgit" title="Code">💻</a></td>
    <td align="center"><a href="https://github.com/J-rg"><img src="https://avatars.githubusercontent.com/u/4042863?v=4?s=48" width="48px;" alt=""/><br /><sub><b>J-rg</b></sub></a><br /><a href="#translation-J-rg" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/jevonmao"><img src="https://avatars.githubusercontent.com/u/64660730?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Jevon Mao</b></sub></a><br /><a href="https://github.com/gao-sun/eul/commits?author=jevonmao" title="Code">💻</a></td>
    <td align="center"><a href="https://github.com/Tekrific"><img src="https://avatars.githubusercontent.com/u/68393566?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Tekrific</b></sub></a><br /><a href="#translation-Tekrific" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/nebeker"><img src="https://avatars.githubusercontent.com/u/8558191?v=4?s=48" width="48px;" alt=""/><br /><sub><b>nebeker</b></sub></a><br /><a href="#translation-nebeker" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/DMNerd"><img src="https://avatars.githubusercontent.com/u/7889445?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Adam</b></sub></a><br /><a href="#translation-DMNerd" title="Translation">🌍</a></td>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/stosumarte"><img src="https://avatars.githubusercontent.com/u/64950825?v=4?s=48" width="48px;" alt=""/><br /><sub><b>stosumarte</b></sub></a><br /><a href="#translation-stosumarte" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/gnehs"><img src="https://avatars.githubusercontent.com/u/16719720?v=4?s=48" width="48px;" alt=""/><br /><sub><b>gnehs</b></sub></a><br /><a href="#translation-gnehs" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/Animenosekai"><img src="https://avatars.githubusercontent.com/u/40539549?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Animenosekai</b></sub></a><br /><a href="#translation-Animenosekai" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/soewaiyanmyowin"><img src="https://avatars.githubusercontent.com/u/38293630?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Soe Wai Yan Myo Win</b></sub></a><br /><a href="#translation-soewaiyanmyowin" title="Translation">🌍</a></td>
    <td align="center"><a href="http://www.studio83.cz/"><img src="https://avatars.githubusercontent.com/u/9982805?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Vojtěch Kaizr</b></sub></a><br /><a href="#translation-wojtishek" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/thewqer"><img src="https://avatars.githubusercontent.com/u/64782240?v=4?s=48" width="48px;" alt=""/><br /><sub><b>wqer</b></sub></a><br /><a href="#translation-thewqer" title="Translation">🌍</a></td>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/sn0wmem0ry"><img src="https://avatars.githubusercontent.com/u/84455611?v=4?s=48" width="48px;" alt=""/><br /><sub><b>sn0wmem0ry</b></sub></a><br /><a href="#translation-sn0wmem0ry" title="Translation">🌍</a></td>
    <td align="center"><a href="https://github.com/daimajia"><img src="https://avatars.githubusercontent.com/u/2503423?v=4?s=48" width="48px;" alt=""/><br /><sub><b>代码家</b></sub></a><br /><a href="https://github.com/gao-sun/eul/commits?author=daimajia" title="Code">💻</a></td>
    <td align="center"><a href="https://github.com/bitigchi"><img src="https://avatars.githubusercontent.com/u/2769571?v=4?s=48" width="48px;" alt=""/><br /><sub><b>Emir Sarı</b></sub></a><br /><a href="#translation-bitigchi" title="Translation">🌍</a></td>
  </tr>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

## Language Support

```swift
let languages = [
  "简体中文", "English", "Arabic",
  "Deutsch", "Русский", "Español",
  "Português", "Монгол", "한국어",
  "日本語", "Français", "Українська",
  "Svenska", "Čeština", "Italiano",
  "繁體中文", "မြန်မာဘာသာ", "Magyar",
  "ไทย", "Türkçe"
];
```

## 更改记录

见 [CHANGELOG.md](CHANGELOG.md)（**2.0.0** 相对上游 **1.6.2**）。

## License

MIT — 本项目延续 [gao-sun/eul](https://github.com/gao-sun/eul)（见上游 [LICENSE](https://github.com/gao-sun/eul/blob/master/LICENSE)）；2.0 非 Gao Sun 官方发布。
