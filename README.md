<p align="center">
  <img src="SimplyVidtor/Assets.xcassets/LogoMark.imageset/LogoMark.svg" width="96" alt="SimplyVidtor logo">
</p>

# SimplyVidtor

A simple, dark-themed video editor for iPhone and iPad, built with SwiftUI and AVFoundation. Pick clips, arrange them on a timeline, add text, music, filters and animation, then export to Photos. Everything runs on device: no accounts, no server.

## Features

- **Projects:** create, rename, duplicate and delete; autosave with 50-step undo and redo.
- **Media:** import videos and photos from the library, and audio from Files or from a video's soundtrack. Imported audio is kept in a library you can reuse across projects.
- **Timeline:** scroll to scrub, pinch to zoom, trim, split, duplicate, reorder, and transitions (cross-fade, dip to black).
- **Clip tools:** speed (0.1×–10×, keep pitch), volume, filters, adjustments, crop and rotate, and transform (position, scale, rotation, opacity).
- **Layers:** any number of video, text and audio tracks; picture in picture; clips sit anywhere on the main track and snap to neighbouring edges; higher tracks draw on top.
- **Text and stickers:** fonts, colors and backgrounds; In / Out / Loop animations, including per-character effects; animation packs imported as JSON ([format](docs/motion-packs.md)).
- **Keyframes:** animate clip, text and sticker transforms with eased keyframes (for example, a zoom from 100% to 150%).
- **Export:** choose resolution, frame rate and HEVC, with a size estimate. HDR clips export as 10-bit HLG. Save to Photos or share.

## Requirements

- Xcode 26.6 or later
- iOS 17.0 or later (iPhone and iPad)

## Getting started

```bash
git clone git@github.com:SawK0/SimplyVidtor.git
cd SimplyVidtor
open SimplyVidtor.xcodeproj
```

Run the `SimplyVidtor` scheme, or use the Makefile:

| Command | What it does |
|---|---|
| `make build` | Build for the iPhone 17 Pro simulator |
| `make run` | Build, install and launch in the simulator (extra launch arguments: `make run ARGS="-foo"`) |
| `make gallery` | Launch the design-system component gallery |
| `make test` | Unit and UI tests |
| `make test-unit` | Unit tests only |
| `make test-ui` | UI tests only |

### Debug launch arguments

All of these are off by default and listed in the shared scheme:

| Argument | Effect |
|---|---|
| `-componentGallery` | Opens the component gallery |
| `-inMemoryStore` | Uses a throwaway data store and media folder (UI tests always pass it) |
| `-stubMediaPicker` | The picker's Add button returns a placeholder clip |
| `-seedSampleAudio` | Adds sample tones to an empty audio library |
| `-seedMotionPack` | Imports the bundled sample animation pack |

## Project layout

```
SimplyVidtor/
  App/            app entry and navigation
  DesignSystem/   theme tokens and shared components
  Features/       Projects, MediaPicker, Editor (timeline and tool panels), Export
  Model/          Project, Timeline, Clip, TextItem, AudioItem, tracks, motion, keyframes
  Engine/         composition builder, video compositor, thumbnails, waveforms, exporter
SimplyVidtorTests/    unit tests (Swift Testing)
SimplyVidtorUITests/  UI tests (XCTest)
docs/                 file formats
```

Playback and export share one pipeline: `CompositionBuilder` turns the timeline into an `AVComposition`, and a custom `AVVideoCompositing` compositor draws every frame with Core Image. What you see in the preview is what you export.

## Documentation

- [PLAN.md](PLAN.md): architecture, milestones and progress
- [CLAUDE.md](CLAUDE.md): conventions and engineering notes
- [docs/motion-packs.md](docs/motion-packs.md): animation pack format

## Status

Milestones M0–M9 are complete. M10 (polish: accessibility, performance, iPad layout) is in progress.
