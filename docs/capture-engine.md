# Capture Engine v2 (Geometry + UVDoc Dewarp)

Status: **implemented** — live edge detection, auto-capture, perspective
correction, UVDoc non-linear dewarping (Core ML, optional stage), illumination
normalization, two-page spread splitting, session → SwiftData book persistence.
Dewarping is opt-in per pipeline (`ScanPipeline(dewarper:)`); the app passes a
`UVDocDewarper`, tests keep the geometry-only path. Curvature survives in the
geometry-only pipeline by design
(see [Curved pages](#curved-pages-expected-behavior)).

## Pipeline

```
AVCaptureSession (photo preset, portrait, ~12 Vision analyses/s)
  └─ VNDetectRectanglesRequest → Quad (normalized, bottom-left origin)
       └─ StabilityTracker (hold still 1.1 s → auto-capture; re-arms on
          page turn = rectangle lost or clearly replaced)
            └─ AVCapturePhotoOutput full-res still
                 └─ ScanPipeline.processPages(source:quad:mode:)
                      ├─ single page:  quad → CIPerspectiveCorrection → 1 page
                      └─ spread:       Quad.split(0.5) → L/R halves,
                                      each → CIPerspectiveCorrection → 2 pages
                                      (reading order: image-left first)
                 └─ per page: UVDoc dewarp (optional, Core ML → 45×31 grid → Float32 resample,
                    see below; falls back to the geometry-only page on any failure)
                 └─ per page: illumination normalization
                      (border white balance → contrast 1.06 / saturation 0.85)
                 └─ long edge capped at 2400 px (never upscaled, Lanczos)
  Session → Book (SwiftData) + Page JPEGs (Application Support/BookFoldPages)
```

## Coordinate conventions (the part that always goes wrong)

| Space | Origin | Used by |
|---|---|---|
| Vision normalized | bottom-left | `VNDetectRectanglesRequest`, `Quad` |
| CoreImage pixels | bottom-left | `CIPerspectiveCorrection` inputs |
| Layer/view points | top-left | edge overlay drawing |

Only two conversions exist: `Quad.pixelPoints(in:)` (multiply by pixel size,
no flip) and `Quad.layerPoints(in:)` (multiply + y-flip). Both are unit-tested
(`QuadTests.testPixelPointsMapToCoreImageSpace`, `testLayerPointsFlipYAxis`).

The preview layer uses `.resizeAspect` (not aspect-fill) so normalized
coordinates map 1:1 onto the visible frame — the overlay is exact, at the
cost of possible letterboxing.

## Auto-capture state machine (`StabilityTracker`)

- `searching → tracking`: any plausible rectangle appears.
- `tracking → captured`: all four corners within `0.03` (normalized) of the
  reference for `1.1 s` → **fires once**.
- `captured → tracking` (re-arm, "page turned") when either
  - the rectangle is lost for `> 0.35 s` (hand/page passing), or
  - a new rectangle with bounding-box IoU `< 0.55` vs the captured one.
- Manual shutter calls `markCaptured` so auto-capture doesn't double-fire.

Known limit: a page turn where the rectangle never disappears *and* stays in
the same place (IoU stays high) will not re-arm automatically — use the
manual shutter. Real page turns almost always break tracking briefly.

## Spread splitting & page order

Splitting happens in **quad space before perspective correction**: the top
and bottom edges are interpolated at the midline, and each half is corrected
independently from the full-resolution source. Both pages get their own clean
rectangle, a straight spine and symmetric margins.

Reading order: the half with the smaller centroid x comes first (image-left =
earlier page for an upright open book). Assumption (v1): the book is
photographed upright with a vertical spine. 90°-rotated spreads are not
detected yet.

## Illumination normalization ("book page look")

1. Average the four thin border strips of the corrected page (paper margin
   = illuminant estimate).
2. Per-channel gains: brightest channel is the target, all channels
   brightened toward it, clamped to `[1.0, 1.6]` — never darkens.
3. `CIColorControls`: contrast 1.06, saturation 0.85, brightness +0.02.

## VisionKit (`VNDocumentCameraViewController`) — evaluated, not used

Checked as the card requested. Reasons to stay on the custom pipeline:

- VisionKit delivers *finished* scans in a modal; the app gets **no live
  rectangle data**, so no live edge overlay and no stability-based
  auto-capture UX.
- No access to the detected quad → **no two-page spread splitting** in quad
  space, which is the core of this milestone.
- Output is VisionKit's own cropped/enhanced images; no control over
  illumination normalization or resolution policy.
- Not available in the Simulator → would block the import-based test path.

A `DataScannerViewController`-style custom session is also what comparable
open-source scanners (e.g. DDScanner) do. Decision: custom pipeline; VisionKit
remains a possible "quick single page" fallback in a future card if users ask
for it.

## Curved pages (expected behavior)

v1 is geometry-only: perspective is removed, **curvature survives**. The unit
test `PerspectiveCorrectorTests.testCurvedPageKeepsCurvatureWhileRemovingPerspective`
renders the same synthetic page flat and curled (28 px bow, perspective-warped
photo with known quad), runs both through the identical pipeline and measures
the bow of a text line in the output:

- flat control: bow < 1 % of page height (comes out flat),
- curved page: bow > 2 % of page height, ≥ 3× the flat control (survives).

Measured in the test suite (bow = max deviation from the chord over the
10–90 % text span, fraction of page height):

- flat control: 0.13 %,
- curved page: 2.09 %, analytic ground truth 2.42 % (28 px × (1 − sin 0.1π) / 800 px),
  i.e. ~86 % of the curl survives the resampling. The 2 % floor passes with
  little margin — tighten only after measuring on real photos.

## Non-linear dewarp (UVDoc, Core ML)

- `Resources/Models/UVDocGrid_fp16.mlpackage`: UVDoc (MIT) converted with
  `Tools/ModelConvert/convert_uvdoc.py`. Input 1×3×712×488 RGB float, output
  two sampling grids (45×31). Model: 15 MB, FP16. Licenses: `THIRD_PARTY_NOTICES.md`.
- `UVDocDewarper` runs the network on the corrected page, resized to 488×712.
  `DewarpResampler` (Float32, CPU) then resamples the full-resolution corrected
  page through the upsampled grid (bilinear, align_corners = true). Source
  positions outside the page are paper-white, not black.
- Synthetic result (`UVDocDewarperTests`, curl 28 px on 800 px page): line bow
  before 14.9 px → after 3.2 px (numbers in `Tools/ModelConvert/README.md`).
  Flat page: no change (bow stays < 1 %).
- Host timing (Mac, `-O`, full 1700×2400 page incl. model predict): 0.13–0.16 s.
  Not an iPhone number.
- **Not verified yet:** real curved book photos, on-device latency
  (< 2 s/page target), memory on iPhone, and the iOS XCTest run (the simulator
  test runner was unavailable on the build host). Those need a device run.

## Known limits (v1)

- **Aspect of strongly keystoned quads.** The plan estimates page aspect from
  the mean of opposite edge lengths. For a ~12 % per-side trapezoid this is
  ~3 % off (0.774 measured vs 0.75 ground truth). Axis-aligned pages recover
  the aspect exactly (`testAxisAlignedPageRecoversAspectExactly`). A
  homography-based aspect estimate is a candidate follow-up.
- **Dewarp is a learned approximation.** UVDoc was trained on Doc3D-style
  synthetic warps plus real photos. Evaluated here only on synthetic curled
  text; residual curl remains near the top and bottom page edges. Check on
  real photos before relying on it for scholarly scans.
- **Illumination needs an unmanaged CIContext.** White-balance gains are
  computed from gamma-encoded border values, so the chain must run with
  `Illumination.makeContext()` (working color space NSNull). A default,
  linear-light context leaves a color cast (solid warm test image came out
  (153, 141, 127) instead of neutral).

## Simulator testing (no camera)

`ScanView` detects a missing camera and switches to an import-centric UI.
"Import photo" (PHPicker) runs the *exact same* pipeline:
`DocumentDetector.bestQuad(in: CGImage)` (whole-image Vision pass) →
`ScanPipeline.processPages`. If no rectangle is found the full frame is used
and the UI says so. This keeps capture-engine development and CI fully
Simulator-capable.

## Storage

- SwiftData `Book` (id, title — editable in the library, createdAt) and
  `Page` (index, fileName), cascade delete.
- JPEG files (q=0.85) in `Application Support/BookFoldPages/<book-uuid>/`,
  plain `FileManager` — no iCloud, no CloudKit, no file provider, no network
  (enforced by `scripts/check-no-network.sh` in CI).

## Tests

`xcodebuild test -scheme BookFold` covers:

- quad math: canonical corner ordering, degenerate rejection, split, both
  coordinate conversions, similarity/IoU
- stability: fire after 1.1 s, jitter tolerance, movement resets, no
  double-fire, both re-arm paths, manual-capture suppression
- spread: halves geometry, reading order (incl. mirrored scene), area
  conservation, pixel mapping; end-to-end spread → 2 ordered pages with
  left/right markers
- perspective: plan math (no upscale, long-edge cap), flat-page round-trip
  (paper corners white), curved-page behavior above
- illumination: gain math, clamps, neutral round-trip, border average
- persistence: session → book with gap-free ordered indices, files on disk,
  rename, delete cleanup
- Vision: rectangle detection on a synthetic photo vs ground truth
