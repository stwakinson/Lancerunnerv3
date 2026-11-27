# Combat tuning and first effects pass

The starter Warden's turn multiplier increases from 1.6 to 2.0 (+25%). Other hulls retain their existing handling. The current Lance energy bolt (the plasma request) increases from 125 to 187.5 m/s (+50%); its shop description matches. Damage, firing cadence, energy costs and the cruise turning reduction are unchanged.

Visuals now distinguish cool ward hits from warm hull sparks. Pavise missiles detonate blue, Fetter missiles produce a cool disruption burst, and Bodkin missiles produce a warm blast. Mission enemies, ambient locals and the player produce destruction flashes, expanding light rings and drifting, spinning block fragments on death. Existing cargo drops, faction penalties and mission progression remain intact. Fragments are cosmetic glowing particles, not collectible salvage.

`artois_combat_effects.gd` owns the short-lived visuals. Each burst uses a low-resolution core and ring plus an instanced MultiMesh of 10 impact sparks or 36 explosion fragments. At most 32 bursts are tracked; older ones are hidden and queued for deletion on overflow. There are no debris physics bodies, collisions, shadow lights or persistent wrecks. Effects expire within 2.8 seconds, including offscreen NPC explosions while docked. Their clock follows the same pause behaviour as combat.

Validation: `tests/artois_effects_smoke.gd` checks the speed changes, ward/hull impacts, missile type, mission/local destruction, bounded spawning, node cleanup and expiry while docked. The rendered variant captures the early flash and later fragments. Existing combat, ordnance, living traffic, character and ship-dealer smoke tests pass. This is a visual effects pass; it adds no audio assets.
