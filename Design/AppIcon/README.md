# Commander4Mac app icon

Selected by the user on October 16, 2026: option B, a midnight rounded tile with two folded cobalt and teal panes. The metaphor is two places open together. Keep the center gap clear, the silhouette substantial, and the composition balanced. Avoid lettering, tiny file lists, badges, faces, and competing symbols.

The original artwork was generated and refined with the built-in image generation tool. The retained production source is `master-unmasked.png`, a 1024 × 1024 lossless PNG. `script/render_icon.swift` prepares a classic macOS rounded tile and transparent exterior; `script/build_icon.sh` produces the iconset and `Resources/AppIcon.icns`. The source artwork remains unmasked. The final icon has no stray generated pixels outside its tile.

## Apple conventions

Use a simple centered symbol with clearly defined edges and verify recognition at small sizes. For modern layered icons, Apple recommends an opaque full-bleed square background and unmasked foreground layers, with system-provided corner masking and lighting. Keep editable layers for future material and appearance work. See [Apple app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons) and [Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

This delivery uses a flattened classic `.icns` suitable for the app’s macOS 15 minimum. It keeps the selected midnight appearance in both light and dark environments; it does not claim custom adaptive Dark/Mono renditions. Icon Composer presented a separate unaccepted agreement on this Mac, so no agreement was accepted and no `.icon` project is claimed.

## Sizes and formats

PNG representations use RGBA with transparent pixels outside the finished legacy tile. Every file is square. `@2x` represents Retina pixel density, as specified in [Apple’s iconset format](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/IconSetType.html).

| Logical size | 1× filename / pixels | 2× filename / pixels |
| --- | --- | --- |
| 16 pt | `icon_16x16.png`, 16 × 16 | `icon_16x16@2x.png`, 32 × 32 |
| 32 pt | `icon_32x32.png`, 32 × 32 | `icon_32x32@2x.png`, 64 × 64 |
| 128 pt | `icon_128x128.png`, 128 × 128 | `icon_128x128@2x.png`, 256 × 256 |
| 256 pt | `icon_256x256.png`, 256 × 256 | `icon_256x256@2x.png`, 512 × 512 |
| 512 pt | `icon_512x512.png`, 512 × 512 | `icon_512x512@2x.png`, 1024 × 1024 |

The ten PNG files live in `AppIcon.iconset`. macOS `iconutil` packs them into the multi-resolution `.icns`; `CFBundleIconFile` references `AppIcon` in the signed app bundle. The 1024-pixel representation is named `icon_512x512@2x.png`.

## Final generation prompt

Preserve the two large cobalt blue and teal folded folder panes and their side-by-side composition, crisp silhouette, satin finish, and restrained highlights. Use a continuous opaque full-bleed midnight-blue square background, with the symbol in the central area. No exterior corner mask, margin, rim, cast shadow, speckles, glow, border, text, letters, watermark, or extra objects. The legacy export pipeline applies its outer shape separately.
