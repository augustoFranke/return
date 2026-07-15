# Return

**Ultra-low-latency in-ear monitoring for macOS.**

Return routes your microphone to your headphones in real time so you can hear
yourself while you speak, sing, stream, or record — without paying for a
closed-source monitor utility.

It is designed for **one of the smallest software delays** among open-source
projects with the same purpose: native Core Audio HAL I/O, 32-frame device
buffers when the hardware allows, and a lock-free C ring buffer that keeps the
software bridge tight.

## Why Return is fast

Most “mic monitor” tools sit on higher-level audio APIs or keep larger safety
buffers. Return goes lower:

| Design choice | What it does |
| --- | --- |
| Core Audio **HAL** units | Direct input/output paths, no AVAudioEngine graph overhead |
| Preferred **32-frame** buffers | ~0.7 ms per buffer at 48 kHz when the device accepts it |
| Compact software bridge | Target fill ≈ 4× the larger device buffer (often ~128 frames) |
| Lock-free C ring buffer | Capture and render callbacks stay light and real-time safe |

On cooperative hardware, that stack is among the **lowest-latency open-source
software monitors** available for macOS — close enough that the remaining delay
is mostly the interface, converters, and headphones themselves.

> Actual latency depends on your interface and sample rate. Return requests the
> smallest buffer size the device will take and restores the previous sizes when
> monitoring stops.

## Install

1. Download **`Return.dmg`** from the
   [latest release](https://github.com/augustoFranke/return/releases/latest).
2. Open the DMG and drag **Return** into **Applications**.
3. Launch Return and allow **Microphone** access when macOS asks.

The app is a menu-bar accessory (`LSUIElement`). Click the mic icon to open
the panel.

> The release is ad-hoc signed, not notarized. If Gatekeeper blocks the first
> launch: **Control-click** the app → **Open** → confirm.

## Use

1. Plug in headphones (or choose them as the system output).
2. Select your mic as the system input if needed.
3. Click the menu-bar icon → turn **Monitoring** on.
4. Adjust **Volume** so you hear yourself clearly without feedback.

Input and output must share the same sample rate (Return will refuse mismatched
rates rather than introduce resampling latency).

## Features

- Real-time mic → headphones monitoring
- Menu-bar UI: monitoring toggle + volume
- Native Swift + Core Audio (macOS 14+)
- No account, no network, no telemetry
- Restores original device buffer sizes on stop

## Build from source

Requires macOS 14+ and Xcode command-line tools.

```sh
# Build, package Return.app, and write Return.dmg (no install)
./build.sh package

# Same, then install to /Applications
./build.sh
```

Run tests:

```sh
swift test
```

## Architecture (short)

```
Microphone ──► AUHAL input ──► C ring buffer ──► AUHAL output ──► Headphones
                 (32 frames)   (target fill)       (32 frames)
```

Sources live under `Sources/` (Swift UI + HAL bridge) and `NativeAudio/` (C ring
buffer). See `Package.swift` for the SwiftPM layout.

## License

[MIT](LICENSE) — free to use, modify, and distribute.
