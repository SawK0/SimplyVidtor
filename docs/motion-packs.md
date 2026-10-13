# Motion packs

A motion pack is one JSON file of animations for text and stickers. Users import it from Files in the Animate panel. The app validates it, keeps a copy, and embeds each animation in the projects that use it, so those projects still render if the pack is removed.

`SimplyVidtor/Resources/sample-motion-pack.json` is a complete example.

## Pack

| Key | Type | Notes |
|---|---|---|
| `formatVersion` | int | `1`. Files with a newer version are refused with "needs a newer version". |
| `id` | string | Reverse-DNS, lowercase: `com.studio.neon`. Importing the same id again replaces the pack. |
| `name` | string | 1 to 40 characters. |
| `version` | string | Free form, e.g. `"1.2"`. |
| `author` | string | |
| `thumbnail` | string | Optional. Base64 PNG or JPEG, at most 500 KB. |
| `productID` | string | Optional. The App Store product that unlocks the pack; omit for a free pack. |
| `animations` | array | 1 to 100 animations. |

Files are at most 2 MB.

## Animation

| Key | Type | Notes |
|---|---|---|
| `id` | string | Starts with the pack id: `com.studio.neon.flicker`. Unique in the pack. |
| `name` | string | 1 to 20 characters. |
| `roles` | array | Any of `"in"`, `"out"`, `"loop"`. |
| `keyframes` | array | 2 to 64 keyframes. |
| `isDirectional` | bool | Optional. Offsets and wipes turn to the direction the user picks. Author them travelling up. |
| `hasStrength` | bool | Optional, default `true`. Strength scales offsets, rotation and scale. Turn off for loops that must line up (a full spin). |
| `characterSpread` | number | Optional, 0...1. Above 0, each character plays the keyframes in turn and their starts spread over this fraction of the duration. `1` is a typewriter. |
| `defaultDuration` | number | Optional, 0.1...3 seconds. |

Rules:

- An `in` animation ends at rest (the last keyframe has every value at its default). It plays backwards as `out`, still travelling the chosen direction.
- A `loop` ends where it starts; rotation may differ by whole turns.

## Keyframe

Missing values rest at their defaults.

| Key | Default | Range | Meaning |
|---|---|---|---|
| `time` | required | 0...1 | Progress through the animation. The first keyframe is at 0 and the last at 1. |
| `opacity` | 1 | 0...1 | |
| `offsetX`, `offsetY` | 0 | -2...2 | Fractions of the frame's shorter side; x right, y down. |
| `scale` | 1 | 0...10 | |
| `rotation` | 0 | ±4 turns | Radians, clockwise. |
| `reveal` | 1 | 0...1 | Visible fraction, for wipes. |
| `easing` | `"linear"` | | Curve to the next keyframe: `"linear"`, `"easeIn"`, `"easeOut"`, `"easeInOut"`, `"snappy"`, `"back"`, or `[x1, y1, x2, y2]` like CSS `cubic-bezier` (x values 0...1). |
