# SimplyVidtor Plan

A simple, dark-themed iOS video editor: pick clips, trim and arrange them on a timeline, add text, music and filters, then export to Photos.

Design source: [Figma: iOS Video Editor](https://www.figma.com/design/sjymzmXSpWxi9qBCKUPAom) (node IDs in [CLAUDE.md](CLAUDE.md#design-source-figma)).

## Goals

- Fast path from "New Project" to an exported video in under a minute.
- One-handed, thumb-friendly editor: preview on top, timeline in the middle, tools at the bottom.
- Everything on device. No accounts, no server.

## Non-goals (v1)

- Multi-track video (picture-in-picture, overlays of video on video).
- Keyframe animation, chroma key, AI features ("Auto Edit" tile is a placeholder).
- Cloud sync, collaboration, templates marketplace.

## Architecture

| Layer | Choice | Notes |
|---|---|---|
| UI | SwiftUI | iOS 26.5+, dark appearance only for v1 |
| State | `@Observable` models | One `EditorSession` per open project |
| Persistence | SwiftData | `Project` row + timeline stored as a Codable value |
| Media import | PhotoKit (`PHPickerViewController` / custom grid) | Copy picked files into the app container so projects survive library changes |
| Playback | `AVPlayer` + `AVMutableComposition` | Rebuild the composition when the timeline changes |
| Filters, transitions, text | Custom `AVVideoCompositing` compositor rendering with Core Image | One pipeline for preview and export (see note below) |
| Text / stickers (editing) | SwiftUI overlay on the preview while a text item is being edited | Keep positions in normalized (0...1) coordinates |
| Thumbnails | `AVAssetImageGenerator` | Cached per clip, generated off the main actor |
| Waveform | `AVAssetReader` sampling | Cached per audio asset |
| Export | `AVAssetExportSession` (async `export(to:as:)`) | Then `PHPhotoLibrary` save |

### Video pipeline note

`AVVideoComposition(asset:applyingCIFiltersWithHandler:)` only filters a single asset: it cannot apply different filters per clip or blend two clips for a cross-fade, and it cannot be combined with `AVVideoCompositionCoreAnimationTool`. So the engine uses one custom compositor:

- `CompositionBuilder` turns a `Timeline` into `AVMutableComposition` (two alternating video tracks so transitions can overlap) plus an `AVMutableVideoComposition` whose instructions carry per-clip filter, crop and transition info.
- `VideoCompositor: AVVideoCompositing` reads those instructions, applies Core Image filters, blends overlapping frames, and draws text/sticker layers (pre-rendered to `CIImage`).
- The same composition feeds `AVPlayerItem` (preview) and `AVAssetExportSession` (export), so what you see is what you export.

### Core model (draft)

```swift
struct Timeline: Codable {
    var clips: [Clip]              // ordered, back to back
    var textItems: [TextItem]
    var audioItems: [AudioItem]
    var settings: ExportSettings   // resolution, fps, HDR
}

struct Clip: Codable, Identifiable {
    let id: UUID
    var mediaFile: String          // filename in app container
    var sourceStart: Double        // seconds into the source
    var sourceDuration: Double
    var speed: Double = 1          // 0.1...10
    var volume: Double = 1
    var filter: FilterPreset?
    var filterIntensity: Double = 0.8
    var crop: CGRect?              // normalized
    var transitionAfter: Transition?
}
```

Timeline durations are derived (`sourceDuration / speed`), never stored, so split, trim and speed stay consistent.

## Milestones

### M0: Foundation

Chunk 1: environment setup
- [x] `.gitignore`, `Makefile` (`make build`, `make test`, `make test-unit`, `make test-ui`)
- [x] `App/` folder with `SimplyVidtorApp` + `RootView`, dark-only (`preferredColorScheme(.dark)` and `UIUserInterfaceStyle = Dark`)
- [x] Photo library usage strings (`INFOPLIST_KEY_NSPhotoLibraryUsageDescription`, `...AddUsageDescription`)
- [x] iPhone locked to portrait (iPad keeps all orientations until open question 3 is decided)
- [x] Template tests replaced with a unit smoke test and a launch UI test; `make test` green

Chunk 2: design system
- [x] Design tokens: colors, type scale, radii, spacing, sizes (`DesignSystem/Theme.swift`); AccentColor asset set to `#FFCC00`
- [x] Shared components: `ToolButton`, `CircleIconButton`, `.primary` / `.secondary` / `.destructive` button styles, `SegmentedPicker`, `.accentSwitch` toggle style, `ValueSlider` (with center origin for bipolar values)
- [x] `ComponentGallery` (preview, or launch with `-componentGallery` in Debug)
- [ ] Verify type sizes, spacing and component dimensions against Figma page `3:2` (blocked: Figma MCP rate limit when this chunk landed; colors and radii already match CLAUDE.md)

Chunk 3: navigation shell
- [ ] Root navigation: Projects → Editor (full-screen cover), sheets for picker and export, all with placeholder screens
- [ ] Remaining folders (`Features/`, `Engine/`, `Model/`) created as their first files land

### M1: Projects + Media Picker (Figma 01, 04)
- [ ] Projects screen: New Project card, quick actions, recent projects grid
- [ ] SwiftData `Project` model, create / rename / delete / duplicate
- [ ] Media picker: recents grid, All / Videos / Photos filter, ordered multi-select, "Add N clips"
- [ ] Import pipeline: copy into container, generate cover thumbnail
- [ ] Photos (stills) become clips with a default 3 s duration

### M2: Editor core (Figma 02)
- [ ] Preview player with play/pause, timecode, fullscreen
- [ ] Timeline: ruler, filmstrip clips, fixed center playhead, scroll to scrub, pinch to zoom
- [ ] Select clip, trim handles, reorder by long-press drag
- [ ] Toolbar actions: Split, Duplicate, Delete
- [ ] Add clip (+) re-opens picker and inserts at playhead
- [ ] Undo / redo (snapshot `Timeline` values)
- [ ] Autosave on change (debounced)

### M3: Clip tools (Figma 05, 06)
- [ ] Speed panel: 0.1×–10× slider on a log scale (so 1× sits mid-track), keep pitch toggle (Curve tab later)
- [ ] Volume panel, mute
- [ ] Filters panel: presets with intensity, apply to all
- [ ] Adjust panel: brightness, contrast, saturation, warmth
- [ ] Crop / rotate, aspect ratio (9:16, 1:1, 16:9)
- [ ] Transitions between clips (cross-fade first)

### M4: Overlays (Figma 07)
- [ ] Text track: add, edit inline with keyboard, font / style / color, drag and pinch on preview
- [ ] Sticker track (emoji / bundled assets)
- [ ] Audio: import music from Files, trim, volume, fade in/out, waveform

### M5: Export (Figma 03, 08, 09)
- [ ] Export sheet: resolution, frame rate, Smart HDR, estimated size
- [ ] Exporting screen with progress and cancel
- [ ] Save to Photos, Done screen with share sheet

### M6: Polish
- [ ] Haptics on snap and selection
- [ ] VoiceOver labels for every tool and timeline item
- [ ] Performance pass: thumbnail cache, composition rebuild cost, memory on long projects
- [ ] iPad layout (target already includes iPad) or drop iPad for v1

## Testing

- **Unit (Swift Testing):** timeline math (split, trim, speed, total duration), composition building, export size estimate.
- **UI (XCTest):** create project → pick clips → split → export happy path, using bundled sample videos.
- Bundle 2–3 short sample clips in the test target so tests do not need the photo library.

## Open questions

1. Custom media grid (matches Figma) or system `PhotosPicker` for v1? Custom needs full library permission.
2. Music source: Files app only, or bundled royalty-free tracks too?
3. Keep iPad in v1, or iPhone only?
4. Remaining Figma screens (Speed, Filters, Text Editing) are designed in this plan but not yet drawn in Figma.
