# Contributing to BookFold

Thanks for your interest! BookFold is an offline-first, privacy-first open-source
book scanner. Before you start, please read the two rules that define this
project.

## The two hard rules

1. **Offline forever.** The app target must not contain networking APIs,
   analytics, trackers, or third-party dependencies — not even "optional"
   ones. CI enforces this via `scripts/check-no-network.sh`; if you genuinely
   believe an exception is needed, open an issue and discuss it first.
2. **CLA required.** Contributions are only accepted after signing the
   Contributor License Agreement (see below). A bot will ask you on your first
   pull request — it takes one click.

## Development setup

Requirements: Xcode 16 or newer, [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/hendkai/BookFold.git
cd BookFold
brew install xcodegen
xcodegen generate
open BookFold.xcodeproj
```

- The `*.xcodeproj` is **generated** from `project.yml` — never commit it, and
  make project changes in `project.yml`, not in Xcode.
- Minimum deployment target: iOS 17. Language: Swift 6, SwiftUI-first.
- Run the offline guard locally before pushing:
  `./scripts/check-no-network.sh`

## Pull requests

1. Fork / branch from `main`.
2. Keep PRs focused; describe what and why.
3. Make sure CI is green (build + offline guard).
4. Sign the CLA when the bot asks.

## Contributor License Agreement (CLA)

To keep BookFold dual-licensable (AGPL for everyone + optional commercial
licenses that fund development — see [DUAL-LICENSING.md](DUAL-LICENSING.md)),
every contributor signs a CLA:

- **Individual contributors:** [`.cla/CLA-INDIVIDUAL.md`](.cla/CLA-INDIVIDUAL.md)
- **Contributing on behalf of a company:** [`.cla/CLA-CORPORATE.md`](.cla/CLA-CORPORATE.md)

Signing happens directly in your pull request: the CLA Assistant bot posts a
comment, you reply with the signature line, done. Your code stays yours — the
CLA only grants the project the right to distribute it under AGPL *and*
commercial terms (see the CLA text for the exact scope).

## Conduct

Be kind and constructive. Bugs and feature ideas are welcome as issues with
steps to reproduce.
