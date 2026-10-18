# BookFold

**Scan books into a local, private virtual library — 100 % offline.**

BookFold turns your iPhone into a book scanner: photograph pages (flat sheets or
two-page spreads of an open book), let BookFold detect the page edges and
correct the perspective, and collect the scans as a "virtual book" in your
on-device library.

> **Status: early development.** The geometry capture engine (edge detection,
> perspective correction, spread splitting, session-to-book persistence) is
> implemented and unit-tested — see
> [`docs/capture-engine.md`](docs/capture-engine.md). Page dewarping for
> curved open books and the full library/reader experience are next. There is
> no App Store release yet.

## Privacy: offline by design

- **No network code at all.** The app contains no networking APIs, no
  analytics, no trackers, and talks to no server — ever.
- **Zero third-party dependencies.** No SDK can phone home because no SDK is
  linked into the app target.
- **This is provable from the repository:** CI runs
  [`scripts/check-no-network.sh`](scripts/check-no-network.sh) on every push
  and pull request and fails the build if any networking or tracking API, or
  any dependency, appears in the app target.
- Your scans live in the app's local container. There is no cloud, no account,
  no telemetry.

## Roadmap

1. ✅ Capture engine: live edge detection, auto-capture, perspective
   correction (`docs/capture-engine.md`)
2. ✅ Two-page spread scanning with automatic page ordering
3. Page dewarping for curved open books
4. Library & reader experience

## Capture engine in one minute

- **Live scanning:** `AVCaptureSession` + `VNDetectRectanglesRequest` with a
  live edge overlay; the shutter fires itself once the page holds still for
  ~1 s, and re-arms when you turn the page.
- **Perspective & illumination:** detected rectangle → `CIPerspectiveCorrection`
  → border-based white balance + gentle contrast shaping for a clean
  "scanned page" look.
- **Two-page spreads:** the detected rectangle is split at the midline and
  each half is corrected independently — one shot of an open book yields two
  consecutive pages in reading order.
- **Session → book:** finishing a scan creates a `Book` with ordered pages in
  the local SwiftData store; page JPEGs live in the app container. Nothing
  ever leaves the device.
- **Simulator-friendly:** no camera? Import photos — they run through the
  exact same pipeline (also how the unit tests exercise it).

Run the tests: `xcodegen generate && xcodebuild test -scheme BookFold`.

## Building from source

Requirements: Xcode 16 or newer, [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open BookFold.xcodeproj   # then run the "BookFold" scheme on an iOS Simulator
```

The `*.xcodeproj` is generated from `project.yml` and intentionally not
committed. CI (macOS runner) does exactly the same: `xcodegen generate`, then
`xcodebuild` against the iOS Simulator with code signing disabled.

## License

BookFold is free software, licensed under the
[GNU AGPL v3.0 or later](LICENSE) (`AGPL-3.0-or-later`).

Private and internal use is free. If you want to distribute BookFold as part
of a commercial product or embed it in proprietary software, a commercial
license is available — see [DUAL-LICENSING.md](DUAL-LICENSING.md) and
[COMMERCIAL-LICENSING.md](COMMERCIAL-LICENSING.md).

Contributions require signing the CLA — see
[CONTRIBUTING.md](CONTRIBUTING.md).

---

Copyright (C) 2026 BookFold Project / Hendrik Kaiser.
BookFold is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE. See the [license](LICENSE) for details.
