# Agincourt landing art and depth

The landing preview uses original AI-generated art plates with cinematic pixel-art
styling: cool teal storm light, warm amber market windows and a distant gothic
fortress carrier. The supplied visual references guided the mood and composition;
no game screenshots or supplied illustrations are embedded as assets.

## Independent planes

| Plane | Depth factor | Content |
| --- | ---: | --- |
| Distant artwork | 0.10 | Opaque storm, castle, carrier and distant valley |
| Air traffic | 0.23 | Three looping small hull silhouettes and one searchlight |
| Valley mist | 0.35 | Slow, weather-dependent haze between far and near art |
| Market artwork | 0.65 | Alpha-cut village, wet street and parked ship |
| Street life | 0.65 | Pilot silhouette, two walking figures, brazier, embers and light glints |
| Foreground artwork | 1.05 | Alpha-cut market post, barrels, flowers and mooring props |
| Near weather | screen-space | Two rain speeds and small pavement splashes |

The artwork is genuinely separated onto three PNGs. The distant castle and carrier
share one painted plate; they do not have individual geometry or independent motion.
Mist, rain, people, traffic and the fire are runtime animation passes. This remains
a composed landing hub preview, not a navigable 3D city or an on-foot gameplay mode.

## Controls

- Move the **mouse** for shallow viewpoint movement.
- Hold **A / D** to pan left/right; **R** recentres the camera.
- **C / DRIFT** toggles the slow cinematic camera drift. It does not pause traffic or weather.
- **L / DEPTH** flattens all parallax planes for comparison.
- **F / LANDING RAIN** toggles rain and valley mist.
- **Enter** launches back into the space benchmark.

Camera motion eases toward its target, then layer offsets snap to the 640×360
pixel grid. Motion is clamped to the artwork overscan. Actors and pavement share
the same depth factor, so their feet stay attached when the viewpoint moves.

## Asset provenance and replacement

The three source images in `assets/benchmark/landing/` are **1672×941** each.
`distant_fortress.png` is opaque RGB; `market_pad.png` and `foreground_props.png`
retain real RGBA transparency. They are the unresampled generated source files,
not a claim of native 1920×1080 artwork. Original generated files are preserved
outside the repository; the game uses copies.

`BenchmarkLandingArtLayer` draws each source into an overscanned rectangle. The
market is framed upward to leave a usable street above the UI. A solid ground
extension beneath the art prevents a lower edge gap. The foreground has separate
framing. These transforms do not alter the source pixels.

To replace a plate, preserve its transparent silhouette and visual alignment or
adjust its `frame` rectangle in `benchmark_landing.gd`. The two near plates must
remain transparent; flattening them against black will destroy depth separation.
Lighting shimmer is a subtle shader on the market art; it does not supply normal
maps or physically relight the painted buildings. The imagery remains an art-direction prototype for later authored refinement.

## Review

Open the main menu's **ARTOIS / VISUAL BENCHMARK** and press Enter.
The regular benchmark smoke test checks alpha, depth on/off, drift control,
keyboard pan, overscan limits, shared actor/pavement depth, weather and launch.
For a deterministic motion review:

```sh
godot --path . --script res://tests/landing_tour.gd
```

The tour uses the same live camera/animation API. To record it, use Godot Movie
Maker with an absolute temporary output path:

```sh
godot --path . --fixed-fps 30 --write-movie /absolute/path/tour.avi \\
  --script res://tests/landing_tour.gd
```

[Rendered landing screenshot](benchmark-previews/artois-landing.png) ·
[Recorded parallax preview](benchmark-previews/landing-parallax.mp4)
