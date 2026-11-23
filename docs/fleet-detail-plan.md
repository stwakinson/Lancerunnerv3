# Bookmarked: distance-based fleet detail

Future work, requested for later. This is not implemented by the Pilgrim asset.

Keep persistent ship identity, hull/armour/power, cargo, route, faction and mission
state independent of its current rendering/simulation level. Candidate bands:

- Within roughly 500 m: full combat, physics/projectile checks, frequent tactics.
- 500–1,000 m: less frequent decisions and simpler steering/collision/effects.
- Beyond roughly 1,000 m: cheap fleet combat/routines and low-detail meshes or
  multi-angle billboards where apparent ship size permits.
- Far away/off-screen: scheduled travel, trade and encounter outcomes; no rendering.

Treat visual and simulation detail separately. Use hysteresis around thresholds,
retain higher detail for selected/mission-critical targets and incoming threats,
and keep large cathedral ships as meshes farther away than small fighters.

Benchmark 50/100/250/500 representative visible ships on target hardware before
fixing distances or promising counts. Track CPU versus GPU costs, spatial-query
scaling, projectile pooling, mesh/material batches, transparency, lights and shadows.
The system currently has 30 persistent locals plus five optional mission enemies;
a dense fleet battle is a different workload. The Pilgrim's 812/341-triangle
meshes are assets for that future work, not the fleet-detail system itself.
