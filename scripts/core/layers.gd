class_name Layers
extends RefCounted

# Physics layer bits shared by ships, bullets and the aim ray.
const PLAYER := 1
const ENEMY := 2
const PLAYER_BULLET := 4
const ENEMY_BULLET := 8
const ALLY := 16
## The ship's solid hull (only the pilot on foot collides with it).
const SHIP_HULL := 32
