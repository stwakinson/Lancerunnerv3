# Code organisation

The game starts at `scenes/menu.tscn` and runs in `scenes/main.tscn`.
Scripts are grouped by responsibility:

- `core/`: mission selection, game state, scoring, health regeneration and scene transitions.
- `player/`: ship and pilot movement, camera, damage handling and ship components.
- `combat/`: enemies, allies, population management and projectiles.
- `world/`: the spherical planet and starfield.
- `effects/`: particles, explosions, trails and parachute visuals.
- `ui/`: menus, HUD and radar.

## Ship components

`PlayerShipController` coordinates input, flight, landing, boarding and ship
replacement. Its exported settings stay on the existing Player scene node so
Inspector settings and NodePaths continue to work.

- `ShipWeapons` owns the ship's firing cooldown and projectile creation. The
  controller updates it only while enabled and occupied, after aiming, so input
  order and the pause in firing cooldown while outside the ship are preserved.
  It receives the ship for each update rather than retaining a reference to it.
- `ShipHull` owns the generated mesh collision body and the skirt that fills the
  gap beneath a parked ship. It remains under ShipVisual so collision follows
  banking. The controller exposes its top height to the pilot and toggles its
  collision when the ship is wrecked, replaced or restarted.
- `PlayerHealth`, `LandingGear` and `ShipBanking` retain their existing roles.

## HUD and radar

`Hud` coordinates overlays, menus, missile camera and contextual prompts.
`HudRadar` owns radar sweep timing, contact history and scope drawing. It draws
on the HUD's canvas during the existing draw callback, preserving overlay order.
Radar size, ranges, sweep period and fade settings remain exported on the HUD.

`ShipWeapons` and `HudRadar` are RefCounted helpers with no independent process
callbacks. Their coordinators control update order and lifetime explicitly.

## Validation

Import the project, then run the scene integration check:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . res://tests/component_smoke.tscn
```

The check loads both missions and exercises ship firing cadence, hull geometry,
parked collision, crosshair aim, inherited projectile speed, radar contacts and
range changes, leaving the ship, wrecking and restarting. For visual changes,
also play the game and inspect radar sweeps, blips and targeting at ship and
on-foot ranges.
