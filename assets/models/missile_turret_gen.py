"""
MissileTurret generator - ground missile turret with 8 tubes (Blender 4.x)
Paste into Blender's Scripting tab and press Run. Uses bpy + bundled mathutils.

Facing +Y in Blender (-Z forward in Godot), up +Z. Same materials as EnemyRobot.

Exported hierarchy (every node's origin sits on its rotation pivot):
  TurretBase            static, origin at ground centre (drop it on the surface)
   +- TurretYaw         rotate around Blender Z  (Godot: rotation.y)
       +- TurretPitch   rotate around Blender X  (Godot: rotation.x, + = nose up)
           +- Missile1..Missile8     hide one when it fires, show on reload
           +- FirePoint1..FirePoint8 at each tube mouth, -Z forward in Godot
Tube numbering: 1-4 = pod on the -X side, 5-8 = pod on the +X side;
inside each pod: top row first, then bottom row, each row from -X to +X.

Run: Blender -b -P missile_turret_gen.py  (set TURRET_OUT to choose the .glb path)
"""
import bpy
import os
from math import radians, sin, cos
from mathutils import Vector, Matrix

# =====================================================================
# SETTINGS
# =====================================================================
TURRET_SCALE      = 1.0    # 1.0 = ~3.1 m across the feet, ~1.8 m tall
REST_PITCH_DEG    = 15.0   # launcher elevation in the exported rest pose
RED_GLOW          = 8.0
THRUST_GLOW       = 6.0
SEPARATE_MISSILES = True   # False = missiles merged into TurretPitch
SMOOTH_ANGLE      = 35.0
TRI_BUDGET        = 12000  # only used for a warning print
EXPORT_FILE       = "missile_turret.glb"

BASE_H  = 0.45             # height of the yaw pivot (top of the base)
PITCH_H = 1.45             # height of the pitch axis
YAW_PIVOT   = Vector((0.0, 0.0, BASE_H))
PITCH_PIVOT = Vector((0.0, 0.0, PITCH_H))
V = lambda x, y, z: Vector((x, y, z))

# =====================================================================
# CLEAR SCENE (removes ALL objects so the script can be re-run)
# =====================================================================
act = bpy.context.view_layer.objects.active
if act and act.mode != 'OBJECT':
    try:
        bpy.ops.object.mode_set(mode='OBJECT')
    except RuntimeError:
        pass
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)

# =====================================================================
# MATERIALS
# =====================================================================
def make_material(name, base, metallic, roughness, emission=None, strength=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    out.location = (300, 0)
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    bsdf.inputs['Base Color'].default_value = (*base, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Emission Color'].default_value = (*(emission or (0.0, 0.0, 0.0)), 1.0)
    bsdf.inputs['Emission Strength'].default_value = strength
    mat.diffuse_color = (*(emission or base), 1.0)
    return mat

CHROME   = make_material("Chrome",       (0.60, 0.62, 0.65), 1.0, 0.25)
GUNMETAL = make_material("Gunmetal",     (0.12, 0.12, 0.14), 0.9, 0.45)
RED      = make_material("RedGlow",      (0.25, 0.0, 0.0),   0.0, 0.40,
                         (1.0, 0.05, 0.02), RED_GLOW)
THRUST   = make_material("ThrusterGlow", (0.30, 0.08, 0.0),  0.0, 0.40,
                         (1.0, 0.35, 0.05), THRUST_GLOW)

# =====================================================================
# HELPERS (parts are collected into named groups -> one object per group)
# =====================================================================
GROUPS, CUTTERS = {}, []
_current = None
AX = {'X': 0, 'Y': 1, 'Z': 2}

def group(name):
    global _current
    _current = GROUPS.setdefault(name, [])

def prim(kind, name, mat, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1),
         verts=16, seg=16, rings=8, r2=0.0, major=16, minor_seg=4, minor=0.1,
         cutter=False):
    """Add a primitive; `scale` = half-extents, baked into the mesh."""
    if kind == 'cube':
        bpy.ops.mesh.primitive_cube_add(size=2.0)
    elif kind == 'cyl':
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=1.0, depth=2.0)
    elif kind == 'cone':
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=1.0, radius2=r2, depth=2.0)
    elif kind == 'sphere':
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1.0)
    elif kind == 'torus':
        bpy.ops.mesh.primitive_torus_add(major_segments=major, minor_segments=minor_seg,
                                         major_radius=1.0, minor_radius=minor)
    else:
        raise ValueError(kind)
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    obj.data.transform(Matrix.Diagonal(Vector(scale)).to_4x4())
    obj.location = Vector(loc)
    obj.rotation_euler = rot
    if mat:
        obj.data.materials.append(mat)
    if cutter:
        obj.display_type = 'WIRE'
        obj.hide_render = True
        CUTTERS.append(obj)
    else:
        _current.append(obj)
    return obj

def aim(obj, direction):
    q = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized())
    obj.rotation_euler = q.to_euler()

def rod(name, mat, p1, p2, r1, r2=None, verts=12, cutter=False):
    """Cylinder (or cone if r2 given) from p1 to p2."""
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    half = d.length / 2.0
    if r2 is None:
        obj = prim('cyl', name, mat, scale=(r1, r1, half), verts=verts, cutter=cutter)
    else:
        obj = prim('cone', name, mat, scale=(r1, r1, half), verts=verts,
                   r2=r2 / r1, cutter=cutter)
    obj.location = (p1 + p2) / 2.0
    aim(obj, d)
    return obj

def taper(obj, along, **factors):
    a = AX[along]
    vs = obj.data.vertices
    vals = [v.co[a] for v in vs]
    lo, hi = min(vals), max(vals)
    span = (hi - lo) or 1.0
    for v in vs:
        t = (v.co[a] - lo) / span
        co = v.co.copy()
        for k, f in factors.items():
            co[AX[k]] *= 1.0 + (f - 1.0) * t
        v.co = co
    obj.data.update()

def bevel(obj, width, segs=2, angle=35.0):
    m = obj.modifiers.new("Bevel", 'BEVEL')
    m.width = width
    m.segments = segs
    m.limit_method = 'ANGLE'
    m.angle_limit = radians(angle)

def cut(target, cutter_obj):
    """Boolean difference; cut walls take the cutter's material."""
    m = target.modifiers.new("Cut", 'BOOLEAN')
    m.operation = 'DIFFERENCE'
    m.solver = 'EXACT'
    m.object = cutter_obj
    try:
        m.material_mode = 'TRANSFER'
    except (AttributeError, TypeError):
        pass

def slot_cutter(name, mat, loc, scale, count):
    """Cube cutter repeated upward with an Array modifier (vent slits)."""
    c = prim('cube', name, mat, loc, scale=scale, cutter=True)
    arr = c.modifiers.new("Array", 'ARRAY')
    arr.count = count
    arr.relative_offset_displace = (0.0, 0.0, 3.0)
    return c

def light(name, pos, r=0.03):
    return prim('sphere', name, RED, pos, scale=(r, r, r), seg=8, rings=6)

# =====================================================================
# BASE - static octagonal platform, 4 braced legs, warning lights
# =====================================================================
group("TurretBase")
plat = prim('cyl', "Platform", GUNMETAL, (0, 0, 0.14), rot=(0, 0, radians(22.5)),
            scale=(1.0, 1.0, 0.14), verts=8)
taper(plat, 'Z', X=0.85, Y=0.85)
bevel(plat, 0.03, 2)
collar = prim('cyl', "BaseCollar", GUNMETAL, (0, 0, 0.34), scale=(0.78, 0.78, 0.06), verts=16)
bevel(collar, 0.015, 1)
prim('cyl', "YawBearing", CHROME, (0, 0, 0.425), scale=(0.70, 0.70, 0.025), verts=24)

for i in range(4):
    a = radians(45 + 90 * i)
    d = V(cos(a), sin(a), 0)
    rod("LegStrut", GUNMETAL, d * 0.70 + V(0, 0, 0.18), d * 1.42 + V(0, 0, 0.06), 0.07, verts=8)
    foot = prim('cyl', "FootPad", GUNMETAL, d * 1.48 + V(0, 0, 0.04),
                scale=(0.18, 0.18, 0.04), verts=8)
    bevel(foot, 0.01, 1)
    rod("LegPiston", GUNMETAL, d * 0.78 + V(0, 0, 0.36), d * 1.05 + V(0, 0, 0.24), 0.04, verts=8)
    rod("LegPistonRod", CHROME, d * 1.05 + V(0, 0, 0.24), d * 1.40 + V(0, 0, 0.09), 0.022, verts=8)
    b = radians(90 * i)
    light("BaseLight", V(cos(b), sin(b), 0) * 0.83 + V(0, 0, 0.2), r=0.035)

# =====================================================================
# YAW - turntable, armoured housing, yoke arms, radar
# =====================================================================
group("TurretYaw")
tt = prim('cyl', "Turntable", GUNMETAL, (0, 0, 0.49), scale=(0.68, 0.68, 0.04), verts=24)
bevel(tt, 0.012, 1)

housing = prim('cube', "Housing", GUNMETAL, (0, -0.02, 0.715), scale=(0.52, 0.5, 0.185))
taper(housing, 'Y', X=0.8)                       # narrower toward the front
bevel(housing, 0.03, 2)
cut(housing, slot_cutter("VentCut", THRUST, (0, -0.52, 0.64), (0.28, 0.05, 0.012), 3))

glacis = prim('cube', "Glacis", GUNMETAL, (0, 0.5, 0.66), rot=(radians(35), 0, 0),
              scale=(0.4, 0.12, 0.1))
taper(glacis, 'Z', X=0.75)
bevel(glacis, 0.015, 2)

for s in (-1, 1):
    arm = prim('cube', "YokeArm", GUNMETAL, (s * 0.62, 0, 1.065), scale=(0.08, 0.26, 0.535))
    taper(arm, 'Z', Y=0.6)
    bevel(arm, 0.02, 2)
    rod("ArmPiston", GUNMETAL, (s * 0.73, -0.12, 0.78), (s * 0.73, -0.06, 1.10), 0.03, verts=10)
    rod("ArmPistonRod", CHROME, (s * 0.73, -0.06, 1.10), (s * 0.73, -0.02, 1.38), 0.016, verts=8)
    light("ArmLight", V(s * 0.62, 0.12, 1.58), r=0.03)

prim('cube', "RadarBracket", GUNMETAL, (0, -0.56, 0.84), scale=(0.06, 0.06, 0.06))
rod("RadarMast", CHROME, (0, -0.6, 0.84), (0, -0.6, 1.12), 0.02, verts=8)
dish_c = V(0, -0.62, 1.18)
dish_d = V(0, -1, 0.7).normalized()
rod("RadarDish", CHROME, dish_c - 0.03 * dish_d, dish_c + 0.05 * dish_d, 0.17, r2=0.03, verts=16)
light("RadarLight", dish_c + 0.07 * dish_d, r=0.02)

# =====================================================================
# PITCH - two 2x2 launcher pods, axle, trunnions, sensor eye
# =====================================================================
group("TurretPitch")
PZ = PITCH_H
T = 0.095                                        # tube offset from pod centre
TUBES = []
for s in (-1, 1):
    cx = s * 0.34
    pod = prim('cube', "LauncherPod", GUNMETAL, (cx, 0, PZ), scale=(0.2, 0.45, 0.2))
    bevel(pod, 0.02, 2)
    armor = prim('cube', "PodArmor", CHROME, (cx, -0.05, PZ + 0.215), scale=(0.19, 0.3, 0.018))
    bevel(armor, 0.008, 1)
    cut(pod, slot_cutter("BackblastCut", THRUST, (cx, -0.45, PZ - 0.1), (0.14, 0.04, 0.012), 3))
    light("PodLight", V(s * 0.545, 0.35, PZ + 0.12), r=0.02)
    for dz in (T, -T):                          # top row, then bottom row
        for dx in (-T, T):                      # -X to +X
            c = V(cx + dx, 0, PZ + dz)
            bore = rod("TubeBore", GUNMETAL, c + V(0, 0.10, 0), c + V(0, 0.60, 0), 0.068,
                       verts=16, cutter=True)
            cut(pod, bore)
            rim = rod("TubeRim", CHROME, c + V(0, 0.43, 0), c + V(0, 0.49, 0), 0.082, verts=16)
            cut(rim, bore)
            TUBES.append(c)

rod("Axle", GUNMETAL, (-0.70, 0, PZ), (0.70, 0, PZ), 0.07, verts=16)
for s in (-1, 1):
    cap = rod("TrunnionCap", CHROME, (s * 0.70, 0, PZ), (s * 0.75, 0, PZ), 0.1, verts=16)
    bevel(cap, 0.01, 1)

sensor = prim('cube', "SensorBlock", GUNMETAL, (0, 0.08, PZ), scale=(0.11, 0.34, 0.13))
taper(sensor, 'Y', X=0.8, Z=0.8)
bevel(sensor, 0.015, 2)
prim('sphere', "SensorEye", RED, (0, 0.42, PZ + 0.01), scale=(0.045, 0.03, 0.045), seg=12, rings=8)
ring = prim('torus', "EyeRing", CHROME, (0, 0.415, PZ + 0.01), scale=(0.058,) * 3,
            major=16, minor_seg=4, minor=0.15)
aim(ring, (0, 1, 0))

# =====================================================================
# MISSILES - one per tube, noses poking out of the rims
# =====================================================================
MISSILE_PIVOTS = {}
for i, c in enumerate(TUBES, 1):
    name = f"Missile{i}" if SEPARATE_MISSILES else "TurretPitch"
    group(name)
    rod("MissileBody", CHROME, c + V(0, 0.20, 0), c + V(0, 0.50, 0), 0.055, verts=12)
    rod("MissileBand", RED, c + V(0, 0.50, 0), c + V(0, 0.515, 0), 0.057, verts=12)
    rod("MissileNose", GUNMETAL, c + V(0, 0.515, 0), c + V(0, 0.64, 0), 0.055, r2=0.004, verts=12)
    if SEPARATE_MISSILES:
        MISSILE_PIVOTS[name] = c + V(0, 0.42, 0)

# =====================================================================
# APPLY MODIFIERS, delete cutters, bake transforms into meshes
# =====================================================================
ALL_PARTS = [o for parts in GROUPS.values() for o in parts]
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
baked = [(o, bpy.data.meshes.new_from_object(o.evaluated_get(dg)))
         for o in ALL_PARTS if o.modifiers]
for obj, new_me in baked:
    old = obj.data
    mats = list(old.materials)
    obj.modifiers.clear()
    obj.data = new_me
    if len(new_me.materials) == 0:
        for m in mats:
            new_me.materials.append(m)
    bpy.data.meshes.remove(old)
for c in CUTTERS:
    bpy.data.objects.remove(c, do_unlink=True)

bpy.context.view_layer.update()
for obj in ALL_PARTS:
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)

# =====================================================================
# JOIN each group, move origin to its pivot, build the hierarchy
# =====================================================================
PIVOTS = {"TurretBase": V(0, 0, 0), "TurretYaw": YAW_PIVOT, "TurretPitch": PITCH_PIVOT}
PIVOTS.update(MISSILE_PIVOTS)
PARENT = {"TurretYaw": "TurretBase", "TurretPitch": "TurretYaw"}
PARENT.update({n: "TurretPitch" for n in MISSILE_PIVOTS})

OBJS = {}
for name, parts in GROUPS.items():          # order: base, yaw, pitch, missiles
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    pivot = PIVOTS[name]
    obj.data.transform(Matrix.Scale(TURRET_SCALE, 4) @ Matrix.Translation(-pivot))
    obj.data.update()
    if name in PARENT:
        obj.parent = OBJS[PARENT[name]]
        obj.location = (pivot - PIVOTS[PARENT[name]]) * TURRET_SCALE
    OBJS[name] = obj

# FirePoint empties at each tube mouth (children of TurretPitch)
pitch = OBJS["TurretPitch"]
FIREPOINTS = []
for i, c in enumerate(TUBES, 1):
    fp = bpy.data.objects.new(f"FirePoint{i}", None)
    fp.empty_display_type = 'ARROWS'
    fp.empty_display_size = 0.08
    pitch.users_collection[0].objects.link(fp)
    fp.parent = pitch
    fp.location = (c + V(0, 0.68, 0) - PITCH_PIVOT) * TURRET_SCALE
    FIREPOINTS.append(fp)

# rest pose: launcher raised a little (Godot receives this as TurretPitch rotation)
pitch.rotation_euler = (radians(REST_PITCH_DEG), 0.0, 0.0)

# =====================================================================
# SHADING + TRIANGLE COUNT
# =====================================================================
meshes = list(OBJS.values())
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = OBJS["TurretBase"]
try:
    bpy.ops.object.shade_smooth_by_angle(angle=radians(SMOOTH_ANGLE))   # Blender 4.1+
except Exception:
    bpy.ops.object.shade_smooth()                                         # Blender 4.0
    for o in meshes:
        try:
            o.data.use_auto_smooth = True
            o.data.auto_smooth_angle = radians(SMOOTH_ANGLE)
        except AttributeError:
            pass

tris = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
if tris > TRI_BUDGET:
    print(f"WARNING: {tris} triangles is over the {TRI_BUDGET} budget")

# =====================================================================
# EXPORT
# =====================================================================
if bpy.data.is_saved:
    path = bpy.path.abspath("//" + EXPORT_FILE)
else:
    path = os.path.join(os.path.expanduser("~"), EXPORT_FILE)
path = os.environ.get("TURRET_OUT", path)   # optional override

bpy.ops.object.select_all(action='DESELECT')
for o in meshes + FIREPOINTS:
    o.select_set(True)
bpy.context.view_layer.objects.active = OBJS["TurretBase"]
bpy.ops.export_scene.gltf(
    filepath=path,
    export_format='GLB',
    use_selection=True,
    export_yup=True,
    export_apply=True,
)
print(f"MissileTurret: {tris} triangles, {len(meshes)} mesh nodes, {len(FIREPOINTS)} fire points")
print(f"Exported to {path}")
