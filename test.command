#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .test-work Cache
xcrun swiftc -swift-version 5 -module-cache-path Cache Source/Core.swift Tests/main.swift -o .test-work/check
.test-work/check "$PWD/.test-work" "$PWD/Templates"
