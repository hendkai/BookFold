# Third-party notices

BookFold itself is licensed under AGPL-3.0-or-later (see LICENSE). The
components below are included in or used to build this repository. Each
keeps its own license; nothing here changes the terms of BookFold.

## 1. UVDoc — dewarp network (bundled model)

- **Used as:** non-linear page dewarping stage (`Sources/BookFold/Features/Scan/Geometry/UVDocDewarper.swift`).
- **Shipped as:** `Resources/Models/UVDocGrid_fp16.mlpackage` (Core ML, FP16, input 1×3×712×488, outputs a 45×31 sampling grid).
- **Derived from:** `model/best_model.pkl` and `model.py` of https://github.com/tanguymagne/UVDoc
  (paper: Floor Verhoeven, Tanguy Magne, Olga Sorkine-Hornung, *UVDoc: Neural Grid-based Document Unwarping*, SIGGRAPH Asia 2023).
- **Checkpoint sha256:** `7e90861b8a516eb4bc51f84bd889cb77275743d2d1d3ca8091951ec9f2b7da23`.
- **License:** MIT. Full text in `Tools/ModelConvert/UVDoc-LICENSE.txt`:

  > Copyright (c) 2023 Tanguy MAGNE
  > Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
  > THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND ...

- **Modifications:** the weights are unchanged. The checkpoint was re-serialised to Core ML and the
  `F.interpolate` + `F.grid_sample` resampling was moved out of the network into Swift (Float32), so the model only outputs sampling grids.
- **Compatibility with AGPL-3.0 and the commercial license:** MIT is compatible with AGPL-3.0 and permits
  sublicensing under other terms (e.g. the commercial license in COMMERCIAL-LICENSING.md), provided the copyright and
  permission notice above is retained. This notice must travel with every binary or source distribution that contains the model.

## 2. Model converter (Tools/ModelConvert/convert_uvdoc.py)

- **Adapted from:** `Tools/ModelConvert/convert_uvdoc.py` of https://github.com/daxmate/DDScanner
  (Copyright 2026 daxmate, Apache License 2.0). The adaptation changes the author metadata and the contract references.
- **License:** Apache-2.0. Full text in `Tools/ModelConvert/LICENSE-APACHE-2.0.txt`. DDScanner's NOTICE is in
  `Tools/ModelConvert/NOTICE-DDScanner.md`.
- **Compatibility:** Apache-2.0 is compatible with AGPL-3.0 (the converter is distributed as part of this AGPL project).
- DDScanner's app code is **not** used or copied. Only the converter script, which is not part of the app binary, was adapted.

## 3. Runtime dependencies

- **None.** BookFold's app target uses only Apple frameworks (Vision, Core Image, Core ML, SwiftData).
  The offline guard (`scripts/check-no-network.sh`) enforces this in CI.

## 4. Conversion toolchain (developer-only, not shipped)

- coremltools (BSD-3-Clause), PyTorch (BSD-3-Clause), NumPy (BSD-3-Clause). Used only to build the model. Not part of the app.
