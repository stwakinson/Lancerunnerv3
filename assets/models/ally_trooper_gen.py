"""
AllyTrooper generator - friendly armoured soldier (Blender 4.x)
The player's side on the ground, in the player's ship colours: white armour
with grey trim (the ship's hull) and cyan glows (its engines), a rounded
helmet with a glowing visor, rounded shoulder pads and a rifle held in both
hands. Nothing skeletal, spiked or red, so it reads as a friend next to the
enemy robots.

Same jointed hierarchy as the enemy GroundRobot, so the same walk animation
drives it:

    Trooper (root, scaled to TARGET_HEIGHT, origin between the feet)
      Pelvis
        Torso
          Head
          UpperArm_L > LowerArm_L
          UpperArm_R > LowerArm_R (rifle) > FirePoint
        Thigh_L > Shin_L > Foot_L
        Thigh_R > Shin_R > Foot_R

Every joint's origin sits on its pivot with no rotation. Faces +Y in Blender
(-Z in Godot), up +Z.

Run: Blender -b -P ally_trooper_gen.py   (set TROOPER_OUT to choose the .glb path)
"""
import bpy
import os
from math import radians, pi
from mathutils import Vector, Matrix

# =====================================================================
# SETTINGS
# =====================================================================
TARGET_HEIGHT = 3.4     # same export height as the GroundRobot (the game rescales)
SMOOTH_ANGLE  = 40.0
EXPORT_FILE   = "ally_trooper.glb"

# =====================================================================
# CLEAR SCENE
# =====================================================================
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)

# =====================================================================
# MATERIALS - clean, bright, friendly
# =====================================================================
def make_material(name, base, metallic, roughness, emission=None, strength=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    bsdf.inputs['Base Color'].default_value = (*base, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Emission Color'].default_value = (*(emission or (0.0, 0.0, 0.0)), 1.0)
    bsdf.inputs['Emission Strength'].default_value = strength
    mat.diffuse_color = (*(emission or base), 1.0)
    return mat

WHITE  = make_material("ArmorWhite", (0.86, 0.88, 0.92), 0.15, 0.35)
# Trim in the ship's grey hull colour (the variable keeps its old name).
BLUE   = make_material("ArmorGrey",  (0.34, 0.35, 0.38), 0.4,  0.4)
SUIT   = make_material("Undersuit",  (0.16, 0.17, 0.2),  0.1,  0.7)
VISOR  = make_material("VisorGlow",  (0.05, 0.25, 0.35), 0.0,  0.1, (0.25, 0.85, 1.0), 5.0)
RIFLE  = make_material("Rifle",      (0.2, 0.21, 0.24),  0.7,  0.4)
LAMP   = make_material("BlueLamp",   (0.05, 0.2, 0.5),   0.0,  0.3, (0.3, 0.6, 1.0), 6.0)

# =====================================================================
# HELPERS - every part goes into the current segment (joint)
# =====================================================================
SEGS = {}
SEG = None

def segment(name):
    global SEG
    SEG = name
    SEGS.setdefault(name, [])

def prim(kind, name, mat, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1),
         verts=16, seg=16, rings=8, r2=0.0):
    if kind == 'cube':
        bpy.ops.mesh.primitive_cube_add(size=2.0)
    elif kind == 'cyl':
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=1.0, depth=2.0)
    elif kind == 'cone':
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=1.0, radius2=r2, depth=2.0)
    elif kind == 'sphere':
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1.0)
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    obj.data.transform(Matrix.Diagonal(Vector(scale)).to_4x4())
    obj.location = Vector(loc)
    obj.rotation_euler = rot
    obj.data.materials.append(mat)
    SEGS[SEG].append(obj)
    return obj

def aim(obj, direction):
    q = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized())
    obj.rotation_euler = q.to_euler()

def rod(name, mat, p1, p2, r1, r2=None, verts=14):
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    half = d.length / 2.0
    if r2 is None:
        obj = prim('cyl', name, mat, scale=(r1, r1, half), verts=verts)
    else:
        obj = prim('cone', name, mat, scale=(r1, r1, half), verts=verts, r2=r2 / r1)
    obj.location = (p1 + p2) / 2.0
    aim(obj, d)
    return obj

def soft(obj, width=0.02, segs=3):
    """Rounded, friendly edges."""
    m = obj.modifiers.new("Bevel", 'BEVEL')
    m.width = width
    m.segments = segs
    m.limit_method = 'ANGLE'
    m.angle_limit = radians(30)

def plate(name, mat, loc, half, rot=(0, 0, 0), round_w=0.02):
    o = prim('cube', name, mat, loc, rot=rot, scale=half)
    soft(o, round_w)
    return o

PIVOT = {
    "Pelvis": Vector((0.0, 0.0, 0.98)),
    "Torso":  Vector((0.0, 0.0, 1.04)),
    "Head":   Vector((0.0, 0.0, 1.62)),
}
PARENT = {"Pelvis": None, "Torso": "Pelvis", "Head": "Torso"}
FIRE_TIP = None

# =====================================================================
# HEAD - rounded helmet, wide glowing visor, small antenna
# =====================================================================
segment("Head")
H = Vector((0.0, 0.0, 1.8))
helmet = prim('sphere', "Helmet", WHITE, H, scale=(0.14, 0.15, 0.15), seg=24, rings=14)
prim('sphere', "HelmetStripe", BLUE, H + Vector((0, -0.005, 0.02)), scale=(0.03, 0.155, 0.155), seg=16, rings=10)
visor = prim('sphere', "Visor", VISOR, H + Vector((0, 0.075, -0.01)), scale=(0.115, 0.085, 0.06), seg=20, rings=10)
jaw = plate("ChinGuard", WHITE, H + Vector((0, 0.07, -0.1)), (0.085, 0.06, 0.035), round_w=0.025)
for s in (-1, 1):
    prim('cyl', "EarPod", BLUE, H + Vector((s * 0.14, 0.0, -0.01)), rot=(0, radians(90), 0),
         scale=(0.045, 0.045, 0.02), verts=16)
rod("Antenna", SUIT, H + Vector((0.1, -0.06, 0.08)), H + Vector((0.13, -0.08, 0.2)), 0.006, verts=6)
prim('sphere', "AntennaTip", LAMP, H + Vector((0.13, -0.08, 0.205)), scale=(0.012,) * 3, seg=8, rings=6)
rod("Neck", SUIT, PIVOT["Head"], PIVOT["Head"] + Vector((0, 0, 0.1)), 0.05, verts=12)

# =====================================================================
# TORSO - chest armour, blue shoulder yoke, backpack
# =====================================================================
segment("Torso")
T = Vector((0.0, 0.0, 1.32))
rod("Abdomen", SUIT, PIVOT["Torso"], T + Vector((0, 0, -0.05)), 0.12, verts=16)
chest = plate("ChestPlate", WHITE, T + Vector((0, 0.03, 0.08)), (0.19, 0.12, 0.17), round_w=0.05)
plate("ChestBand", BLUE, T + Vector((0, 0.13, 0.02)), (0.15, 0.015, 0.03), round_w=0.01)
prim('sphere', "ChestLamp", LAMP, T + Vector((0.08, 0.15, 0.13)), scale=(0.02, 0.01, 0.02), seg=10, rings=6)
plate("Collar", BLUE, T + Vector((0, 0.0, 0.26)), (0.16, 0.1, 0.03), round_w=0.02)
plate("Backpack", WHITE, T + Vector((0, -0.17, 0.05)), (0.14, 0.06, 0.16), round_w=0.04)
plate("BackpackStripe", BLUE, T + Vector((0, -0.235, 0.05)), (0.04, 0.005, 0.12), round_w=0.004)
plate("Belt", BLUE, PIVOT["Torso"] + Vector((0, 0, 0.02)), (0.15, 0.1, 0.03), round_w=0.02)

# =====================================================================
# PELVIS
# =====================================================================
segment("Pelvis")
P0 = PIVOT["Pelvis"]
plate("Hips", SUIT, P0, (0.15, 0.09, 0.06), round_w=0.03)
plate("HipGuard", WHITE, P0 + Vector((0, 0.08, -0.04)), (0.1, 0.02, 0.06), rot=(radians(-10), 0, 0), round_w=0.015)

# =====================================================================
# LEGS - white thigh and shin armour over a dark suit, rounded boots
# =====================================================================
for s, side in ((-1, "L"), (1, "R")):
    x0 = s * 0.11
    Hp = Vector((x0, 0.0, 0.93))
    K = Vector((x0, 0.015, 0.52))
    A = Vector((x0, 0.0, 0.11))
    PIVOT["Thigh_" + side], PARENT["Thigh_" + side] = Hp, "Pelvis"
    PIVOT["Shin_" + side], PARENT["Shin_" + side] = K, "Thigh_" + side
    PIVOT["Foot_" + side], PARENT["Foot_" + side] = A, "Shin_" + side

    segment("Thigh_" + side)
    rod("ThighSuit", SUIT, Hp, K, 0.07, verts=14)
    plate("ThighArmor", WHITE, (Hp + K) / 2 + Vector((0, 0.03, 0.02)), (0.075, 0.055, 0.15), round_w=0.035)

    segment("Shin_" + side)
    prim('sphere', "Knee", BLUE, K + Vector((0, 0.04, 0)), scale=(0.06, 0.05, 0.06), seg=14, rings=8)
    rod("ShinSuit", SUIT, K, A, 0.06, verts=14)
    plate("ShinArmor", WHITE, (K + A) / 2 + Vector((0, 0.035, 0.03)), (0.065, 0.045, 0.15), round_w=0.03)

    segment("Foot_" + side)
    boot = plate("Boot", WHITE, Vector((x0, 0.04, 0.05)), (0.07, 0.12, 0.055), round_w=0.04)
    plate("Sole", SUIT, Vector((x0, 0.04, 0.008)), (0.072, 0.125, 0.012), round_w=0.008)
    plate("BootStripe", BLUE, Vector((x0, 0.13, 0.07)), (0.05, 0.02, 0.02), round_w=0.01)

# =====================================================================
# ARMS - rounded shoulder pads; right hand holds the rifle forward
# =====================================================================
for s, side in ((-1, "L"), (1, "R")):
    Sh = Vector((s * 0.25, 0.0, 1.52))
    E = Sh + Vector((s * 0.02, 0.0, -0.27))
    PIVOT["UpperArm_" + side], PARENT["UpperArm_" + side] = Sh, "Torso"
    PIVOT["LowerArm_" + side], PARENT["LowerArm_" + side] = E, "UpperArm_" + side

    segment("UpperArm_" + side)
    prim('sphere', "ShoulderPad", BLUE, Sh + Vector((s * 0.02, 0, 0.03)), scale=(0.1, 0.1, 0.075), seg=18, rings=10)
    rod("UpperArmSuit", SUIT, Sh, E, 0.055, verts=12)
    plate("BicepArmor", WHITE, (Sh + E) / 2 + Vector((s * 0.02, 0.01, 0)), (0.05, 0.055, 0.09), round_w=0.025)

    segment("LowerArm_" + side)
    prim('sphere', "Elbow", SUIT, E, scale=(0.055,) * 3, seg=12, rings=8)
    f = Vector((-s * 0.25, 1.0, 0.05)).normalized()     # forearms reach forward and in
    W = E + 0.25 * f
    rod("Forearm", WHITE, E, W, 0.052, r2=0.045, verts=14)
    prim('sphere', "Glove", SUIT, W + 0.03 * f, scale=(0.045, 0.05, 0.045), seg=12, rings=8)
    if s == 1:
        # Rifle: held level along +Y, stock at the shoulder line.
        g0 = W + Vector((-0.05, -0.08, 0.03))
        g1 = g0 + Vector((0, 0.62, 0))
        plate("RifleBody", RIFLE, g0 + Vector((0, 0.24, 0)), (0.035, 0.22, 0.05), round_w=0.01)
        plate("RifleStock", RIFLE, g0 + Vector((0, -0.07, -0.01)), (0.03, 0.09, 0.045), round_w=0.012)
        rod("RifleBarrel", RIFLE, g0 + Vector((0, 0.45, 0.01)), g1, 0.016, verts=12)
        plate("RifleSight", BLUE, g0 + Vector((0, 0.18, 0.07)), (0.012, 0.05, 0.015), round_w=0.005)
        prim('sphere', "RifleLamp", LAMP, g0 + Vector((0.038, 0.3, 0.0)), scale=(0.012,) * 3, seg=8, rings=6)
        plate("RifleMag", BLUE, g0 + Vector((0, 0.16, -0.07)), (0.022, 0.035, 0.05), round_w=0.008)
        FIRE_TIP = g1 + Vector((0, 0.02, 0))

# =====================================================================
# BAKE modifiers and transforms
# =====================================================================
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
ALL = [o for objs in SEGS.values() for o in objs]
baked = [(o, bpy.data.meshes.new_from_object(o.evaluated_get(dg))) for o in ALL if o.modifiers]
for obj, new_me in baked:
    old = obj.data
    mats = list(old.materials)
    obj.modifiers.clear()
    obj.data = new_me
    if len(new_me.materials) == 0:
        for m in mats:
            new_me.materials.append(m)
    bpy.data.meshes.remove(old)
bpy.context.view_layer.update()
for obj in ALL:
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)

top = max(v.co.z for o in ALL for v in o.data.vertices)

# =====================================================================
# JOIN each segment into one mesh with its origin on the joint pivot
# =====================================================================
JOINTS = {}
for name, objs in SEGS.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    j = bpy.context.view_layer.objects.active
    j.name = name
    j.data.name = name
    j.data.transform(Matrix.Translation(-PIVOT[name]))
    JOINTS[name] = j

bpy.ops.object.select_all(action='DESELECT')
for j in JOINTS.values():
    j.select_set(True)
bpy.context.view_layer.objects.active = JOINTS["Pelvis"]
try:
    bpy.ops.object.shade_smooth_by_angle(angle=radians(SMOOTH_ANGLE))
except Exception:
    bpy.ops.object.shade_smooth()

root = bpy.data.objects.new("Trooper", None)
bpy.context.scene.collection.objects.link(root)
root.scale = Vector((1, 1, 1)) * (TARGET_HEIGHT / top)
for name, j in JOINTS.items():
    parent = PARENT[name]
    j.parent = JOINTS[parent] if parent else root
    j.location = PIVOT[name] - (PIVOT[parent] if parent else Vector())

fp = bpy.data.objects.new("FirePoint", None)
bpy.context.scene.collection.objects.link(fp)
fp.parent = JOINTS["LowerArm_R"]
fp.location = FIRE_TIP - PIVOT["LowerArm_R"]

# =====================================================================
# EXPORT
# =====================================================================
path = bpy.path.abspath("//" + EXPORT_FILE) if bpy.data.is_saved \
    else os.path.join(os.path.expanduser("~"), EXPORT_FILE)
path = os.environ.get("TROOPER_OUT", path)
bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=False,
                          export_yup=True, export_apply=True)
tris = sum(len(p.vertices) - 2 for j in JOINTS.values() for p in j.data.polygons)
print(f"AllyTrooper: {tris} triangles, {len(JOINTS)} joints, height {top:.2f} -> {TARGET_HEIGHT}")
print(f"Exported to {path}")
