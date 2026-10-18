#!/usr/bin/env bash
# BookFold offline guard.
#
# The BookFold app target must not contain ANY networking API, tracking or
# analytics SDK, or third-party dependency. This script is enforced in CI
# (.github/workflows/ci.yml) so the "100% local, no network code" promise
# in the README stays provable from the repository alone.
#
# If a future feature genuinely needs one of the banned symbols, that is a
# product decision: discuss it in an issue first, then update this guard
# AND the privacy documentation together.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

banned='URLSession|NSURLConnection|NSURLProtocol|NSStream|CFNetwork|CFStream|NWConnection|NWBrowser|NWListener|NWPathMonitor|WKWebView|SFSafariViewController|Firebase|Crashlytics|AppMetrica|Amplitude|Mixpanel|Segment|Sentry|AppsFlyer|Adjust|AdSupport|AppTrackingTransparency'

if grep -RInE "$banned" --include='*.swift' --include='*.h' --include='*.m' --include='*.mm' Sources/; then
  echo "::error::Networking or tracking API reference found in app sources" >&2
  fail=1
fi

if grep -qE '^[[:space:]]*packages:' project.yml; then
  echo "::error::project.yml declares Swift packages — dependencies need an offline review first (see CONTRIBUTING.md)" >&2
  fail=1
fi

for f in Package.swift Package.resolved; do
  if [ -e "$f" ]; then
    echo "::error::$f present — dependencies need an offline review first (see CONTRIBUTING.md)" >&2
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "Offline guard passed: no networking APIs, no tracking SDKs, no third-party dependencies."
fi
exit "$fail"
