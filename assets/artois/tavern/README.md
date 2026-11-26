# Tavern art plates

Generated for the Artois tavern in Lancerunner. Room, exterior and foreground use a 1672×941 canvas. The room plates contain no people. The actor atlas is independent and uses a regular 4×4 layout with transparent padding.

Keep architectural framing consistent when replacing plates. The counter-front occlusion region and seating anchors in `artois_tavern.gd` match this room composition. The scene deliberately starts unpopulated; the game creates a visit roster only on planet landing.

See `docs/artois-tavern.md` for layer and roster details.

`locals.png` adds eight generated ordinary tavern speakers in a transparent 4×2 atlas. Cells map left-to-right, top-to-bottom to copper factor, miner, farmer, dockworker, smallholder, wool merchant, veteran and shipwright. Generated with the original patrons atlas as the style reference; source retained in the generation workspace. Their dialogue and visit selection live separately in `data/artois_tavern_stories.json`.
