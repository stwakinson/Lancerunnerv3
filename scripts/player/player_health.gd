class_name PlayerHealth
extends Node

# Takes hits from enemy bullets and enemy rams, takes health via GameManager,
# then blinks the ship while briefly invulnerable.

@export var invulnerable_time := 0.5
## Health lost ramming an enemy (an enemy shot takes 10 of 100).
@export var ram_damage := 20
@export var blink_rate := 10.0
@export var hit_color := Color(0.4, 0.8, 1.0)

var invulnerable_timer := 0.0
var is_invulnerable: bool:
	get:
		return invulnerable_timer > 0.0

@onready var ship: PlayerShipController = get_parent()

var start_transform: Transform3D
var _clock := 0.0


func _ready() -> void:
	start_transform = ship.global_transform
	ship.area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	_clock += delta
	if invulnerable_timer <= 0.0:
		return
	invulnerable_timer -= delta
	_set_hull_visible(invulnerable_timer <= 0.0 or fposmod(_clock * blink_rate, 1.0) < 0.6)


func take_hit(damage: int) -> void:
	var gm := GameManager.instance
	if is_invulnerable or (gm != null and gm.is_game_over):
		return

	# On foot the burst would fill the first-person view; the shake and red flash are enough.
	if not ship.on_foot:
		Explosion.spawn(ship.global_position, hit_color, 0.7)
	var cam := get_viewport().get_camera_3d() as CameraFollow
	if cam != null:
		cam.shake(0.6)

	if gm != null:
		gm.player_hit(damage)
	if gm == null or not gm.is_game_over:
		invulnerable_timer = invulnerable_time


# Ramming an enemy destroys it (no points) and costs a life.
func _on_area_entered(other: Area3D) -> void:
	var enemy := other as Enemy
	if enemy == null or is_invulnerable or ship.on_foot:
		return  # the parked ship isn't the player while they're out walking
	if GameManager.instance != null and GameManager.instance.is_game_over:
		return
	enemy.die(false)
	take_hit(ram_damage)


# Out of health (or crashed): the ship, or the pilot on foot, goes up in a
# fireball. The game over screen follows once it's had time to burn.
func on_game_over() -> void:
	if ship.on_foot:
		Blast.spawn(ship.pilot.global_position, 0.25)
	else:
		Blast.spawn(ship.global_position, 2.0)
	invulnerable_timer = 0.0
	ship.visual.visible = false
	ship.enabled = false


# Hit the ground far too hard: the ship is destroyed outright.
func crash() -> void:
	var gm := GameManager.instance
	if gm == null or gm.is_game_over:
		return
	gm.death_reason = "YOUR SHIP CRASHED"
	gm.player_hit(gm.health)


func reset_player() -> void:
	if ship.on_foot:
		ship.pilot.climb_in()
	ship.pilot.reset_chute()
	ship.wrecked = false
	ship.replacement_wait = 0.0
	ship.restore_hull()
	ship.global_transform = start_transform
	ship.reset_motion()
	ship.visual.visible = true
	_set_hull_visible(true)
	ship.enabled = true
	invulnerable_timer = 2.0


# Blinks only the hull meshes; the engine plumes keep burning.
func _set_hull_visible(visible: bool) -> void:
	var model := ship.visual.get_node_or_null("ShipModel") as Node3D
	if model != null:
		model.visible = visible
