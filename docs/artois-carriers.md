# Naval carriers and patrol response

Saint-Denis is a Valois carrier roughly 389 m from Agincourt Castle. Saint George is a Britannian carrier north of Calais Gate, roughly 585 m from it. Both appear on the chart, support normal docking/launch, and have commodity stores, an outfitter and a ship dealer (button or key 4). The carriers use faction-coloured blockout geometry and existing garrison hangar interiors.

The civilian planet dealer still offers Kestrel, Warden and Pilgrim. Each carrier sells only its own licensed fighter:

| Carrier | Fighter | Retail | Required reputation | Hold | Hull | Armour | Ward | Speed |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| Saint George | Longbow | 24,000 | Britannia 25 | 16 | 155 | 95 | 75 | 38 m/s |
| Saint-Denis | Epervier | 24,000 | Valois 25 | 14 | 145 | 85 | 85 | 40 m/s |

Docking still needs normal standing (-19 or better). Buying military hulls needs trusted standing (25). Planet and carrier contacts now offer randomized combat contracts that award standing with the issuing faction. Completing those contracts earns the 25 naval standing needed for a fighter licence; see `artois-random-contracts.md`. Credit and reputation rewards are saved together and both roll back on a failed save; a completed contract cannot pay twice. Ship trade-in, equipment/cargo transfer and purchased-hull persistence use the same rules as civilian purchases.

A player hit on a naval guard alerts living guards of the same allegiance within 1,500 m. The partner immediately marks the player as its target and uses the existing combat AI and territory leash. Remote patrols and the other navy do not receive the alert. Responding allies do not create extra assault penalties. Existing castle and Calais patrols cover the nearby carriers; no new population spawns or replacement rules are introduced.

The flight camera now uses a symmetric chase offset and looks directly at the ship's origin, keeping it at the centre of the viewport even while the camera follows a turn. The starting Warden's turn multiplier increases from 1.0 to 1.6; its speed, weapons and protection remain unchanged. Original ShipWars camera/ship controls are untouched.
