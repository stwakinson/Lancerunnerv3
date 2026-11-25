# Planet ship dealer and port clearance

Dock at Agincourt Planet Port, click the parked spacecraft or **4 SHIP DEALER**, or press **4**. The shipyard offers three standard hulls:

| Hull | Retail | Cargo | Hull | Armour | Ward | Flight speed |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Kestrel interceptor | 6,000 | 8 | 85 | 45 | 45 | 45 m/s |
| Warden fighter (starting ship) | 8,000 | 20 | 120 | 80 | 60 | 35 m/s |
| Pilgrim light trader | 18,000 | 90 | 200 | 110 | 75 | 28 m/s |

The current ship trades in for 50% of its retail value. The dealer shows the net payment, or credits returned on a downgrade. All cargo, fitted equipment, utilities and consumables transfer; a smaller hold is refused if the cargo will not fit. The expansion module still adds ten spaces. All three hulls have two weapon hardpoints. Purchases change the ship model, protection, hold, flight speed and turning immediately. Cruise is five times the selected hull's flight speed and afterburner three times. The existing shield utility still upgrades the ward to 180. The Pilgrim uses the authored model; the other two use distinct lightweight blockouts.

Purchases are saved atomically with the existing economy save. Failed saves roll back the credits and ship class. Old saves keep their ship class and inventory. There is one active ship, not a hangar fleet.

Owned ports require **normal/neutral reputation**, currently -19 or better with their controlling faction; wary (-20) and hostile standings are refused. Agincourt Castle is Valois, the northern posts Britannian, the southern ports Valois, Caulers and the ruined guild Hanseatic, and local civilian ports Borderlander. The Freebooter base requires Freebooter clearance. St Paul's independent chapter remains a neutral sanctuary; defeat recovers the player there if their reputation bars entry to the planet. Recovery does not reset reputation. Hyper gates remain offline.

All three current hulls also require normal standing with the planet's Borderlander shipwrights. Future hull entries can set `minimum_reputation` to a higher score and specify `required_faction` independently of the port's docking clearance. Faction-exclusive ships and reputation recovery missions are not added in this change.

Configuration lives in `data/artois_ships.json` and `data/artois_factions.json`. Cargo capacities remain shared with NPCs in `artois_ship_holds.gd`. Dealer UI uses the existing shop modal so Escape, launch restrictions and pause behaviour remain consistent.
