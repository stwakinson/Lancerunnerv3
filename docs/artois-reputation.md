# Artois reputation and law

F2 in flight shows public standings. Scores run from -100 to 100; -20 is wary and -50 is hostile (red / shoot on sight). Lawful factions begin neutral; Freebooters and unidentified raiders begin hostile.

A player hit, including a shield hit, costs 8 reputation with the victim's faction. Repeated hits on that vessel within 30 simulation seconds belong to the same assault incident. Destruction costs another 30. Misses and NPC crimes do not affect player standing. Destroyed vessels cannot report twice.

Civilian attacks also cost 3 with each other protecting power (Britannia and Valois); destruction costs another 12. Thus four Hanseatic merchant murders make both powers hostile. Attacking naval forces affects their own faction only. Publicly unidentified raiders remain a separate outlaw faction; their hidden sponsor is not exposed through standings. Completing the existing anti-freebooter contract awards +10 Britannian and Valois reputation, saved with payment. Fines and amnesty are not implemented.

There are 38 persistent session locals: the previous 30 plus eight naval guards. Two Britannian guards patrol Calais in the north; pairs of Valois guards patrol Agincourt Castle, the Eastern Gate and Picardie in the south. Freebooters retain their existing base. Guards engage hostile players and nearby outlaws using the same combat limitations as other armed NPCs, and stay within their patrol territory. Hostile civilians flee instead of acquiring weapons. Directly attacked vessels defend themselves immediately even before their whole faction becomes hostile.

Standings are saved with the existing economy save and survive recovery/death. Old saves acquire default standings. Save failures retain standings in memory and retry. World ships and guard deaths remain session state; no replenishment is added. Hyper gates remain offline. Owned ports now require normal standing (-19 or better), with St Paul remaining a neutral sanctuary. See `artois-ship-dealer.md` for clearance, recovery and purchase rules.

Configuration: `data/artois_factions.json` (public allegiances and territorial ownership), `data/artois_population.json` (guards and roster), `scripts/artois/artois_law.gd` (incident rules), and `scripts/benchmark/landing_market_state.gd` (persistence).
