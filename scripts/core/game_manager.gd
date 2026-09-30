class_name GameManager
extends Node

# Scene-wide state: health (slowly regenerating), score + combo, kills,
# banners, game over and restart.
# The HUD (hud.gd) draws from this state.

static var instance: GameManager

@export var player: PlayerShipController
@export var spawner: EnemySpawner

@export_group("Rules")
@export var max_health := 100
## Health regained per second, very slowly...
@export var regen_per_second := 0.5
## ...starting this many seconds after the last hit.
@export var regen_delay := 5.0
## Kills within this many seconds of each other build the combo.
@export var combo_window := 2.0
@export var max_combo := 5


var score := 0
var kills := 0
var combo := 1
var health := 0
# Trails behind health after a hit, so the lost chunk visibly drains away.
var health_trail := 0.0
var is_game_over := false
## Classic mode: every enemy destroyed (the game over screen shows a win).
var mission_complete := false
## Seconds since the game ended; the game over screen waits for the explosion.
var game_over_time := 0.0
## Shown on the game over screen.
var death_reason := ""
## How long the player's explosion plays before the game over screen appears.
@export var game_over_delay := 2.5

# True once the explosion has played and the game over screen is up.
var game_over_screen: bool:
	get:
		return is_game_over and game_over_time >= game_over_delay

var combo_timer := 0.0
var score_punch := 0.0
var hit_flash := 0.0
var banner_text := ""
var banner_timer := 0.0
var banner_duration := 0.0
var play_time := 0.0
var trail_hold := 0.0
var _regen_wait := 0.0
var _regen_accum := 0.0


func _enter_tree() -> void:
	instance = self
	health = max_health
	health_trail = max_health


func _exit_tree() -> void:
	if instance == self:
		instance = null


func register_kill(points: int) -> void:
	combo = mini(combo + 1, max_combo) if combo_timer > 0.0 else 1
	combo_timer = combo_window
	score += points * combo
	kills += 1
	score_punch = 1.0


func player_hit(damage: int) -> void:
	if is_game_over:
		return

	health = maxi(0, health - damage)
	trail_hold = 0.4
	_regen_wait = regen_delay
	_regen_accum = 0.0
	hit_flash = clampf(0.4 + damage / 25.0, 0.0, 1.0)
	combo = 1
	combo_timer = 0.0

	if health == 0:
		is_game_over = true
		game_over_time = 0.0
		if death_reason.is_empty():
			death_reason = "YOUR SHIP WAS DESTROYED" if player == null or not player.on_foot else "YOU WERE KILLED"
		var cam := get_viewport().get_camera_3d() as CameraFollow
		if cam != null:
			cam.shake(1.0)
		if player != null:
			player.health.on_game_over()


func show_banner(text: String, duration: float) -> void:
	banner_text = text
	banner_duration = duration
	banner_timer = duration


func restart_game() -> void:
	score = 0
	kills = 0
	combo = 1
	combo_timer = 0.0
	health = max_health
	health_trail = max_health
	is_game_over = false
	mission_complete = false
	game_over_time = 0.0
	death_reason = ""
	hit_flash = 0.0
	trail_hold = 0.0
	_regen_wait = 0.0
	_regen_accum = 0.0
	play_time = 0.0

	for b in get_tree().get_nodes_in_group("bullets"):
		b.queue_free()
	if spawner != null:
		spawner.reset()
	get_tree().call_group("ally_spawner", "reset")
	if player != null:
		player.health.reset_player()

	var cam := get_viewport().get_camera_3d() as CameraFollow
	if cam != null:
		cam.snap_to_target()


func _process(delta: float) -> void:
	play_time += delta
	# Classic mode is won by destroying every enemy.
	if GameMode.is_classic and not is_game_over and spawner != null and play_time > 1.0 \
			and spawner.enemies_left == 0:
		mission_complete = true
		is_game_over = true
		game_over_time = game_over_delay - 1.5   # a moment to take it in first
		death_reason = ""
	if is_game_over:
		game_over_time += delta

	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 1
	score_punch = move_toward(score_punch, 0.0, delta * 4.0)
	hit_flash = move_toward(hit_flash, 0.0, delta * 2.5)
	if banner_timer > 0.0:
		banner_timer -= delta
	_regenerate(delta)
	if trail_hold > 0.0:
		trail_hold -= delta
	else:
		health_trail = move_toward(health_trail, health, delta * 40.0)


func _regenerate(delta: float) -> void:
	if is_game_over or health >= max_health:
		return
	if _regen_wait > 0.0:
		_regen_wait -= delta
		return
	_regen_accum += regen_per_second * delta
	while _regen_accum >= 1.0 and health < max_health:
		_regen_accum -= 1.0
		health += 1
	health_trail = maxf(health_trail, health)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if game_over_screen and key != null and key.pressed and not key.echo and key.physical_keycode == KEY_R:
		restart_game()
