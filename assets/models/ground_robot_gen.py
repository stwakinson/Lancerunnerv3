"""
GroundRobot generator - walking Terminator T-800 style endoskeleton (Blender 4.x)
Builds the robot as jointed parts so the game can animate the walk in code:

    Robot (root, scaled to TARGET_HEIGHT, origin between the feet)
      Pelvis
        Torso
          Head
          UpperArm_L > LowerArm_L (claw)
          UpperArm_R > LowerArm_R (cannon) > FirePoint
        Thigh_L > Shin_L > Foot_L
        Thigh_R > Shin_R > Foot_R

Every joint's origin sits on its pivot with no rotation, so swinging a part is
one rotation about its local X axis. Faces +Y in Blender (-Z in Godot), up +Z.

Run: Blender -b -P ground_robot_gen.py   (set ROBOT_OUT to choose the .glb path)
"""
import bpy
import os
from math import radians, sin, cos, pi
from mathutils import Vector, Matrix

# =====================================================================
# SETTINGS
# =====================================================================
TARGET_HEIGHT = 3.4     # game units, feet to top of skull
RED_GLOW      = 8.0
SMOOTH_ANGLE  = 35.0
EXPORT_FILE   = "ground_robot.glb"

# =====================================================================
# CLEAR SCENE
# =====================================================================
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)

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
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    bsdf.inputs['Base Color'].default_value = (*base, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Emission Color'].default_value = (*(emission or (0.0, 0.0, 0.0)), 1.0)
    bsdf.inputs['Emission Strength'].default_value = strength
    mat.diffuse_color = (*(emission or base), 1.0)
    return mat

CHROME   = make_material("Chrome",   (0.60, 0.62, 0.65), 1.0, 0.25)
GUNMETAL = make_material("Gunmetal", (0.12, 0.12, 0.14), 0.9, 0.45)
RED      = make_material("RedGlow",  (0.25, 0.0, 0.0),   0.0, 0.40, (1.0, 0.05, 0.02), RED_GLOW)

# =====================================================================
# HELPERS - every part goes into the current segment (joint)
# =====================================================================
SEGS = {}          # segment name -> [objects]
CUTTERS = []
SEG = None
AX = {'X': 0, 'Y': 1, 'Z': 2}

def segment(name):
    global SEG
    SEG = name
    SEGS.setdefault(name, [])

def prim(kind, name, mat, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1),
         verts=16, seg=16, rings=8, r2=0.0, major=16, minor_seg=4, minor=0.1,
         cutter=False):
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
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    obj.data.transform(Matrix.Diagonal(Vector(scale)).to_4x4())
    obj.location = Vector(loc)
    obj.rotation_euler = rot
    if mat:
        obj.data.materials.append(mat)
    if cutter:
        obj.hide_render = True
        CUTTERS.append(obj)
    else:
        SEGS[SEG].append(obj)
    return obj

def aim(obj, direction):
    q = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized())
    obj.rotation_euler = q.to_euler()

def rod(name, mat, p1, p2, r1, r2=None, verts=12, cutter=False):
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

def subsurf(obj, levels=1):
    m = obj.modifiers.new("Subsurf", 'SUBSURF')
    m.levels = levels
    m.render_levels = levels

def cut(target, cutter_obj):
    m = target.modifiers.new("Cut", 'BOOLEAN')
    m.operation = 'DIFFERENCE'
    m.solver = 'EXACT'
    m.object = cutter_obj
    try:
        m.material_mode = 'TRANSFER'
    except (AttributeError, TypeError):
        pass

def light(name, pos, r=0.014):
    return prim('sphere', name, RED, pos, scale=(r, r, r), seg=8, rings=6)

# Joint pivots (Blender space, human scale; rescaled at the end)
PIVOT = {
    "Pelvis": Vector((0.0, 0.0, 0.98)),
    "Torso":  Vector((0.0, 0.0, 1.04)),
    "Head":   Vector((0.0, -0.02, 1.60)),
}
PARENT = {"Pelvis": None, "Torso": "Pelvis", "Head": "Torso"}
FIRE_TIP = None

# =====================================================================
# HEAD - chrome skull, teeth, red eyes
# =====================================================================
segment("Head")
HEAD = Vector((0.0, 0.02, 1.87))
skull = prim('sphere', "Skull", CHROME, HEAD, scale=(0.13, 0.16, 0.15), seg=20, rings=12)
taper(skull, 'Y', X=0.72)
for s in (-1, 1):
    sock = prim('sphere', "EyeSocketCut", GUNMETAL, HEAD + Vector((s * 0.048, 0.135, 0.01)),
                scale=(0.038, 0.05, 0.03), seg=12, rings=8, cutter=True)
    cut(skull, sock)
    prim('sphere', "Eye", RED, HEAD + Vector((s * 0.048, 0.118, 0.01)),
         scale=(0.024, 0.02, 0.02), seg=10, rings=6)
    brow = prim('cube', "Brow", CHROME, HEAD + Vector((s * 0.05, 0.135, 0.05)),
                rot=(radians(-15), -s * radians(20), 0), scale=(0.05, 0.022, 0.011))
    bevel(brow, 0.005, 1)
    cheek = prim('cube', "Cheek", CHROME, HEAD + Vector((s * 0.075, 0.09, -0.05)),
                 scale=(0.03, 0.04, 0.02))
    bevel(cheek, 0.008, 2)
nose = prim('cube', "NoseCut", GUNMETAL, HEAD + Vector((0, 0.15, -0.035)),
            rot=(0, radians(45), 0), scale=(0.014, 0.05, 0.014), cutter=True)
cut(skull, nose)
maxilla = prim('cube', "Maxilla", CHROME, HEAD + Vector((0, 0.095, -0.095)),
               scale=(0.075, 0.06, 0.04))
taper(maxilla, 'Y', X=0.6)
bevel(maxilla, 0.012, 2)
subsurf(maxilla, 1)
for i in range(8):
    x = -0.0385 + i * 0.011
    prim('cone', "ToothUp", CHROME, HEAD + Vector((x, 0.145 - 8 * x * x, -0.147)),
         rot=(pi, 0, 0), scale=(0.007, 0.007, 0.017), verts=4)
jaw = prim('cube', "Jaw", CHROME, HEAD + Vector((0, 0.05, -0.195)),
           rot=(radians(-8), 0, 0), scale=(0.085, 0.10, 0.03))
taper(jaw, 'Y', X=0.35, Z=0.8)
bevel(jaw, 0.01, 2)
subsurf(jaw, 1)
for i in range(6):
    x = -0.0275 + i * 0.011
    prim('cone', "ToothLow", CHROME, HEAD + Vector((x, 0.125 - 10 * x * x, -0.156)),
         scale=(0.007, 0.007, 0.016), verts=4)
for s in (-1, 1):
    hinge = HEAD + Vector((s * 0.066, 0.0, -0.17))
    prim('cyl', "JawHinge", GUNMETAL, hinge, rot=(0, radians(90), 0),
         scale=(0.022, 0.022, 0.012), verts=12)
    rod("JawStrut", CHROME, HEAD + Vector((s * 0.09, 0.0, -0.06)), hinge, 0.011, verts=8)
N0 = PIVOT["Head"]
rod("Neck", GUNMETAL, N0, N0 + Vector((0, 0, 0.17)), 0.028, verts=10)
for dz in (0.04, 0.08, 0.12):
    prim('cyl', "NeckDisc", CHROME, N0 + Vector((0, 0, dz)), scale=(0.042, 0.042, 0.006), verts=12)
for s in (-1, 1):
    rod("NeckPiston", CHROME, N0 + Vector((s * 0.045, 0.02, 0.01)),
        N0 + Vector((s * 0.04, 0.04, 0.18)), 0.009, verts=8)

# =====================================================================
# TORSO - collar, chest plates, ribs, spine, abdomen
# =====================================================================
segment("Torso")
T = Vector((0.0, 0.0, 0.90))       # offset of the rib cage block
collar = prim('cube', "Collar", GUNMETAL, T + Vector((0, 0.02, 0.67)), scale=(0.20, 0.09, 0.035))
bevel(collar, 0.015, 2)
subsurf(collar, 1)
for s in (-1, 1):
    light("CollarLight", T + Vector((s * 0.06, 0.125, 0.665)), r=0.012)
    pec_loc = T + Vector((s * 0.09, 0.10, 0.54))
    pec_rot = (radians(10), 0, -s * radians(20))
    pec = prim('cube', "ChestPlate", GUNMETAL, pec_loc, rot=pec_rot, scale=(0.085, 0.025, 0.10))
    taper(pec, 'Z', X=1.2)
    bevel(pec, 0.012, 2)
    slit = prim('cube', "SlitCut", GUNMETAL, pec_loc + Vector((0, 0, -0.065)),
                rot=pec_rot, scale=(0.06, 0.06, 0.006), cutter=True)
    arr = slit.modifiers.new("Array", 'ARRAY')
    arr.count = 3
    arr.relative_offset_displace = (0.0, 0.0, 3.0)
    cut(pec, slit)
    rod("Clavicle", CHROME, T + Vector((s * 0.15, 0.02, 0.66)),
        T + Vector((s * 0.25, -0.01, 0.60)), 0.02, verts=10)
sternum = prim('cube', "Sternum", CHROME, T + Vector((0, 0.135, 0.40)), scale=(0.022, 0.018, 0.15))
bevel(sternum, 0.006, 1)
for i, z in enumerate((0.58, 0.50, 0.42, 0.34, 0.27)):
    R = 0.17 - i * 0.012
    prim('torus', "Rib", CHROME, T + Vector((0, -0.01, z)), rot=(radians(-14), 0, 0),
         scale=(R, R * 0.75, R), major=18, minor_seg=5, minor=0.08)
spine_pts = []
for i in range(8):
    t = i / 7
    z = 0.70 - t * 0.56
    y = -0.12 - 0.025 * sin(pi * t)
    p = T + Vector((0, y, z))
    spine_pts.append(p)
    vb = prim('cube', "Vertebra", GUNMETAL, p, scale=(0.045, 0.035, 0.024))
    bevel(vb, 0.008, 1)
    rod("SpineSpike", CHROME, p + Vector((0, -0.03, 0)), p + Vector((0, -0.08, 0.02)),
        0.012, r2=0.0, verts=4)
rod("SpinalCord", GUNMETAL, spine_pts[0], spine_pts[-1], 0.018, verts=10)
for a, b in zip(spine_pts[:-1], spine_pts[1:]):
    light("SpineLight", (a + b) / 2 + Vector((0, -0.028, 0)), r=0.013)
# abdomen: exposed lower spine column with discs and side pistons
W0 = PIVOT["Torso"]
rod("LowerSpine", GUNMETAL, W0 + Vector((0, -0.04, -0.02)), W0 + Vector((0, -0.08, 0.22)),
    0.038, verts=12)
for dz in (0.04, 0.10, 0.16):
    prim('cyl', "AbDisc", CHROME, W0 + Vector((0, -0.05 - dz * 0.12, dz)),
         scale=(0.06, 0.05, 0.008), verts=14)
for s in (-1, 1):
    rod("AbPiston", CHROME, W0 + Vector((s * 0.08, 0.03, 0.0)),
        W0 + Vector((s * 0.10, 0.02, 0.22)), 0.012, verts=8)

# =====================================================================
# PELVIS
# =====================================================================
segment("Pelvis")
P0 = PIVOT["Pelvis"]
pelvis = prim('cube', "PelvisBlock", GUNMETAL, P0 + Vector((0, -0.01, 0.0)),
              scale=(0.16, 0.08, 0.055))
taper(pelvis, 'Z', X=1.15)
bevel(pelvis, 0.015, 2)
subsurf(pelvis, 1)
groin = prim('cube', "GroinPlate", CHROME, P0 + Vector((0, 0.07, -0.05)),
             rot=(radians(-12), 0, 0), scale=(0.05, 0.015, 0.06))
taper(groin, 'Z', X=1.6)
bevel(groin, 0.008, 1)
light("BeltLight", P0 + Vector((0, 0.09, 0.02)), r=0.015)
for s in (-1, 1):
    prim('cyl', "HipHousing", CHROME, P0 + Vector((s * 0.13, 0, -0.03)),
         rot=(0, radians(90), 0), scale=(0.055, 0.055, 0.03), verts=16)

# =====================================================================
# LEGS
# =====================================================================
for s, side in ((-1, "L"), (1, "R")):
    x0 = s * 0.13
    H = Vector((x0, 0.0, 0.93))
    K = Vector((x0, 0.02, 0.52))
    A = Vector((x0, -0.01, 0.11))
    PIVOT["Thigh_" + side], PARENT["Thigh_" + side] = H, "Pelvis"
    PIVOT["Shin_" + side], PARENT["Shin_" + side] = K, "Thigh_" + side
    PIVOT["Foot_" + side], PARENT["Foot_" + side] = A, "Shin_" + side

    segment("Thigh_" + side)
    prim('sphere', "HipBall", CHROME, H, scale=(0.055,) * 3, seg=16, rings=8)
    rod("Femur", CHROME, H, K, 0.032, verts=12)
    rod("ThighPiston", GUNMETAL, H + Vector((s * 0.05, 0.02, -0.06)),
        H + Vector((s * 0.05, 0.03, -0.26)), 0.02, verts=10)
    rod("ThighPistonRod", CHROME, H + Vector((s * 0.05, 0.03, -0.26)),
        K + Vector((s * 0.04, 0.0, 0.03)), 0.01, verts=8)
    plate = prim('cube', "ThighPlate", GUNMETAL, (H + K) / 2 + Vector((0, 0.05, 0.04)),
                 scale=(0.055, 0.018, 0.13))
    taper(plate, 'Z', X=1.3)
    bevel(plate, 0.01, 2)
    light("HipLight", H + Vector((s * 0.05, 0.03, 0.0)), r=0.013)

    segment("Shin_" + side)
    prim('sphere', "KneeBall", CHROME, K, scale=(0.045,) * 3, seg=14, rings=8)
    cap = prim('cube', "KneeCap", GUNMETAL, K + Vector((0, 0.045, 0.0)), scale=(0.04, 0.015, 0.05))
    bevel(cap, 0.01, 2)
    for k in (-1, 1):
        rod("ShinBone", CHROME, K + Vector((k * 0.018, 0, -0.02)), A + Vector((k * 0.016, 0, 0.02)),
            0.017, verts=8)
    rod("CalfPiston", GUNMETAL, K + Vector((0, -0.05, -0.06)), K + Vector((0, -0.05, -0.24)),
        0.022, verts=10)
    rod("CalfPistonRod", CHROME, K + Vector((0, -0.05, -0.24)), A + Vector((0, -0.04, 0.04)),
        0.011, verts=8)
    light("KneeLight", K + Vector((s * 0.045, 0.0, 0.0)), r=0.012)

    segment("Foot_" + side)
    prim('sphere', "AnkleBall", GUNMETAL, A, scale=(0.036,) * 3, seg=12, rings=6)
    foot = prim('cube', "FootPlate", GUNMETAL, Vector((x0, 0.05, 0.035)),
                scale=(0.055, 0.12, 0.035))
    taper(foot, 'Y', X=1.25, Z=0.6)
    bevel(foot, 0.012, 2)
    rod("AnkleStrut", CHROME, A, Vector((x0, 0.03, 0.06)), 0.016, verts=8)
    for k in (-1, 0, 1):
        tb = Vector((x0 + k * 0.03, 0.16, 0.03))
        rod("Toe", CHROME, tb, tb + Vector((k * 0.01, 0.06, -0.015)), 0.016, r2=0.003, verts=6)
    rod("HeelSpur", CHROME, Vector((x0, -0.06, 0.03)), Vector((x0, -0.11, 0.01)),
        0.015, r2=0.0, verts=6)

# =====================================================================
# ARMS - right: cannon held forward, left: claw
# =====================================================================
for s, side in ((-1, "L"), (1, "R")):
    Sh = Vector((s * 0.25, -0.01, 1.50))
    E = Sh + Vector((s * 0.03, -0.03, -0.27))
    PIVOT["UpperArm_" + side], PARENT["UpperArm_" + side] = Sh, "Torso"
    PIVOT["LowerArm_" + side], PARENT["LowerArm_" + side] = E, "UpperArm_" + side

    segment("UpperArm_" + side)
    prim('sphere', "ShoulderBall", CHROME, Sh, scale=(0.055,) * 3, seg=16, rings=8)
    paul = prim('cube', "Pauldron", GUNMETAL, Sh + Vector((s * 0.015, -0.005, 0.06)),
                rot=(0, s * radians(20), 0), scale=(0.08, 0.085, 0.03))
    bevel(paul, 0.015, 2)
    subsurf(paul, 1)
    light("ShoulderLight", Sh + Vector((s * 0.8, 0.6, 0)).normalized() * 0.052)
    rod("Humerus", CHROME, Sh, E, 0.026, verts=10)
    rod("UpperPiston", GUNMETAL, Sh + Vector((0, 0.04, -0.05)), Sh + Vector((0, 0.04, -0.17)),
        0.015, verts=10)
    rod("UpperPistonRod", CHROME, Sh + Vector((0, 0.04, -0.17)), E + Vector((0, 0.035, 0.02)),
        0.008, verts=8)

    segment("LowerArm_" + side)
    prim('sphere', "ElbowBall", CHROME, E, scale=(0.042,) * 3, seg=14, rings=8)
    light("ElbowLight", E + Vector((s, 0, 0.3)).normalized() * 0.04)
    if s == 1:
        f = Vector((-0.06, 1.0, 0.0)).normalized()     # forearm held level, forward
    else:
        f = Vector((0.08, 0.75, -0.66)).normalized()   # claw arm hangs forward
    UPZ = Vector((0, 0, 1))
    w = f.cross(UPZ).normalized()
    n = w.cross(f).normalized()
    Wr = E + 0.24 * f
    for k in (-1, 1):
        rod("ForearmBone", CHROME, E + 0.02 * f + k * 0.02 * n, Wr + k * 0.016 * n, 0.014, verts=8)
    pa = E + 0.03 * f + s * 0.05 * w
    pb = E + 0.15 * f + s * 0.05 * w
    pc = Wr + s * 0.045 * w
    rod("ForearmPiston", GUNMETAL, pa, pb, 0.018, verts=10)
    rod("ForearmPistonRod", CHROME, pb, pc, 0.009, verts=8)
    rod("PistonBracket", GUNMETAL, E + 0.03 * f, pa, 0.01, verts=6)
    rod("PistonBracket", GUNMETAL, Wr, pc, 0.01, verts=6)
    prim('sphere', "WristBall", GUNMETAL, Wr, scale=(0.03,) * 3, seg=12, rings=6)
    if s == 1:
        c1 = Wr + 0.14 * f
        housing = rod("CannonHousing", GUNMETAL, Wr - 0.02 * f, c1, 0.058, verts=12)
        bevel(housing, 0.012, 2)
        rod("CannonBarrel", CHROME, c1, c1 + 0.36 * f, 0.028, verts=12)
        for k in range(3):
            a = c1 + (0.06 + 0.07 * k) * f
            rod("CoolingRing", GUNMETAL, a, a + 0.02 * f, 0.036, verts=12)
        muzzle = rod("Muzzle", GUNMETAL, c1 + 0.34 * f, c1 + 0.44 * f, 0.042, verts=12)
        bevel(muzzle, 0.006, 1)
        mbore = rod("MuzzleBore", GUNMETAL, c1 + 0.30 * f, c1 + 0.47 * f, 0.02, verts=12, cutter=True)
        cut(muzzle, mbore)
        rod("MuzzleGlow", RED, c1 + 0.358 * f, c1 + 0.366 * f, 0.019, verts=12)
        FIRE_TIP = c1 + 0.45 * f
    else:
        palm = prim('cube', "Palm", GUNMETAL, Wr + 0.05 * f, scale=(0.04, 0.03, 0.045))
        aim(palm, f)
        bevel(palm, 0.01, 2)
        for a in (90, 210, 330):
            rd = cos(radians(a)) * w + sin(radians(a)) * n
            b = Wr + 0.09 * f + 0.03 * rd
            k1 = b + 0.075 * (f + 0.55 * rd).normalized()
            k2 = k1 + 0.065 * (f - 0.10 * rd).normalized()
            tip = k2 + 0.06 * (f - 0.90 * rd).normalized()
            rod("Finger1", CHROME, b, k1, 0.012, verts=8)
            prim('sphere', "Knuckle", GUNMETAL, k1, scale=(0.016,) * 3, seg=8, rings=6)
            rod("Finger2", CHROME, k1, k2, 0.011, verts=8)
            prim('sphere', "Knuckle", GUNMETAL, k2, scale=(0.014,) * 3, seg=8, rings=6)
            rod("Talon", CHROME, k2, tip, 0.014, r2=0.0, verts=6)

# =====================================================================
# BAKE modifiers and transforms, drop cutters
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
for c in CUTTERS:
    bpy.data.objects.remove(c, do_unlink=True)
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

root = bpy.data.objects.new("Robot", None)
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
path = os.environ.get("ROBOT_OUT", path)
bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=False,
                          export_yup=True, export_apply=True)
tris = sum(len(p.vertices) - 2 for j in JOINTS.values() for p in j.data.polygons)
print(f"GroundRobot: {tris} triangles, {len(JOINTS)} joints, height {top:.2f} -> {TARGET_HEIGHT}")
print(f"Exported to {path}")
