# The Hollow Crown — Artois tavern

After landing at Agincourt Planet Port, press **3** or choose **TAVERN / CONTACTS**. Click a marked patron to open that faction's contract conversation. Press **5** or choose **RETURN TO MARKET** to visit the market and shipyard again. Enter still launches; Escape retains the normal pause menu. Carrier contacts remain in their carrier hangars.

The tavern is the independent `scenes/artois_tavern.tscn`, designed for the existing 640×360 landing viewport. Its script extends Node2D directly and owns its own layer/camera setup rather than inheriting the planet landing script. Entry validates and prepares the room before hiding the market, replaces an incomplete cached room, and explicitly enables viewport updates. Its base scene is empty: no bartender or patrons are baked into the room artwork, and no actors are spawned by `_ready()`. `begin_visit()` adds people separately on a successful planet landing.

Six registered depth layers form the scene:

1. Cool rainy spaceport exterior.
2. Empty room architecture with a real transparent window opening, warm hearth flicker and glass-plane rain.
3. Separate bar staff sprite.
4. Aligned, people-free counter-front crop that occludes the bartender's lower body.
5. Separate seated guests and their contact markers.
6. Close tables, tankard and foliage on transparent alpha.

The exterior moves slowly and the nearest props move faster. Architecture, counter and seated people share a depth factor, so people remain on their furniture. Mouse look, A/D pan, cinematic drift, depth and weather toggles use the existing landing controls. Conversation freezes camera movement while ambient lighting continues. Patron click rectangles follow the actual layer offsets and the landing viewport's scale/crop transform.

Each landing rolls 2–4 faction contacts from the planet's existing pool, random seat assignments, three ordinary rumour patrons from an eight-person pool, and a separate staff variant. The roster is capped at eight actors: four faction contacts, three local speakers and one innkeeper. It stays unchanged while entering/leaving the bar, shopping or opening menus. Only a new successful planet landing rerolls it. If an active or completed contract requires a planet contact, that issuer is always included on return, preventing an unavailable turn-in. The conversation selector lists only contacts currently present.

Original generated source plates live in `assets/artois/tavern/`:

- `empty_room.png`: opaque people-free reference room.
- `room_shell.png`: architectural plate with transparent window panes.
- `exterior.png`: independent rainy spaceport view.
- `foreground.png`: transparent close props.
- `locals.png`: new 4×2 transparent atlas of eight working people, assigned to named rumour profiles.
- `patrons.png`: 4×4 transparent actor atlas; columns are faction clothing and rows are seated/staff poses.

`artois_tavern.gd` owns the layers and visit roster; `artois_tavern_patron.gd` draws independent atlas actors. No source images are modified at runtime. Furniture occlusion uses an aligned AtlasTexture region from the empty room shell. The parent Artois scene owns room navigation and clickable overlays; faction contracts keep their existing logic and reward saves.

The empty room can be inspected without actors, and `clear_people()` removes all staff/patrons while preserving its art. Actors, room assets and visit state remain separate. Click blue speech markers for local talk, the notice board or innkeeper for news, or press 6. See `artois-tavern-stories.md` for the rumour and gazette system.

Validation covers empty base, genuine window alpha, bounded varied rosters, required-contact inclusion, independent parallax, furniture registration, moving hit areas, actual patron clicks, stable rosters during conversations/re-entry/shopping, launch from the tavern, fresh landing rerolls, contract acceptance/turn-in and depth toggles. Existing randomized contracts, projectile combat, markets, ship dealer and background traffic checks also pass.

Entry regression tests exercise the actual key 3 and service button, assert the dedicated scene and heading, check rendered artwork rather than a flat grey viewport, and recover an incomplete cached room. These checks also pass after a clean source import.

Patron click areas remain visible continuously while available, so ordinary mouse presses held across several frames are not cancelled by the per-frame hotspot update. Both the figure and its gold contact marker open the matching faction conversation. The held-click regression exercises all four faction patrons and marker clicks on Godot 4.7, rather than synthesizing press/release in a single frame.
