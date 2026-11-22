# Ship Wars (Godot port)

Godot 4.7 port of the Unity "ShipGame" space shooter. Open the folder in Godot and press F5.

## Artois system

Choose **ARTOIS SYSTEM / EXPLORE** to fly the new map blockout. **M** opens the
system chart; select a destination and choose **NAVIGATE**. Approach **Agincourt
Planet Port** within **90 m**, slow below **20 m/s**, then press **J** to land.
Enter launches back from the planet market. See [the Artois guide](docs/artois-system.md).

Artois also includes double-tap dodges, fitted weapons, regenerating shields and
Captain Fluellen's five-enemy test contract on the planet.
[Knightly combat](docs/knightly-combat.md) adds power, armour, a RMB-held, mouse-directed
shield, cruise spooling, Tab afterburner and a bottom-right scanner. See
[combat and mission controls](docs/artois-combat.md).
[Mouse flight](docs/mouse-flight.md): LMB guns, RMB shield, Enter selection cursor and Esc pause menu.

[Golden filament highways](docs/artois-highways.md) provide 10× in-system travel
through paired rings, with directional boost breakouts. North, east and south
hyper gates are present but offline with null destinations; the demo stays in Artois.
[Station interiors and local markets](docs/station-markets.md) let you dock at
14 ports, use both shops, and make modest regional commodity runs.
[Embry's column canyon](docs/embry-art.md) combines towering rectangular rocks
with an orange industrial station nestled between them.
[Thirty named locals](docs/artois-locals.md) now trade, salvage, prowl and flee
inside Artois. Left click or press V to inspect nearby ships and their orders.
[Cursor guns and ordnance](docs/artois-ordnance.md) add locked missile variants,
ammunition and period-inspired hull/shield recovery supplies in the outfitter.

## Lancerunner visual benchmark

The main menu's **ARTOIS / VISUAL BENCHMARK** opens an isolated pixel-style 3D
space scene and layered landing preview. Press **Enter** to dock/launch, **P** to
compare space rendering modes, and **F** to toggle landing weather. See
[the benchmark guide](docs/visual-benchmark.md) for controls and asset replacement.

## Controls
- **Mouse**: steer (the ship turns to follow the view)
- **W / S**: fly forward / back along the view (look down + W dives). The ship has momentum: let go and it drifts to a stop
- **A / D**: strafe
- **Shift**: boost (the meter at the bottom left lasts 10 seconds and slowly refills)
- **Left click / Space**: fire toward the crosshair
- **Z**: toggle zoom to aim (press again to zoom back out; holding right click also works) (in the ship and on foot, where it aims down the gun's sights)
- **Esc**: pause, with the option to return to the main menu (Esc again or Resume to carry on)
- **[ / ]**: mouse sensitivity (saved between sessions)
- **R**: play again after game over
- **Landing**: fly down into the planet to land. The ship slides to a stop. Press W to take off
- **E**: once landed and stopped, climb out and walk around in first person with a gun. W/A/S/D walk, Shift sprints (uses the boost meter), Space jumps, left click fires. Press E next to the ship to get back in
- **The planet is the map**: there's no box around the play area any more, so you can fly all the way around the world (up to 1500 above the ground). Out in space nothing pulls you down. Inside the atmosphere (the lowest 120, marked GRAVITY on the HUD) level flight follows the curve of the planet, and if you slow down or stop you start falling, harder the lower you are

## Missions
START MISSION opens a picker with two missions:
- **Infinite**: destroyed enemies keep coming back and the fight gets tougher over time; it lasts until you're shot down.
- **Classic**: one fixed force of 50 fighters and 50 robots, guarded by 30 missile turrets, and nothing respawns on either side. Destroy every fighter and robot to win (MISSION COMPLETE); the turrets are optional. With 10 or fewer left they all come for you, and with 5 or fewer, red arrows at the screen edge point to them.

The HUD shows the mission and how many enemies (fighters and robots) are left.

## Health
The bar at the top right starts at 100 and turns from green to orange to red as it drops. An enemy shot takes 10 (10 shots and you're out), and ramming an enemy takes 20. Diving steeply or straight down into the ground at full speed (or boosting into it) destroys the ship outright. Land by coming in at a gentle angle, or stop and let gravity lower you. Anything destroyed, you included, goes up in a fireball with burning wreckage; when you die the game over screen follows once the explosion has played. Health slowly comes back (1 point every 2 seconds, starting 5 seconds after your last hit). Fighters go down in one shot. 50 of them are scattered through space all around the planet, cruising on patrol; only the nearest ones hunt you (4 at first, one more every 10 seconds, up to 10 at a time), racing in from wherever they are. Shoot a patrolling one and it fights back. Destroyed enemies are replaced far away, so there are always 50, and newly recruited hunters get tougher every 30 seconds. Red brackets mark the fighters hunting you once they're within radar range (robots and turrets only show on the radar). Your kills are counted under the bar.

30 missile turrets stand on the planet's surface (squares on the radar). Fly your ship within about 300 of one and it swings round and locks on (MISSILE LOCKING, top of the screen); hold still in its sights for 2 seconds and it fires a homing missile: WARNING · MISSILE LOCK flashes, a red diamond blinks on the radar, and a missile cam rides along on the missile's flank. Missiles are faster than you cruise but slower than you boost, so boost away (straight up works best) or out-turn it: after 20 seconds its motor burns out and it drifts to a stop and fizzles. One hit destroys your ship: game over. Turrets are armoured: 10 shots from the ship or 20 from your rifle on foot, and they go up in a chain of explosions. Missiles can't be shot down. Robots' small shots barely scratch the ship (2 damage). Turrets and can't lock onto you on foot or parked.

Only one missile can chase you at a time: while one is after you, no other turret locks on.

You're not alone: 50 allied fighters (identical to your ship) patrol around the planet, and the nearest 10 escort you, flying around you and dogfighting enemy fighters near you. 50 allied troopers (white armour with grey trim and a cyan visor, in your ship's colours; `assets/models/ally_trooper_gen.py`) are scattered over the surface; when you're down on the ground up to 10 join you (dropped in beside you if they're far away), stay close and shoot enemy robots. Enemy fighters and robots attack whichever of you and your allies is nearest. Allies can be killed and aren't replaced; the HUD counts how many are left (ALLIES AIR / GROUND) and they're blue blips on the radar. Your shots pass through them, and their kills aren't counted in your score.

50 walking T-800 robots wander the planet's surface. Land (or skim low over the ground) and up to 10 come for you (4 at first, one more every 10 seconds down there); any too far away to walk warp in nearby. They're slower than the fighters but take two shots, and they raise their cannon arm to shoot you whether you're landed or flying low.

## Layout

See [Code organisation](docs/architecture.md) for component responsibilities and validation commands.
- `scenes/menu.tscn`: the home screen (starts here), with the ship turning above START MISSION
- `scenes/main.tscn`: the game (Unity `Game.unity`)
- `scripts/core/scene_fader.gd`: autoload `SceneFader`, fades through black between scenes
- `scripts/ui/pause_menu.gd`: the Esc bar ("Return to main menu?")
- `scenes/enemy.tscn`, `bullet.tscn`, `enemy_bullet.tscn`: the Unity prefabs
- `scenes/ground_robot.tscn` + `scripts/combat/ground_robot.gd`: the walking robot (walk animated in code). Its model `assets/models/ground_robot.glb` is built by `assets/models/ground_robot_gen.py` (run with Blender: `ROBOT_OUT=$PWD/assets/models/ground_robot.glb Blender -b -P assets/models/ground_robot_gen.py`)
- `scripts/`: one script per Unity MonoBehaviour (`CameraFollow` → `camera_follow.gd`, etc.)
  - `player/ship_model.gd`: what the Unity scene builder did for the ship model: scale it to 2.4 units, center it, add engine thrusters, and tint enemies red
  - `effects/fx_particles.gd`: stands in for Unity's ParticleSystem (explosions and thrusters)
  - `ui/hud.gd`: the Unity IMGUI HUD, crosshair and enemy indicators

Unity uses +Z as forward; Godot uses -Z. Positions from the Unity scene have their Z mirrored.

## Credits
Space textures by Solar System Scope (CC BY 4.0). See `assets/textures/CREDITS.txt`.
