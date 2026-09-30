class_name Parachute
extends Node3D

# A parachute: a round canopy of billowing gores in alternating color and
# white, with a colored hem scalloped between the lines and a vent at the
# top, held above its rider by thin lines that gather into risers at the
# harness. It opens quickly once deployed and sways gently while it flies;
# light shines through the cloth when seen from below. The rider moves it
# each frame with hold() and slows its fall with drag(). When cut (on
# landing, or when the rider leaves it) the lines drop away and the canopy
# drifts down, goes slack and stays lying on the ground where it comes to rest.
#
# The pilot and the ship each carry their own (different sizes and colors),
# each with its own cooldown.

## Seconds after a parachute is cut before its rider can deploy a new one.
const COOLDOWN := 20.0
## Seconds for the canopy to open fully.
const OPEN_TIME := 0.7
## How fast a cut canopy drifts down, in canopy radii per second.
const DROP_SPEED := 0.8
## How far the canopy leans back from the rider per unit of sideways speed.
const TRAIL := 0.06
## Half-angle of the dome at its hem (radians): how deep the canopy is.
const SPAN := 1.1
## Fraction of the dome left open at the top.
const VENT := 0.1

var canopy_radius := 1.0
## Height of the canopy's hem above the rider's harness.
var canopy_height := 2.0

## 0 when just deployed, 1 fully open; drag() works in proportion.
var openness: float:
	get:
		return ease(clampf(_age / OPEN_TIME, 0.0, 1.0), 0.4)

var _age := 0.0
var _phase := randf() * TAU
var _canopy: MeshInstance3D
var _lines: Node3D
var _cut := false
var _settled := false
var _collapse := 0.0
var _up := Vector3.UP


# A new parachute, ready to add to the scene (the loading screen shows one to
# get its materials compiled).
static func make(radius: float, height: float, color: Color, line_width: float) -> Parachute:
	var p := Parachute.new()
	p.name = "Parachute"
	p.canopy_radius = radius
	p.canopy_height = height
	p._build(color, line_width, 16 if radius > 1.0 else 12)
	return p


# Opens a parachute above `anchor`.
static func deploy(anchor: Vector3, up: Vector3, radius: float, height: float, color: Color, line_width: float) -> Parachute:
	var tree := Engine.get_main_loop() as SceneTree
	var p := make(radius, height, color, line_width)
	tree.current_scene.add_child(p)
	p.hold(anchor, up, Vector3.ZERO)
	return p


# Slows a rider's `velocity`: the fall eases to `fall_speed`, sideways speed to
# `glide_speed`, and it can't climb. `rate` is how hard it pulls, per second.
static func drag(p: Parachute, velocity: Vector3, up: Vector3, fall_speed: float, glide_speed: float,
		rate: float, delta: float) -> Vector3:
	var step := rate * p.openness * delta
	var vertical := velocity.dot(up)
	var horizontal := velocity - up * vertical
	vertical = move_toward(vertical, clampf(vertical, -fall_speed, 0.0), step)
	if horizontal.length() > glide_speed:
		horizontal = horizontal.move_toward(horizontal.normalized() * glide_speed, step)
	return horizontal + up * vertical


# Keeps the canopy above the rider's harness at `anchor`, opening as it goes,
# trailing a little behind the way the rider is moving and swaying gently.
func hold(anchor: Vector3, up: Vector3, velocity: Vector3) -> void:
	if _cut:
		return
	_up = up
	var basis := _basis_up(up)
	var sideways := velocity - up * velocity.dot(up)
	var sway := (basis.x * sin(_age * 1.1 + _phase) + basis.z * sin(_age * 0.8 + _phase * 2.0)) * 0.05
	var lean := (up - sideways * TRAIL + sway).normalized()
	var open := openness
	# The canopy breathes a little as it flies.
	var breathe := 1.0 + 0.025 * sin(_age * 2.3 + _phase) * open
	var size := Vector3(lerpf(0.12, 1.0, open) * breathe, lerpf(0.35, 1.0, open) / breathe, lerpf(0.12, 1.0, open) * breathe)
	global_transform = Transform3D(_basis_up(lean) * Basis.from_scale(size), anchor)


# Let go: the lines fall away and the canopy drifts down to lie on the ground.
func cut() -> void:
	if _cut:
		return
	_cut = true
	_lines.visible = false
	var at := _canopy.global_position
	_canopy.top_level = true
	_canopy.global_transform = Transform3D(_basis_up(_up), at)


func _process(delta: float) -> void:
	_age += delta
	if not _cut or _settled:
		return
	var planet := Planet.instance
	if planet == null:
		return
	# Drift down going slack: the dome sags flat and spreads out a little.
	_collapse = minf(1.0, _collapse + delta * 0.8)
	var up := planet.up_at(_canopy.global_position)
	var pos := _canopy.global_position - up * DROP_SPEED * canopy_radius * delta
	var rest := canopy_radius * 0.02
	if planet.altitude(pos) <= rest:
		pos = planet.global_position + up * (planet.radius + rest)
		_collapse = 1.0
		_settled = true
	var spread := lerpf(1.0, 1.2, _collapse)
	var shape := Vector3(spread, lerpf(1.0, 0.08, _collapse), spread)
	_canopy.global_transform = Transform3D(_basis_up(up) * Basis.from_scale(shape), pos)


func _basis_up(up: Vector3) -> Basis:
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, up, side.cross(up)).orthonormalized()


# Point on the canopy (hem at y = 0): `u` runs around in gores (0..gores),
# `v` from the vent (0) to the hem (1). Each gore bulges out between its seams,
# and the hem rises between the lines into scallops.
func _canopy_point(u: float, v: float, gores: int) -> Vector3:
	var sphere := canopy_radius / sin(SPAN)
	var bulge := sin(PI * fposmod(u, 1.0))
	var phi := lerpf(VENT, 1.0, v) * SPAN
	var r := sphere * sin(phi) * (1.0 + 0.045 * bulge * sin(PI * v * 0.9 + 0.3))
	var y := sphere * (cos(phi) - cos(SPAN)) + canopy_radius * 0.07 * bulge * pow(v, 6.0)
	var a := TAU * u / float(gores)
	return Vector3(cos(a) * r, y, sin(a) * r)


func _build(color: Color, line_width: float, gores: int) -> void:
	var white := Color(0.96, 0.95, 0.92)
	var hem := color.darkened(0.15)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0.0, -canopy_radius / sin(SPAN) * cos(SPAN), 0.0)
	const COLS := 6
	const ROWS := 12
	for g in gores:
		var cloth := color if g % 2 == 0 else white
		for row in ROWS:
			for col in COLS:
				var u0 := g + float(col) / COLS
				var u1 := g + float(col + 1) / COLS
				var v0 := float(row) / ROWS
				var v1 := float(row + 1) / ROWS
				# Clockwise seen from outside (Godot's front face), so the
				# outside is lit from outside and the inside from inside.
				for corner in [[u1, v0], [u0, v0], [u0, v1], [u1, v0], [u0, v1], [u1, v1]]:
					var p := _canopy_point(corner[0], corner[1], gores)
					var f := fposmod(corner[0], 1.0)
					var c := hem if corner[1] > 0.88 else cloth
					if f < 0.04 or f > 0.96:
						c = c.darkened(0.12)  # seam tape
					st.set_color(c)
					st.set_normal((p - center).normalized())
					st.add_vertex(p)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.85
	# Light comes through the cloth, so it glows seen from underneath.
	mat.backlight_enabled = true
	mat.backlight = Color(0.55, 0.5, 0.45)
	_canopy = MeshInstance3D.new()
	_canopy.name = "Canopy"
	_canopy.mesh = st.commit()
	_canopy.material_override = mat
	_canopy.position = Vector3(0.0, canopy_height, 0.0)
	add_child(_canopy)

	# Lines from the hem at each seam gather at a link a little above the
	# harness; two risers carry them down to it.
	var cord := StandardMaterial3D.new()
	cord.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cord.albedo_color = Color(0.82, 0.82, 0.78)
	_lines = Node3D.new()
	_lines.name = "Lines"
	add_child(_lines)
	var link_height := canopy_height * 0.16
	var links := [Vector3(-canopy_radius * 0.04, link_height, 0.0), Vector3(canopy_radius * 0.04, link_height, 0.0)]
	for g in gores:
		var hem_point := _canopy_point(float(g), 1.0, gores) + Vector3(0.0, canopy_height, 0.0)
		var link: Vector3 = links[0] if hem_point.x < 0.0 else links[1]
		_add_line(link, hem_point, line_width, cord)
	for link in links:
		_add_line(Vector3.ZERO, link, line_width * 2.5, cord)


func _add_line(from: Vector3, to: Vector3, width: float, mat: Material) -> void:
	var line := CylinderMesh.new()
	line.top_radius = width
	line.bottom_radius = width
	line.height = from.distance_to(to)
	line.radial_segments = 4
	line.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = line
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var along := (to - from).normalized()
	var x := along.cross(Vector3.FORWARD if absf(along.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, along, x.cross(along)), (from + to) * 0.5)
	_lines.add_child(mi)
