# MDE Audio Drivers — Virtual Stereo Audio Devices for macOS

Free macOS installer that creates up to **8 independent virtual stereo audio devices** based on [BlackHole](https://github.com/ExistentialAudio/BlackHole). Built for [MDE — Mix Desk EQ](https://adelvo.io/mix-desk-eq/), but works with any audio application.

## What it does

Each virtual device acts as a stereo audio cable: audio sent to the **output** appears at the **input** of the same device. This is what makes advanced audio routing possible — Mix Desk EQ (or any app) sends a submix to a virtual output, and your target app picks it up as a regular input.

## Included devices

| Device | Purpose |
|---|---|
| **MixDeskEQ System** | macOS system audio → MDE input |
| **MixDeskEQ WebRTC** | MDE mix → Browser / video conferencing |
| **MixDeskEQ Mix 3–8** | Additional outputs for OBS, recording, DAWs, etc. |

The installer lets you choose which devices to install via checkboxes. **2 devices are sufficient for most setups.**

## Install

1. Download the latest `.pkg` from [Releases](../../releases)
2. Double-click, authenticate, done
3. Click **Customize** to choose which devices to install

After installation, devices appear as regular audio inputs and outputs everywhere — System Settings, OBS, Zoom, DAWs, any CoreAudio app.

## Uninstall

An uninstaller `.pkg` is included in the release. It removes all MixDeskEQ audio devices and cleans up.

## Build from source

Requirements: Xcode Command Line Tools, Git

```bash
chmod +x build_installer.sh
./build_installer.sh
```

The script clones [BlackHole](https://github.com/ExistentialAudio/BlackHole), compiles 8 instances with custom names, and packages them as a standard macOS `.pkg` installer with a matching uninstaller.

## Why multiple devices?

Because each output bus in Mix Desk EQ can feed a different virtual device:

- **Bus 1** → speakers (physical)
- **Bus 2** → virtual device → OBS picks it up as mic input
- **Bus 3** → another virtual device → Zoom
- **Bus 4** → yet another → recording app

Each path is independent, each carries a different submix.

## License

GPL-3.0 — see [LICENSE](LICENSE)

Based on [BlackHole](https://github.com/ExistentialAudio/BlackHole) by [Existential Audio Inc.](https://existential.audio/)

## Links

- [MDE — Mix Desk EQ](https://adelvo.io/mix-desk-eq/) — Professional audio routing & mixer for macOS
- [Adelvo](https://adelvo.io) — Professional tools for live production and media workflows
