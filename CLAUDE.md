# CLAUDE.md

SimplyVidtor is a SwiftUI iOS video editor. See [PLAN.md](PLAN.md) for scope, architecture and milestones; keep its checkboxes up to date as work lands.

## Project facts

- Xcode 26.6, iOS deployment target **17.0** (all targets), iPhone + iPad (`TARGETED_DEVICE_FAMILY = 1,2`). No Mac Catalyst, Designed for iPad on Mac, or visionOS.
- Guard iOS 18+ APIs (Liquid Glass, newer AVFoundation) with `if #available` and give iOS 17 a fallback.
- Swift 5 language mode with **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** and approachable concurrency. Everything is main-actor by default. Value types the engine reads are `nonisolated`. A `nonisolated async` function still runs on the caller's actor, so mark heavy async work (thumbnailing, waveform, export) **`@concurrent`**.
- Xcode project uses **synchronized folders** (objectVersion 77). New files dropped into `SimplyVidtor/`, `SimplyVidtorTests/` or `SimplyVidtorUITests/` are picked up automatically; do not hand-edit `project.pbxproj` to add files.
- Info.plist is generated. Add keys as `INFOPLIST_KEY_*` build settings, not a plist file.
- Bundle ID `sawko.SimplyVidtor`.

## Commands

Shortcuts: `make build`, `make run`, `make gallery`, `make test`, `make test-unit`, `make test-ui`. Underlying commands:

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
- `Project` stores `Timeline` as JSON. Once v1 ships, new timeline fields must be optional (or use `decodeIfPresent`): synthesized `Codable` fails on missing keys, which would make old projects unreadable.
- Normalized (0...1) coordinates for overlay positions and crop rects.
- Every screen gets a `#Preview` with sample data.
- Use `Theme` tokens (`Theme.Palette`, `Typography`, `Spacing`, `Radius`, `Size`), never raw hex or magic numbers in views. Reuse `DesignSystem/` components before writing new chrome; add new ones to `ComponentGallery`.
- Debug launch arguments (also in the shared scheme, off by default): `-componentGallery` opens the component gallery; `-inMemoryStore` uses a throwaway SwiftData store and media folder (UI tests always pass it); `-stubMediaPicker` makes the picker's Add return a placeholder clip without a selection; `-seedSampleAudio` adds a 2 s "Sample Tone" to an empty audio library.
- SwiftData models are listed once in `AppSchema.models`; build every container (app, previews, tests) with `AppSchema.container(inMemory:)`.
- Media files live in `MediaStore` (Application Support/Media) and are referenced by file name. Read the store from `@Environment(\.mediaStore)`.
- Present `MediaPickerView` with `.fullScreenCover`, never `.sheet` (the inline photo picker breaks sheet safe areas).
- AVFoundation: keep the `AVAsset` alive while using its tracks (tracks don't retain it; inserting from an orphaned track fails with -11800). Never end a composition with an empty range; it gets dropped, so fill gaps with `blank.mov`. Video composition instructions must tile the whole composition with no gaps: build them from the shared clip boundaries in `CompositionBuilder`.
- Editor edits go through `EditorSession.update { timeline in ... }`, which saves and rebuilds playback. Drag-driven edits use `beginInteractiveEdit` / `updateInteractiveEdit` / `endInteractiveEdit` so they save and rebuild once.
- Tool panels (Speed, Volume, ...) replace the toolbar while open and use the `ToolPanel` chrome. They act on the selected clip; opening one selects the clip under the playhead. Bind controls through `EditorSession.edit`, which applies live during a drag and as a normal edit otherwise.
- The timeline lives in a `UIScrollView` (`TimelineScrollView`). Don't attach SwiftUI long-press gestures to its content (they block scrolling); add UIKit recognizers on the scroll view instead.
- Testing per chunk: `make test-unit` plus only the new/affected UI test on one simulator (`-only-testing:` with `-parallel-testing-enabled NO`). Full `make test` at milestone ends. UI tests are not parallelized in the scheme.
- UI tests: zoom the timeline out (`pinch`) before dragging handles so they're on screen, and wait for `timeline.clip.0` before presenting anything from the editor.
- Previews use `PreviewData.container()` for sample projects.
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

All brand images live in `Assets.xcassets`:

- `AppIcon`: `app-icon.png` (default + dark) and `app-icon-tinted.png` (white glyph on black for tinted mode). 1024×1024, **no alpha** (App Store rejects icons with transparency).
- `LogoGlyph`: split play glyph only, transparent, vector SVG. Use for splash, empty states, About: `Image(.logoGlyph)`.
- `LogoMark`: glyph on the rounded dark tile, vector SVG: `Image(.logoMark)`.

The mark is a rounded play triangle (`388,300 388,724 756,512`, stroke 72, round joins) cut by a slanted gap, right half offset `(14,-18)`, yellow `#FFCC00` on a `#24242C → #0B0B0F` gradient. `LogoMark.svg` is the master; regenerate the icon PNGs from it if the mark changes. There is no wordmark asset: render "Simply" + "Vidtor" (accent) in SF Pro Bold in code.

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
