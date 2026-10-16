#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
xcrun swift script/render_icon.swift Design/AppIcon/master-unmasked.png Design/AppIcon/AppIcon.iconset
/usr/bin/iconutil --convert icns --output Resources/AppIcon.icns Design/AppIcon/AppIcon.iconset
echo "Created Resources/AppIcon.icns and all ten PNG representations."
