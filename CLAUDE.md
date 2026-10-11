# CLAUDE.md

SimplyVidtor is a SwiftUI iOS video editor. See [PLAN.md](PLAN.md) for scope, architecture and milestones; keep its checkboxes up to date as work lands.

## Project facts

- Xcode 26.6, iOS deployment target **26.5**, iPhone + iPad (`TARGETED_DEVICE_FAMILY = 1,2`).
- Swift 5 language mode with **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** and approachable concurrency. Everything is main-actor by default: mark heavy work (thumbnailing, waveform, export) `nonisolated` or move it into an `actor`.
- Xcode project uses **synchronized folders** (objectVersion 77). New files dropped into `SimplyVidtor/`, `SimplyVidtorTests/` or `SimplyVidtorUITests/` are picked up automatically; do not hand-edit `project.pbxproj` to add files.
- Info.plist is generated. Add keys as `INFOPLIST_KEY_*` build settings, not a plist file.
- Bundle ID `sawko.SimplyVidtor`.

## Commands

Shortcuts: `make build`, `make test`, `make test-unit`, `make test-ui`. Underlying commands:

```bash
# Build
xcodebuild -project SimplyVidtor.xcodeproj -scheme SimplyVidtor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Unit + UI tests
xcodebuild -project SimplyVidtor.xcodeproj -scheme SimplyVidtor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Unit tests only
xcodebuild -project SimplyVidtor.xcodeproj -scheme SimplyVidtor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SimplyVidtorTests
```

## Code layout (target)

```
SimplyVidtor/
  App/            app entry, root navigation
  DesignSystem/   tokens (Color, Font, spacing) and shared components
  Features/
    Projects/     01 Projects
    MediaPicker/  04 Media Picker
    Editor/       02 Editor, timeline, tool panels (Speed, Filters, Text...)
    Export/       03 Export sheet, 08 Exporting, 09 Done
  Model/          SwiftData Project, Timeline, Clip, TextItem, AudioItem
  Engine/         composition builder, playback, thumbnails, waveform, exporter
```

## Conventions

- SwiftUI + `@Observable`; no Combine or `ObservableObject` in new code.
- `Timeline` and its parts are value types. The editor mutates a copy and pushes snapshots for undo/redo.
- Store derived values nowhere: clip timeline duration = `sourceDuration / speed`.
- Normalized (0...1) coordinates for overlay positions and crop rects.
- Every screen gets a `#Preview` with sample data.
- Use `Theme` tokens (`Theme.Palette`, `Typography`, `Spacing`, `Radius`, `Size`), never raw hex or magic numbers in views. Reuse `DesignSystem/` components before writing new chrome; add new ones to `ComponentGallery`.
- Debug builds launched with `-componentGallery` open the component gallery instead of the app.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) for unit tests; XCTest only for UI tests.
- App is dark-only for v1: set `.preferredColorScheme(.dark)` at the root.

## Design source (Figma)

File: https://www.figma.com/design/sjymzmXSpWxi9qBCKUPAom (key `sjymzmXSpWxi9qBCKUPAom`)

| Screen | Node |
|---|---|
| 01 Projects | `6:3` |
| 02 Editor | `6:93` |
| 03 Export sheet | `10:184` |
| 04 Media Picker | `12:309` |
| 08 Exporting | `12:399` |
| 09 Export Done | `12:433` |
| Components page | `3:2` |

05 Speed, 06 Filters and 07 Text Editing are not drawn yet; their specs are in PLAN.md M3/M4.

Design is drawn at 393×852 in Inter as a stand-in; **use SF Pro (system font) in code.** Icons in Figma are Lucide-style; map them to SF Symbols (`scissors`, `gauge.with.dots.needle.50percent`, `speaker.wave.2`, `camera.filters`, `slider.horizontal.3`, `textformat`, `music.note`, `crop`, `plus.square.on.square`, `trash`).

### Logo and app icon

Sources live in `Branding/` (outside the app target, so they are not bundled). `app-icon.svg` / `app-icon-tinted.svg` are the masters for `AppIcon.appiconset`; after editing them, re-render to 1024×1024 PNGs **without alpha** (App Store rejects icons with transparency). Open `Branding/preview.html` to see every variant on dark and light.

### Color tokens

| Token | Hex | Use |
|---|---|---|
| `bg/base` | `#0B0B0F` | screen background |
| `bg/surface` | `#1C1C22` | cards, toolbar, sheets |
| `bg/surface-raised` | `#2A2A33` | buttons, segmented controls |
| `border/separator` | `#3A3A45` | hairlines |
| `text/primary` | `#FFFFFF` | |
| `text/secondary` | `#9A9AA6` | |
| `accent/primary` | `#FFCC00` | primary actions, selection, trim handles |
| `accent/on-primary` | `#111111` | text/icons on accent |
| `track/audio` | `#30D5C8` | audio track |
| `track/text` | `#FF9F0A` | text and sticker tracks |
| `status/danger` | `#FF453A` | destructive |

Radii: buttons 16, cards 14–22, sheets 24–28, timeline clips 8.
