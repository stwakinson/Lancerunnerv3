"""
EnemyRobot generator - flying Terminator-style combat robot (Blender 4.x)
Paste into the Scripting tab and press Run. Builds the model, joins it into
one mesh called 'EnemyRobot', adds a 'FirePoint' empty at the cannon tip and
exports enemy_robot.glb. Uses bpy plus the bundled mathutils module only.

Facing: +Y (the glTF exporter turns this into Godot's -Z forward). Up: +Z.
"""
import bpy
import os
from math import radians, sin, cos, pi
from mathutils import Vector, Matrix

# =====================================================================
# SETTINGS  (common tweaks live here)
# =====================================================================
TARGET_LENGTH = 2.4     # metres along Y, thruster tail -> cannon tip
LEAN_DEG      = 30.0    # forward dive lean in degrees
RED_GLOW      = 8.0     # RedGlow emission strength
THRUST_GLOW   = 6.0     # ThrusterGlow emission strength
MAX_TRIS      = 15000   # budget; the mesh is auto-decimated if it goes over
SMOOTH_ANGLE  = 35.0    # smooth-by-angle threshold in degrees
EXPORT_FILE   = "enemy_robot.glb"

LEAN = radians(LEAN_DEG)
# The robot is modelled upright ("body space") and tilted forward by LEAN at
# the end. FWD is the body-space direction that becomes world +Y after the
# tilt, so the arms, cannon and nozzles stay level whatever lean you choose.
FWD  = Vector((0.0, cos(LEAN), sin(LEAN)))
BACK = -FWD

# =====================================================================
# CLEAR SCENE (safe to re-run; removes ALL objects in the file)
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
# MATERIALS (plain Principled BSDF, glTF friendly, no textures)
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
    mat.diffuse_color = (*(emission or base), 1.0)   # viewport solid colour
    return mat

CHROME   = make_material("Chrome",       (0.60, 0.62, 0.65), 1.0, 0.25)
GUNMETAL = make_material("Gunmetal",     (0.12, 0.12, 0.14), 0.9, 0.45)
RED      = make_material("RedGlow",      (0.25, 0.0, 0.0),   0.0, 0.40,
                         (1.0, 0.05, 0.02), RED_GLOW)
THRUST   = make_material("ThrusterGlow", (0.30, 0.08, 0.0),  0.0, 0.40,
                         (1.0, 0.35, 0.05), THRUST_GLOW)

# =====================================================================
# HELPERS
# =====================================================================
PARTS, CUTTERS = [], []
AX = {'X': 0, 'Y': 1, 'Z': 2}

def prim(kind, name, mat, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1),
         verts=16, seg=16, rings=8, r2=0.0, major=16, minor_seg=4, minor=0.1,
         cutter=False):
    """Add a primitive. `scale` = half-extents and is baked into the mesh,
    so bevel widths stay in real units."""
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
        PARTS.append(obj)
    return obj

def aim(obj, direction):
    """Point the object's local +Z along `direction`."""
    q = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized())
    obj.rotation_euler = q.to_euler()

def rod(name, mat, p1, p2, r1, r2=None, verts=12, cutter=False):
    """Cylinder (or cone if r2 is given) from p1 to p2."""
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
    """Scale vertices progressively along one local axis, e.g. taper(o,'Y',X=0.5)."""
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
    return m

def subsurf(obj, levels=1):
    m = obj.modifiers.new("Subsurf", 'SUBSURF')
    m.levels = levels
    m.render_levels = levels
    return m

def cut(target, cutter_obj):
    """Boolean difference; the cut walls take the cutter's material."""
    m = target.modifiers.new("Cut", 'BOOLEAN')
    m.operation = 'DIFFERENCE'
    m.solver = 'EXACT'
    m.object = cutter_obj
    try:
        m.material_mode = 'TRANSFER'
    except (AttributeError, TypeError):
        pass
    return m

def light(name, pos, r=0.014):
    """Small red emissive joint/spine light."""
    return prim('sphere', name, RED, pos, scale=(r, r, r), seg=8, rings=6)

# =====================================================================
# HEAD - chrome skull, sharp jaw, teeth, red eyes
# =====================================================================
HEAD = Vector((0.0, 0.02, 0.95))

skull = prim('sphere', "Skull", CHROME, HEAD, scale=(0.13, 0.16, 0.15), seg=20, rings=12)
taper(skull, 'Y', X=0.72)                                   # narrower face = meaner
for s in (-1, 1):
    sock = prim('sphere', "EyeSocketCut", GUNMETAL, HEAD + Vector((s * 0.048, 0.135, 0.01)),
                scale=(0.038, 0.05, 0.03), seg=12, rings=8, cutter=True)
    cut(skull, sock)
    prim('sphere', "Eye", RED, HEAD + Vector((s * 0.048, 0.118, 0.01)),
         scale=(0.024, 0.02, 0.02), seg=10, rings=6)
    # angry V-shaped brow ridges
    brow = prim('cube', "Brow", CHROME, HEAD + Vector((s * 0.05, 0.135, 0.05)),
                rot=(radians(-15), -s * radians(20), 0), scale=(0.05, 0.022, 0.011))
    bevel(brow, 0.005, 1)
    # cheekbones
    cheek = prim('cube', "Cheek", CHROME, HEAD + Vector((s * 0.075, 0.09, -0.05)),
                 scale=(0.03, 0.04, 0.02))
    bevel(cheek, 0.008, 2)
nose = prim('cube', "NoseCut", GUNMETAL, HEAD + Vector((0, 0.15, -0.035)),
            rot=(0, radians(45), 0), scale=(0.014, 0.05, 0.014), cutter=True)
cut(skull, nose)

# upper jaw block + upper teeth
maxilla = prim('cube', "Maxilla", CHROME, HEAD + Vector((0, 0.095, -0.095)),
               scale=(0.075, 0.06, 0.04))
taper(maxilla, 'Y', X=0.6)
bevel(maxilla, 0.012, 2)
subsurf(maxilla, 1)
for i in range(8):
    x = -0.0385 + i * 0.011
    prim('cone', "ToothUp", CHROME,
         HEAD + Vector((x, 0.145 - 8 * x * x, -0.147)),
         rot=(pi, 0, 0), scale=(0.007, 0.007, 0.017), verts=4)

# lower jaw: V-shaped, slightly open for a snarl
jaw = prim('cube', "Jaw", CHROME, HEAD + Vector((0, 0.05, -0.195)),
           rot=(radians(-8), 0, 0), scale=(0.085, 0.10, 0.03))
taper(jaw, 'Y', X=0.35, Z=0.8)
bevel(jaw, 0.01, 2)
subsurf(jaw, 1)
for i in range(6):
    x = -0.0275 + i * 0.011
    prim('cone', "ToothLow", CHROME,
         HEAD + Vector((x, 0.125 - 10 * x * x, -0.156)),
         scale=(0.007, 0.007, 0.016), verts=4)
for s in (-1, 1):
    hinge = HEAD + Vector((s * 0.066, 0.0, -0.17))
    prim('cyl', "JawHinge", GUNMETAL, hinge, rot=(0, radians(90), 0),
         scale=(0.022, 0.022, 0.012), verts=12)
    rod("JawStrut", CHROME, HEAD + Vector((s * 0.09, 0.0, -0.06)), hinge, 0.011, verts=8)

# neck
rod("Neck", GUNMETAL, (0, -0.02, 0.68), (0, -0.02, 0.85), 0.028, verts=10)
for z in (0.72, 0.76, 0.80):
    prim('cyl', "NeckDisc", CHROME, (0, -0.02, z), scale=(0.042, 0.042, 0.006), verts=12)
for s in (-1, 1):
    rod("NeckPiston", CHROME, (s * 0.045, 0.0, 0.69), (s * 0.04, 0.02, 0.86), 0.009, verts=8)

# =====================================================================
# TORSO - chest armour, ribs, mechanical spine
# =====================================================================
collar = prim('cube', "Collar", GUNMETAL, (0, 0.02, 0.67), scale=(0.20, 0.09, 0.035))
bevel(collar, 0.015, 2)
subsurf(collar, 1)
for s in (-1, 1):
    light("CollarLight", Vector((s * 0.06, 0.125, 0.665)), r=0.012)

for s in (-1, 1):
    pec_loc = Vector((s * 0.09, 0.10, 0.54))
    pec_rot = (radians(10), 0, -s * radians(20))
    pec = prim('cube', "ChestPlate", GUNMETAL, pec_loc, rot=pec_rot,
               scale=(0.085, 0.025, 0.10))
    taper(pec, 'Z', X=1.2)
    bevel(pec, 0.012, 2)
    # three vent slits (one cutter + array) so the ribs show through
    slit = prim('cube', "SlitCut", GUNMETAL, pec_loc + Vector((0, 0, -0.065)),
                rot=pec_rot, scale=(0.06, 0.06, 0.006), cutter=True)
    arr = slit.modifiers.new("Array", 'ARRAY')
    arr.count = 3
    arr.relative_offset_displace = (0.0, 0.0, 3.0)
    cut(pec, slit)

sternum = prim('cube', "Sternum", CHROME, (0, 0.135, 0.40), scale=(0.022, 0.018, 0.15))
bevel(sternum, 0.006, 1)

for i, z in enumerate((0.58, 0.50, 0.42, 0.34, 0.27)):
    R = 0.17 - i * 0.012
    prim('torus', "Rib", CHROME, (0, -0.01, z), rot=(radians(-14), 0, 0),
         scale=(R, R * 0.75, R), major=18, minor_seg=5, minor=0.08)

# spine: vertebrae + dorsal spikes + red lights between them
N_VERT = 8
spine_pts = []
for i in range(N_VERT):
    t = i / (N_VERT - 1)
    z = 0.70 - t * 0.56
    y = -0.12 - 0.025 * sin(pi * t)
    spine_pts.append(Vector((0, y, z)))
    vb = prim('cube', "Vertebra", GUNMETAL, (0, y, z), scale=(0.045, 0.035, 0.024))
    bevel(vb, 0.008, 1)
    rod("SpineSpike", CHROME, (0, y - 0.03, z), (0, y - 0.09, z + 0.03), 0.014, r2=0.0, verts=4)
rod("SpinalCord", GUNMETAL, spine_pts[0], spine_pts[-1], 0.018, verts=10)
for a, b in zip(spine_pts[:-1], spine_pts[1:]):
    mid = (a + b) / 2
    light("SpineLight", mid + Vector((0, -0.028, 0)), r=0.013)

# =====================================================================
# THRUSTERS - lower-body jet pod, 2 glowing nozzles, fins
# =====================================================================
P0 = Vector((0.0, -0.16, -0.02))                               # pod centre
PODUP = Vector((0, 0, 1)).rotation_difference(BACK) @ Vector((0, 1, 0))

# waist narrowing into the pod
rod("Waist", GUNMETAL, (0, -0.03, 0.30), P0 + 0.10 * FWD, 0.10, r2=0.13, verts=16)
belly = prim('cube', "BellyPlate", GUNMETAL, (0, 0.07, 0.20), rot=(radians(20), 0, 0),
             scale=(0.075, 0.02, 0.06))
bevel(belly, 0.01, 2)
light("BellyLight", Vector((0, 0.095, 0.21)), r=0.014)

pod = prim('sphere', "ThrusterPod", GUNMETAL, P0, scale=(0.16, 0.16, 0.30), seg=20, rings=12)
taper(pod, 'Z', X=0.7, Y=0.7)                                 # narrows toward the tail
aim(pod, BACK)
for off, rad in ((-0.08, 0.14), (0.12, 0.117)):
    band = prim('torus', "PodBand", CHROME, P0 + off * BACK, scale=(rad, rad, rad),
                major=20, minor_seg=4, minor=0.1)
    aim(band, BACK)

NOZZLE_EXITS = []
for s in (-1, 1):
    side = Vector((s * 0.085, 0, 0))
    mount = P0 + 0.26 * BACK + side
    exitp = mount + 0.17 * BACK
    NOZZLE_EXITS.append(exitp)
    nacelle = rod("Nacelle", GUNMETAL, P0 + 0.12 * BACK + side, mount, 0.07, verts=16)
    bevel(nacelle, 0.01, 2)
    bell = rod("NozzleBell", GUNMETAL, mount, exitp, 0.06, r2=0.082, verts=16)
    bevel(bell, 0.006, 1)
    bore = rod("NozzleBore", THRUST, mount + 0.04 * BACK, exitp + 0.02 * BACK,
               0.045, r2=0.07, verts=16, cutter=True)
    cut(bell, bore)                                            # bore walls glow
    rod("NozzleCore", THRUST, mount + 0.035 * BACK, mount + 0.11 * BACK,
        0.045, r2=0.005, verts=12)                             # glowing inner cone
    rim = prim('torus', "NozzleRim", GUNMETAL, exitp, scale=(0.08, 0.08, 0.08),
               major=16, minor_seg=4, minor=0.12)
    aim(rim, BACK)

    # swept side fins (wing-like)
    fin = prim('cube', "PodFin", GUNMETAL, scale=(0.12, 0.008, 0.07))
    fin.data.transform(Matrix.Translation(Vector((s * 0.12, 0, 0))))   # root at origin
    for v in fin.data.vertices:
        t = abs(v.co.x) / 0.24
        v.co.z = v.co.z * (1 - 0.6 * t) + 0.10 * t                    # sweep back
    fin.location = P0 + 0.06 * BACK + Vector((s * 0.13, 0, 0))
    aim(fin, BACK)
    bevel(fin, 0.004, 1)

dfin = prim('cube', "DorsalFin", GUNMETAL, scale=(0.008, 0.06, 0.09))
dfin.data.transform(Matrix.Translation(Vector((0, 0.06, 0))))
for v in dfin.data.vertices:
    t = v.co.y / 0.12
    v.co.z = v.co.z * (1 - 0.5 * t) + 0.08 * t
dfin.location = P0 + 0.10 * BACK + 0.11 * PODUP
aim(dfin, BACK)
bevel(dfin, 0.004, 1)

# =====================================================================
# ARMS - shoulders, stabilizer pods, pistons, cannon (R), claw (L)
# =====================================================================
FIRE_TIP = None
UPZ = Vector((0, 0, 1))
for s in (-1, 1):                              # s=+1 right arm (+X), s=-1 left arm
    S = Vector((s * 0.25, 0.0, 0.62))
    u = (FWD + Vector((s * 0.18, 0.0, -0.30))).normalized()   # upper arm direction
    f = (FWD + Vector((-s * 0.10, 0.0, 0.03))).normalized()   # forearm direction
    E = S + 0.25 * u
    W = E + 0.24 * f
    wu = u.cross(UPZ).normalized(); nu = wu.cross(u).normalized()
    w = f.cross(UPZ).normalized();  n = w.cross(f).normalized()

    # shoulder ball joint, armour, clavicle, light
    prim('sphere', "ShoulderBall", CHROME, S, scale=(0.055,) * 3, seg=16, rings=8)
    light("ShoulderLight", S + Vector((s * 0.8, 0.6, 0)).normalized() * 0.052)
    paul = prim('cube', "Pauldron", GUNMETAL, S + Vector((s * 0.015, -0.005, 0.06)),
                rot=(0, s * radians(20), 0), scale=(0.08, 0.085, 0.03))
    bevel(paul, 0.015, 2)
    subsurf(paul, 1)
    rod("Clavicle", CHROME, (s * 0.15, 0.02, 0.66), S, 0.02, verts=10)

    # stabilizer thruster pod on the shoulder
    sp = S + Vector((s * 0.03, -0.02, 0.11))
    body = rod("StabPod", GUNMETAL, sp + 0.07 * FWD, sp + 0.05 * BACK, 0.034, verts=12)
    bevel(body, 0.006, 1)
    rod("StabNose", CHROME, sp + 0.07 * FWD, sp + 0.12 * FWD, 0.034, r2=0.008, verts=12)
    rod("StabNozzle", GUNMETAL, sp + 0.05 * BACK, sp + 0.09 * BACK, 0.026, r2=0.034, verts=12)
    rod("StabGlow", THRUST, sp + 0.088 * BACK, sp + 0.096 * BACK, 0.029, verts=12)

    # upper arm bone + hydraulic piston underneath
    rod("UpperArm", CHROME, S, E, 0.026, verts=10)
    rod("UpperPiston", GUNMETAL, S + 0.05 * u - 0.04 * nu, S + 0.16 * u - 0.04 * nu, 0.015, verts=10)
    rod("UpperPistonRod", CHROME, S + 0.16 * u - 0.04 * nu, E - 0.03 * nu, 0.008, verts=8)

    # elbow ball joint + light
    prim('sphere', "ElbowBall", CHROME, E, scale=(0.042,) * 3, seg=14, rings=8)
    light("ElbowLight", E + Vector((s, 0, 0.4)).normalized() * 0.04)

    # forearm: two skeletal bones + piston beside it
    for k in (-1, 1):
        rod("ForearmBone", CHROME, E + 0.02 * f + k * 0.02 * n, W + k * 0.016 * n, 0.014, verts=8)
    pa = E + 0.03 * f + s * 0.05 * w
    pb = E + 0.15 * f + s * 0.05 * w
    pc = W + s * 0.045 * w
    rod("ForearmPiston", GUNMETAL, pa, pb, 0.018, verts=10)
    rod("ForearmPistonRod", CHROME, pb, pc, 0.009, verts=8)
    rod("PistonBracket", GUNMETAL, E + 0.03 * f, pa, 0.01, verts=6)
    rod("PistonBracket", GUNMETAL, W, pc, 0.01, verts=6)
    prim('sphere', "WristBall", GUNMETAL, W, scale=(0.03,) * 3, seg=12, rings=6)

    if s == 1:
        # ---- RIGHT ARM: long cannon pointing forward ----
        c1 = W + 0.14 * f
        housing = rod("CannonHousing", GUNMETAL, W - 0.02 * f, c1, 0.058, verts=12)
        bevel(housing, 0.012, 2)
        rod("CannonBarrel", CHROME, c1, c1 + 0.36 * f, 0.028, verts=12)
        for k in range(3):
            a = c1 + (0.06 + 0.07 * k) * f
            rod("CoolingRing", GUNMETAL, a, a + 0.02 * f, 0.036, verts=12)
        muzzle = rod("Muzzle", GUNMETAL, c1 + 0.34 * f, c1 + 0.44 * f, 0.042, verts=12)
        bevel(muzzle, 0.006, 1)
        mbore = rod("MuzzleBore", GUNMETAL, c1 + 0.30 * f, c1 + 0.47 * f, 0.02,
                    verts=12, cutter=True)
        cut(muzzle, mbore)
        rod("MuzzleGlow", RED, c1 + 0.358 * f, c1 + 0.366 * f, 0.019, verts=12)
        FIRE_TIP = c1 + 0.44 * f + 0.01 * f
    else:
        # ---- LEFT ARM: 3-fingered claw ----
        palm = prim('cube', "Palm", GUNMETAL, W + 0.05 * f, scale=(0.04, 0.03, 0.045))
        aim(palm, f)
        bevel(palm, 0.01, 2)
        for a in (90, 210, 330):
            rd = cos(radians(a)) * w + sin(radians(a)) * n
            b = W + 0.09 * f + 0.03 * rd
            k1 = b + 0.075 * (f + 0.55 * rd).normalized()
            k2 = k1 + 0.065 * (f - 0.10 * rd).normalized()
            tip = k2 + 0.06 * (f - 0.90 * rd).normalized()
            rod("Finger1", CHROME, b, k1, 0.012, verts=8)
            prim('sphere', "Knuckle", GUNMETAL, k1, scale=(0.016,) * 3, seg=8, rings=6)
            rod("Finger2", CHROME, k1, k2, 0.011, verts=8)
            prim('sphere', "Knuckle", GUNMETAL, k2, scale=(0.014,) * 3, seg=8, rings=6)
            rod("Talon", CHROME, k2, tip, 0.014, r2=0.0, verts=6)

# =====================================================================
# APPLY MODIFIERS (bake evaluated meshes), then delete boolean cutters
# =====================================================================
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
baked = [(o, bpy.data.meshes.new_from_object(o.evaluated_get(dg))) for o in PARTS if o.modifiers]
for obj, new_me in baked:
    old = obj.data
    mats = list(old.materials)
    obj.modifiers.clear()
    obj.data = new_me
    if len(new_me.materials) == 0:          # safety: keep materials
        for m in mats:
            new_me.materials.append(m)
    bpy.data.meshes.remove(old)
for c in CUTTERS:
    bpy.data.objects.remove(c, do_unlink=True)

# bake every object's transform into its mesh
bpy.context.view_layer.update()
for obj in PARTS:
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)

# =====================================================================
# JOIN into one mesh 'EnemyRobot' (per-face materials are kept)
# =====================================================================
bpy.ops.object.select_all(action='DESELECT')
for obj in PARTS:
    obj.select_set(True)
bpy.context.view_layer.objects.active = PARTS[0]
bpy.ops.object.join()
robot = bpy.context.view_layer.objects.active
robot.name = "EnemyRobot"
robot.data.name = "EnemyRobot"
me = robot.data

# lean forward (head/cannon toward +Y, nozzles toward -Y)
lean_m = Matrix.Rotation(-LEAN, 4, 'X')
me.transform(lean_m)
fire = lean_m @ FIRE_TIP
nozzles = [lean_m @ p for p in NOZZLE_EXITS]

# centre the bounding box on the world origin
cos_ = [v.co for v in me.vertices]
mn = Vector((min(c.x for c in cos_), min(c.y for c in cos_), min(c.z for c in cos_)))
mx = Vector((max(c.x for c in cos_), max(c.y for c in cos_), max(c.z for c in cos_)))
center = (mn + mx) / 2
me.transform(Matrix.Translation(-center))
fire = fire - center
nozzles = [p - center for p in nozzles]

# scale so tail -> cannon tip (Y extent) equals TARGET_LENGTH
k = TARGET_LENGTH / (mx.y - mn.y)
me.transform(Matrix.Scale(k, 4))
fire = fire * k
nozzles = [p * k for p in nozzles]
me.update()

# triangle budget check (decimate only if needed)
def tri_count(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)

tris = tri_count(me)
if tris > MAX_TRIS:
    dec = robot.modifiers.new("Decimate", 'DECIMATE')
    dec.ratio = MAX_TRIS * 0.95 / tris
    bpy.ops.object.modifier_apply(modifier=dec.name)
    tris = tri_count(me)

# smooth shading with sharp hard-surface edges
bpy.ops.object.select_all(action='DESELECT')
robot.select_set(True)
bpy.context.view_layer.objects.active = robot
try:
    bpy.ops.object.shade_smooth_by_angle(angle=radians(SMOOTH_ANGLE))   # Blender 4.1+
except Exception:
    bpy.ops.object.shade_smooth()                                         # Blender 4.0
    try:
        me.use_auto_smooth = True
        me.auto_smooth_angle = radians(SMOOTH_ANGLE)
    except AttributeError:
        pass

# FirePoint empty at the cannon tip (child of the robot, identity rotation,
# so its -Z in Godot is the same forward as the robot)
fp = bpy.data.objects.new("FirePoint", None)
fp.empty_display_type = 'ARROWS'
fp.empty_display_size = 0.1
robot.users_collection[0].objects.link(fp)
fp.location = fire
fp.parent = robot

# Thruster empties at the nozzle exits (the game spawns exhaust there)
thrusters = []
for i, p in enumerate(nozzles):
    th = bpy.data.objects.new(f"Thruster_{'LR'[i]}", None)
    th.empty_display_type = 'ARROWS'
    th.empty_display_size = 0.1
    robot.users_collection[0].objects.link(th)
    th.location = p
    th.parent = robot
    thrusters.append(th)

# =====================================================================
# EXPORT (GLB, +Y up, modifiers applied; empties export as glTF nodes)
# =====================================================================
if bpy.data.is_saved:
    path = bpy.path.abspath("//" + EXPORT_FILE)
else:
    path = os.path.join(os.path.expanduser("~"), EXPORT_FILE)
path = os.environ.get("ENEMY_ROBOT_OUT", path)   # optional override

bpy.ops.object.select_all(action='DESELECT')
robot.select_set(True)
fp.select_set(True)
for th in thrusters:
    th.select_set(True)
bpy.context.view_layer.objects.active = robot
bpy.ops.export_scene.gltf(
    filepath=path,
    export_format='GLB',
    use_selection=True,      # EnemyRobot + FirePoint + Thruster_L/R
    export_yup=True,         # Blender +Y forward -> glTF -Z
    export_apply=True,
)
print(f"EnemyRobot: {tris} triangles, {len(me.materials)} materials")
print(f"FirePoint at {tuple(round(c, 3) for c in fp.location)}")
print(f"Exported to {path}")
