# Character and faction sheet

Press **I** or **F2**, click **I CHARACTER** in the footer, or choose **Esc → Character / Factions**. Available in flight and while docked, including the tavern and carrier hangars.

The sheet shows ship class and role, credits, cargo usage, hull, armour, ward, energy, weapons, utility, current mission, and all six faction scores with status and unlocked contract tiers. Basic contracts require 0 standing, Veteran 10, Elite 25; naval ships require 25. Normal docking requires -19 or better; factions become hostile at -50.

Flight and traffic pause while reviewing the sheet. I, F2, Escape or Close dismiss it. Opening from the pause menu returns to that menu; opening over a conversation preserves it. Scores are read from the current saved economy state without resetting reputation.

Validation: `tests/artois_character_smoke.gd` covers keyboard, menu and footer entry, pause restoration, current scores and ship information, all six mission contacts at 0/10/25, increasing payouts and difficulty, fallback Basic generation, eligible tavern rosters and preserving conversations. Existing mouse/menu, randomized contracts, tavern, patron clicks, carriers and ship dealer suites also pass.
