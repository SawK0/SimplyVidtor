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
| UI | SwiftUI | iOS 17+, dark appearance only for v1; iOS 26 features behind `#available` |
| State | `@Observable` models | One `EditorSession` per open project |
| Persistence | SwiftData | `Project` row + timeline stored as a Codable value |
| Media import | One sheet, two tabs: inline `PhotosPicker` for videos/photos; custom Audio tab | Copy picked files into the app container so projects survive library changes |
| Audio import | `.fileImporter` for Files; audio track extracted from a picked video | Imported audio is kept in an app-wide library and reusable across projects |
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

### Core model

Lives in `Model/`: `Timeline`, `Clip`, `AudioItem` (value types, `nonisolated` so the engine can read them off the main actor) and the SwiftData `Project`, which stores the timeline as JSON `Data`. Timeline durations are derived (`sourceDuration / speed`), never stored, so split, trim and speed stay consistent. Text items and export settings join the timeline in M4 / M5.

## Milestones

### M0: Foundation

Chunk 1: environment setup
- [x] `.gitignore`, `Makefile` (`make build`, `make test`, `make test-unit`, `make test-ui`)
- [x] `App/` folder with `SimplyVidtorApp` + `RootView`, dark-only (`preferredColorScheme(.dark)` and `UIUserInterfaceStyle = Dark`)
- [x] Photo library add usage string for saving exports (read access not needed: `PhotosPicker` runs out of process)
- [x] iPhone locked to portrait; iPad supports all orientations
- [x] Template tests replaced with a unit smoke test and a launch UI test; `make test` green

Chunk 2: design system
- [x] Design tokens: colors, type scale, radii, spacing, sizes (`DesignSystem/Theme.swift`); AccentColor asset set to `#FFCC00`
- [x] Shared components: `ToolButton`, `CircleIconButton`, `.primary` / `.secondary` / `.destructive` button styles, `SegmentedPicker`, `.accentSwitch` toggle style, `ValueSlider` (with center origin for bipolar values)
- [x] `ComponentGallery` (preview, or launch with `-componentGallery` in Debug)
- [ ] Verify type sizes, spacing and component dimensions against Figma page `3:2` (blocked: Figma MCP rate limit when this chunk landed; colors and radii already match CLAUDE.md)

Chunk 3: navigation shell
- [x] Root navigation via `AppRouter`: Projects → Media Picker sheet → Editor (full-screen cover); editor owns its own sheets (picker on Media or Audio tab, Export)
- [x] Placeholder screens with `#Preview`: `ProjectsView`, `EditorView`, `MediaPickerSheet`, `ExportSheet`; `ProjectSummary` sample data until SwiftData lands
- [x] `.primaryCompact` button style for nav bars
- [x] Tests: `AppRouterTests` (unit), new-project / cancel / audio-tab navigation (UI)
- [ ] `Engine/` and `Model/` folders created as their first files land (M1/M2)
- [x] Shared `SimplyVidtor` scheme in `xcshareddata` (Debug for Run/Test, Release for Profile/Archive; `-componentGallery` launch arg, off by default)

### M1: Projects + Media Picker (Figma 01, 04)
- [ ] Projects screen visuals from Figma: quick actions, card sizing, cover thumbnails
- [x] `Timeline` / `Clip` / `AudioItem` value types with split, trim, speed, insert, duplicate, remove, move (`TimelineTests`)
- [x] SwiftData `Project` model: timeline as JSON, throwing load so a bad decode is never autosaved, duplicate (`ProjectTests`)
- [x] Projects screen on real data (`@Query`, newest first, empty state); create via picker, rename / duplicate / delete from the context menu (`ProjectLibrary`, `ProjectLibraryTests`, UI test)
- [x] Media picker with two tabs (`SegmentedPicker`): **Videos & Photos** and **Audio**. Full-screen cover, not a sheet: inside a sheet the inline picker strips the safe area
- [x] Videos & Photos tab: inline `PhotosPicker` (`.photosPickerStyle(.inline)`, `selectionBehavior: .continuousAndOrdered` so taps reach the app), All / Videos / Photos filter, own header and "Add N clips" button
- [x] Audio tab (`AudioLibraryView`): app-wide library (`AudioAsset`, `AudioLibrary`) with tap-to-preview (`AudioPreviewPlayer`), single select, swipe to delete, "From Files" (`.fileImporter`, multi-select), "From Video" (keeps the soundtrack as M4A)
- [x] Picked audio goes on the audio track at 0:00; clips go on the video track (editor + appends both)
- [x] Import pipeline (`MediaImporter`, `MediaStore`): copy into the app's media folder in selection order, partial-failure alert, cancel on close
- [x] Cover thumbnail from the first clip (`Thumbnailer`), shown on project cards
- [x] Unused media removed on delete and at launch; skipped if any timeline fails to decode
- [x] Photos (stills) become clips with a default 3 s duration

### M2: Editor core (Figma 02)

Chunk 1: playback
- [x] `CompositionBuilder`: timeline → `AVComposition` + audio mix (speed via `scaleTimeRange`, clip volume, audio items with fades). Photos and missing files are filled with a stretched bundled `blank.mov`, because AVFoundation drops trailing empty ranges
- [x] `EditorSession`: owns the timeline and `AVPlayer`; `update` saves to the project and rebuilds
- [x] Preview (`PlayerView`, no system controls), play/pause button and tap-to-toggle, `mm:ss.t` timecode
- [ ] Fullscreen preview

Chunk 2: timeline view
- [x] Timeline (`EditorTimelineView`): ruler with zoom-aware ticks, filmstrip clips (`ThumbnailCache`), audio row, fixed center playhead
- [x] Scroll to scrub with momentum (`TimelineScrollView`, a `UIScrollView` wrapper since offset-based `ScrollView` APIs need iOS 18); chase-seeking keeps one seek in flight
- [x] Pinch to zoom (15–400 pt/s, `TimelineMetrics`); VoiceOver swipe up/down scrubs by 1 s
- [x] Photos render in the preview: `VideoCompositor` (custom `AVVideoCompositing`, Core Image) draws per-clip instructions (video with its orientation, photo, or black); render size from the first video, else 1080×1920

Chunk 3: clip editing
- [x] Tap to select a clip (accent frame), tap empty track to deselect; selection haptic
- [x] Trim handles on the selected clip; trimming the start keeps the clip's right edge under the finger
- [x] Long-press drag to reorder, other clips reflow live (UIKit long press on the scroll view: a SwiftUI long press in hosted content blocks scrolling)
- [x] Interactive edits (`beginInteractiveEdit` / `updateInteractiveEdit` / `endInteractiveEdit`): live while dragging, one save and rebuild at the end
- [x] VoiceOver: each clip is an element with Move Left / Move Right actions; the playhead is adjustable

Chunk 4: toolbar actions
- [x] Toolbar actions: Split (clip under the playhead, selects the right part), Duplicate and Delete (selected clip); buttons disable when they can't act
- [x] Add clip (+) inserts at the playhead: before the clip under it in its first half, after it in the second; picked audio starts at the playhead

Chunk 5: history
- [x] Undo / redo (snapshot `Timeline` values, 50 steps; a whole trim or reorder drag is one step; undo is saved)
- [x] Autosave: every committed edit writes the project; SwiftData context saved when the editor closes or the app leaves the foreground

### M3: Clip tools (Figma 05, 06)
- [x] Speed panel: 0.1×–10× slider on a log scale (so 1× sits mid-track), keep pitch toggle (Curve tab later). Pitch is per track, so clips that don't keep pitch go on a second varispeed audio track
- [x] Volume panel (0–100%, AVAudioMix can't amplify), mute that keeps the level
- [x] Filters panel: presets with intensity, apply to all (`FilterRenderer`, drawn by `VideoCompositor`)
- [x] Adjust panel: brightness, contrast, saturation, warmth (applied before the filter)
- [x] Crop / rotate, aspect ratio (9:16, 1:1, 16:9): per-clip quarter turns and normalized crop, project canvas on the timeline, full-screen crop editor over a still frame
- [ ] Transitions between clips (cross-fade first)

### M4: Overlays (Figma 07)
- [ ] Text track: add, edit inline with keyboard, font / style / color, drag and pinch on preview
- [ ] Sticker track (emoji / bundled assets)
- [ ] Audio: editor Audio tool opens the picker sheet on the Audio tab; trim, volume, fade in/out, waveform

### M5: Export (Figma 03, 08, 09)
- [ ] Export sheet: resolution, frame rate, Smart HDR, estimated size
- [ ] Exporting screen with progress and cancel
- [ ] Save to Photos, Done screen with share sheet

### M6: Polish
- [ ] Haptics on snap and selection
- [ ] VoiceOver labels for every tool and timeline item
- [ ] Performance pass: thumbnail cache, composition rebuild cost, memory on long projects
- [ ] iPad pass: regular-width editor layout, Stage Manager / Split View window sizes, pointer and keyboard shortcuts (space = play/pause, ⌘Z / ⇧⌘Z)

## Testing

- **Unit (Swift Testing):** timeline math (split, trim, speed, total duration), composition building, export size estimate.
- **UI (XCTest):** create project → pick clips → split → export happy path, using bundled sample videos.
- Sample media lives in `SimplyVidtorTests/Resources` (`sample-2s.mov`); `TestMedia` generates images.
- `PhotoImportUITests` drives the real photo picker and skips unless the simulator library has the sample video (`xcrun simctl addmedia booted SimplyVidtorTests/Resources/sample-2s.mov <photo>`).

## Open questions

1. ~~Custom media grid or system `PhotosPicker`?~~ **Decided: inline `PhotosPicker`** inside our own sheet (no permission prompt, iPad and iCloud handled by the system). Audio needs preview listening, which no system picker offers, so the Audio tab is custom.
2. ~~Music source?~~ **Decided: v1 = Files import + extract audio from a video.** Bundled royalty-free tracks later, once licensed tracks are sourced. Music library (`MPMediaPickerController`) skipped: Apple Music tracks are DRM-protected and need another permission.
3. ~~Keep iPad in v1, or iPhone only?~~ **Decided: iPad is in v1.** Layouts adapt by size class; iPad gets all orientations.
4. Remaining Figma screens (Speed, Filters, Text Editing) are designed in this plan but not yet drawn in Figma.
