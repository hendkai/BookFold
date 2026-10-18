# UVDoc → Core ML model conversion

Rebuilds `Resources/Models/UVDocGrid_fp16.mlpackage` from the original UVDoc
checkpoint. The app ships only the converted model; the checkpoint itself is
not redistributed in this repository.

Licenses: see `../../THIRD_PARTY_NOTICES.md`. UVDoc is MIT (`UVDoc-LICENSE.txt`);
`convert_uvdoc.py` is adapted from DDScanner (Apache-2.0, `LICENSE-APACHE-2.0.txt`,
`NOTICE-DDScanner.md`).

## Reproduce

```bash
git clone https://github.com/tanguymagne/UVDoc /tmp/UVDoc
python3 -m venv .venv-uvdoc && . .venv-uvdoc/bin/activate
pip install torch numpy coremltools     # tested: torch 2.8.0, coremltools 9.0, Python 3.9

python Tools/ModelConvert/convert_uvdoc.py \
    --uvdoc-source /tmp/UVDoc \
    --weights /tmp/UVDoc/model/best_model.pkl \
    --output Resources/Models/UVDocGrid_fp16.mlpackage \
    --verify
```

Before converting, check that the checkpoint hash is
`7e90861b8a516eb4bc51f84bd889cb77275743d2d1d3ca8091951ec9f2b7da23`
(the script prints it under "来源取证").

`--verify` runs PyTorch and Core ML on the same fixed input and aborts if the
grid error exceeds the tolerance in the script (FP16: 0.03).

## Contract

- Input: `image`, Float32 `1 x 3 x 712 x 488`, RGB in [0, 1], NCHW.
- Outputs: `point_positions2D` (`1 x 2 x 45 x 31`, FP16 on disk) is the sampling grid
  in normalized [-1, 1] coordinates, channel 0 = x, channel 1 = y, align_corners = true.
  `point_positions3D` is unused by the app.
- Resampling is **not** in the model. `DewarpGrid.swift` / `DewarpResampler`
  do it in Float32 on the CPU. Putting `grid_sample` in the FP16 model would
  add large pixel errors.

## Measured (this Mac, coremltools predict, ComputeUnit.ALL)

- Model size: 15 MB on disk.
- Median predict time: 6.7 ms (min 5.5 ms). This is a Mac, not an iPhone.
- Full dewarp of a 1700×2400 page (`swiftc -O`, same Swift sources, Mac host): 0.13–0.16 s, after warm-up.
- Synthetic curled text page (`curvature 28 px`, see `UVDocDewarperTests`): line bow goes from
  14.9 px to 3.2 px. Flat page: 0 px before and after.

Device numbers (iPhone, P50/P95 per stage) are still outstanding. See `docs/capture-engine.md`.
