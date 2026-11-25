# Physical player dodge

Double-tap a direction as before. The player dodge now has three thrust phases instead of instantly setting lateral speed and exponentially fading it:

1. **Kick:** begin with 20% thrust velocity for immediate response, then accelerate to the hull's dodge speed. Warm directional jets fire opposite the shove.
2. **Slide:** sustain the lateral momentum briefly.
3. **Recovery:** counter-thrusters fire from the other side and reduce the lateral velocity smoothly to zero.

| Hull | Peak dodge speed | Kick | Slide | Recovery | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Kestrel | 130 m/s | .07 s | .10 s | .27 s | .44 s |
| Warden | 110 m/s | .10 s | .12 s | .34 s | .56 s |
| Pilgrim | 75 m/s | .16 s | .18 s | .52 s | .86 s |
| Longbow | 120 m/s | .09 s | .12 s | .32 s | .53 s |
| Epervier | 125 m/s | .08 s | .11 s | .30 s | .49 s |

The recovery cooldown lasts the manoeuvre plus .15 seconds, with a minimum .65-second cooldown. The normal Warden dodge covers approximately 38.5 m without normal-flight input. No extra energy cost or invulnerability is introduced. Steering, firing and shields remain available under their existing rules.

Dodge motion is integrated analytically, so distance does not depend on frame rate. Its world-space direction is fixed at activation: turning the ship does not rotate its existing lateral momentum. Hull meshes, hardpoints and engine visuals bank into the motion and right themselves as it settles. This is cosmetic attitude separate from the ship's steering/aim frame, so it does not roll the camera or deflect weapon aim.

Brake, Fetter disruption, highway capture, launch and hull/loadout changes clear the manoeuvre, particles and bank together. Highway escape retains its existing transition behaviour. The new player controller does not change original ShipWars controls or the separate NPC tactical AI.

Tuning lives in each hull's `dodge` entry in `data/artois_ships.json`. Implementation is isolated in `scripts/artois/artois_dodge.gd`, called by Artois flight and hull configuration. Regression coverage checks the three phases, banking, jets, frame-rate independence, ship weight, retained world-space momentum, firing/damage during a dodge and transition resets. Existing projectile combat tests still confirm a real dodge avoids a shot that hits a stationary player.
