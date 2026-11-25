# Randomized faction contracts

Dock at Agincourt Planet Port, Saint George or Saint-Denis. On the planet, press **3** to enter the tavern, then click a marked patron (or press **3** again for present contacts). Carriers retain their **FACTION CONTRACTS** service. The planet's contact pool has four individuals:

- Captain Fluellen — Britannia
- Reeve Alice Fenwick — Borderlanders
- Factor Hinrik Voss — Hanseatic League
- Envoy Ysabeau de Renty — Valois

Saint George has Marshal Eleanor Talbot (Britannia). Saint-Denis has Capitaine Jehan de Dreux (Valois). Clicking a person selects their contact; the conversation selector also switches between contacts currently present. The planet tavern rolls 2–4 contacts per landing and guarantees the pending contract issuer on return; see `artois-tavern.md`.

Each contact maintains three offers:

| Type | Objective | Enemy wing | Required issuer standing | Reputation reward |
| --- | --- | --- | ---: | ---: |
| Freebooter clearance | Destroy the patrol | 3–6 freebooters | -19 | +7 |
| Raider interception | Destroy the wing | 2–4 stronger unidentified raiders | 0 | +9 |
| Captain bounty | Destroy the named captain; escorts optional | Captain plus 2–3 escorts | 10 | +12 |

Locations, wing size, captain names and credit payments vary. Payments combine a template base, wing size and distance. Offers are cached while browsing and remain unchanged when closing/reopening the conversation. Resolving a contact's job refreshes that contact's board. Other contacts keep their existing offers.

One contract can be active at a time. Acceptance requires actually docking at the issuing port, its normal docking clearance, and the issuer reputation listed in the offer. Accepting adds the mission-area waypoint and creates at most six dedicated encounter ships. On launch the mission waypoint remains selected. Approach the area; enemies engage within the existing 420m range. Named bounty captains have gold identification fins and a gold HUD label. Raider affiliation remains publicly unidentified.

Only the current encounter's required ships count. Ambient kills, stale encounter IDs, duplicate death reports and optional escort kills do not advance the objective. A bounty completes when its named captain is destroyed; surviving escorts remain until the encounter is resolved. Patrol and interception jobs require the whole wing.

Completion selects the issuing port as the return waypoint, including carrier contracts. Return, dock and talk to the exact issuing contact to claim payment. Other contacts, other ports and remote claims are refused. Credits and reputation are awarded once and saved atomically together. Only the issuer faction gains reputation. A failed save restores credits/reputation and leaves the contract available for a payment retry. This provides the faction progression required to buy licensed naval fighters.

Abandoning or player defeat clears the dedicated encounter and its waypoint without paying rewards or replacing ambient NPCs. A new job can then be accepted. Contract offers and objective progress last for the current game session; claimed credit/reputation rewards persist in the existing economy save. The conversation footer states that distinction.

Sites are generated roughly 1.8–4.2km from their issuing port, within the chart and away from planet bodies, station approaches and highway filaments. Generation uses world-space distances so contracts remain local at the current enlarged map scale. The ambient population, traffic routines, offline hyper gates and NPC replenishment rules are unchanged.

Configuration lives in `data/artois_contracts.json`. `artois_contract_board.gd` handles contacts, offer caching and site generation. `artois_sortie.gd` manages acceptance, objectives, cleanup and atomic reward claims; the fixed five-enemy fixture remains available internally for deterministic existing weapon tests. The conversation UI is separate in `artois_contract_panel.gd`. Combat's existing bounded patrol factory now accepts contract options and maintains correct public target names and maximum-health bars.

Validation includes stable/randomized offers, safe sites, actual street-contact and offer-selection clicks, rank gates, one-active-contract enforcement, proximity activation, bounty/escort semantics, current-encounter-only kills, return-to-issuer checks, carrier launch/return, saved rewards, save-failure rollback, abandonment and defeat cleanup. Existing projectile combat, ordnance, carriers, faction law, ship dealer, station markets and living traffic suites also pass.
