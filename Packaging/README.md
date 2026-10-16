# Drag-to-Applications installation

As of October 16, 2026. This package is a signed local development preview with the stable development identity. It does not replace the production app or claim external distribution readiness.

## Visual design

The selected midnight icon sits on a quiet cool-white background with restrained navy typography and a teal directional arrow. Native Finder icons remain the interactive elements. Artwork never imitates a button or paints fake app/folder icons. Header: “Install Commander4Mac”. Main instruction: “Drag the app to Applications.” After copying: open the installed app, eject the image, then follow Full Disk Access setup.

| Element | Finder position / specification |
| --- | --- |
| Window | 720 × 480 pt, icon view, sidebar/toolbar/status bar requested hidden |
| App | (190, 232), 112 pt icon |
| Applications shortcut | (530, 232), symlink to `/Applications` |
| Directional arrow | Centered between icons, left to right |
| Native filename labels | 13 pt, below icons |
| Background | 720 × 480 PNG plus 1440 × 960 Retina PNG, combined into multi-resolution TIFF |

The rendering source is `render_background.swift`. Icons and labels are positioned with `dmg_settings.py`, using the [dmgbuild settings API](https://dmgbuild.readthedocs.io/en/latest/settings.html). Finder can retain a user’s path bar preference, so all essential artwork sits above that bottom area. The actual mounted Finder window must be checked after changing its bounds, icon sizes, text, or artwork.

## First launch

An app outside `/Applications` or the user’s `~/Applications` shows a dedicated install screen. It offers Show This App, Open Applications, and Quit This Copy. Install guidance appears before file services initialize, so a DMG copy does not load or overwrite the installed app’s workspace or operation marker. After copying, users open the app from Applications. Full Disk Access setup then identifies that installed bundle; the user enables it in System Settings and restarts if requested. A setup acknowledgement is never treated as proof of access.

## Build

```sh
python3 -m venv .build/packaging-venv
.build/packaging-venv/bin/python -m pip install -r Packaging/requirements.txt
./script/build_icon.sh
./script/build_and_run.sh --verify
./script/build_dmg.sh
```

The default output is `.build/distribution/Commander4Mac-Dev.dmg`. Optional arguments select the source app and output path. Packaging verifies the source app, preserves it with the tool’s native `ditto` workflow, creates a read-only compressed UDZO image, signs the image, and verifies its signature and container checksums.

For distribution beyond this Mac, complete the dependency licensing/relinking review and use a production archive. Apple’s [packaging guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) calls for signing nested code, notarizing the distribution container, stapling the ticket, and testing the packaged product. No notarization credentials or permission databases are changed by this build.
