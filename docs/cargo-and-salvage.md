# Ship holds and recoverable cargo

Artois ships now have commodity holds with defined capacities. Equipment and
consumable lockers keep their existing separate rules.

| Hull class | Base cargo units |
| --- | ---: |
| Interceptor / quest patrol | 8 |
| Fighter / player starter / pirates / raiders | 20 |
| Courier | 24 |
| Salvager | 40 |
| Light freighter / Britannian and Valois merchants | 60 |
| Hauler / borderland freight | 80 |
| Pilgrim class definition | 90 |
| Hanseatic cog | 120 |

The fitted cargo expander still adds ten units. The current player ship stays a
20-unit fighter for existing saves. The class table and `set_ship_class` API
support future ship changes; this does not add a ship-purchase menu.

NPC manifests now contain actual commodity IDs and quantities rather than only
cargo labels. Regular merchants load on departure and unload on docking. Planet
exports favour wheat, bottled air and lamp oil; mining/salvage ports favour metals.
Faction preferences guide other loads. Salvagers recover alloy and argent ore
before their return leg. Pirates/raiders carry small supply/plunder manifests;
quest interceptors carry a few units of reactor fuel and alloy. Contents always
fit the hold. NPC trade does not change the player's dealer stocks or fixed prices.

A ship's death rolls surviving units separately for each commodity stack, from
zero up to 75% rounded down, always below the carried amount. Thus some cargo is
always destroyed, and small stacks can be lost entirely. Survivors are split into
floating, slowly drifting/spinning canisters of at most 25 units each. Empty ships
drop nothing; death handling cannot roll the same ship twice. Quest and ambient
NPC deaths use the same mechanism, including NPC-versus-NPC kills.

**Press H within 25 metres** to tractor cargo. Selection is optional: a selected
nearby canister takes priority, otherwise the closest is used. Space + LMB or T
can select one; G stops close enough to collect. Free hold space limits each
pickup, leaving uncollected units in the same canister. Full holds collect nothing.
Leave cruise/spool/filament transit before collecting. The HUD shows current hold
usage, nearby cargo markers, selected quantities and a close-range H hint; cargo
also appears on the scanner.

Recovered cargo is saved before any canister quantity changes. A failed save
restores the hold and leaves the canister intact. Pickup changes neither credits
nor dealer stock, and recovered commodities can be sold normally at markets
that trade them. Player death also removes and saves cargo before spawning its
recoverable fraction; fitted equipment and supply lockers are unchanged.

Uncollected canisters are session-local and expire after ten simulation minutes.
Chart and pause stop their time; they continue drifting/aging while you are docked.
A 128-canister limit bounds scene cost; if full, additional undropped cargo is
counted as destroyed. The canister uses a shared low-poly mesh/material with
analytic drift, not a rigid-body simulation. No ownership/reputation or NPC loot
collection system is added by this pass.

The save remains version 1 with an optional `ship_class`; old saves default to
fighter without resetting inventory. Larger legitimate commodity stacks now pass
validation up to the ship's actual total capacity. Equipment locker caps remain.

Implementation: `artois_ship_holds.gd` defines capacities; `artois_cargo_loot.gd`
owns loss rolls, canisters and pickups; traffic/combat supply actual manifests.

Validation: cargo smoke covers class/legacy saves, real NPC and quest deaths,
random loss, duplicate prevention, delivery/reloading, partial/full/range/transit
pickup, failed-save rollback, H input, player loss, ray selection, drift, pause,
expiry and the object budget. Market, station markets, combat, ordnance, tactics,
traffic, navigation, highways, lanes, mouse and knightly regression suites pass.
Cargo also passed rendered Godot 4.6.3 OpenGL Compatibility. Godot 4.7 Forward+
and large-battle performance remain unverified.

![Floating canisters, pickup hint and hold usage](cargo-previews/artois-cargo-canisters.png)
