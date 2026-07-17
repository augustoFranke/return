# Return

**Ultra-low-latency in-ear monitoring for macOS.**

Return routes your microphone to your headphones in real time so you can hear
yourself while you speak, sing, stream, or record — without paying for a
closed-source monitor utility.

It is designed for **one of the smallest software delays** among open-source
projects with the same purpose: native Core Audio HAL I/O, device-minimum
buffers (often 15 frames), and a lock-free C ring buffer that keeps the
software bridge tight.

## Why Return is fast

Most “mic monitor” tools sit on higher-level audio APIs or keep larger safety
buffers. Return goes lower:

| Design choice | What it does |
| --- | --- |
| Core Audio **HAL** units | Direct input/output paths, no AVAudioEngine graph overhead |
| **Device-minimum** buffers | Asks each device for its smallest buffer (often 15 frames ≈ 0.3 ms at 48 kHz) |
| Adaptive software bridge | Target fill starts at input + output buffer (often ~30 frames) and grows only if the machine underruns |
| Same-device passthrough | Mic and output on the same device: one HAL unit, one IO cycle, no jitter buffer at all |
| Lock-free C ring buffer | Capture and render callbacks stay light and real-time safe |

On cooperative hardware, that stack is among the **lowest-latency open-source
software monitors** available for macOS — close enough that the remaining delay
is mostly the interface, converters, and headphones themselves.

Measured on an M-series MacBook Pro with a USB interface at 48 kHz: 15-frame
device buffers on both sides and a steady bridge fill of ~22–30 frames, for a
software path of roughly **1.3 ms** (down from ~4 ms in Return 1.0). With mic
and output on one duplex device, the bridge collapses to a single IO cycle
(~0.3 ms). If a machine can't sustain that margin, the bridge widens itself in
1.5× steps instead of crackling — latency stays as low as the hardware allows.

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
                (device min)  (adaptive fill)     (device min)
```

When the default input and output are the same device, Return collapses this
to a single AUHAL unit and copies mic to output inside one IO cycle.

Sources live under `Sources/` (Swift UI + HAL bridge) and `NativeAudio/` (C ring
buffer). See `Package.swift` for the SwiftPM layout.

## License

[MIT](LICENSE) — free to use, modify, and distribute.
