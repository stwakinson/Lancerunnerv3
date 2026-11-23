#!/usr/bin/env python3
"""Deterministic Pilgrim source + GLB builder. Run with Blender 4.3+ --background --python.
All textures are authored procedurally here; no external image/model downloads.
Blender front is +Y; glTF/Godot front is -Z. One UV/material atlas for the whole ship.
"""
import bpy, math, random, json, os
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/models/pilgrim'; TEX=ROOT/'assets/textures/pilgrim'
OUT.mkdir(parents=True,exist_ok=True); TEX.mkdir(parents=True,exist_ok=True)
SOURCE=OUT/'source'; SOURCE.mkdir(exist_ok=True); (SOURCE/'.gdignore').write_text('')
# Blender has no Pillow dependency. Rasterise intentionally chunky pixel textures.
S=512; rng=random.Random(1415)
albedo=[(0.20,0.18,0.19,1.0)]*(S*S); emit=[(0,0,0,1)]*(S*S)
def rgb(h): return tuple(int(h[i:i+2],16)/255 for i in (0,2,4))+(1,)
def rect(x,y,w,h,c,e=None):
 c=rgb(c) if isinstance(c,str) else c
 for yy in range(max(0,int(y)),min(S,int(y+h))):
  for xx in range(max(0,int(x)),min(S,int(x+w))):
   at=(S-1-yy)*S+xx; albedo[at]=c
   emit[at]=rgb(e) if e else (0,0,0,1)
def poly(points,c,e=None):
 miny=int(min(y for x,y in points)); maxy=int(max(y for x,y in points))
 for y in range(miny,maxy+1):
  hits=[]
  for i,(x1,y1) in enumerate(points):
   x2,y2=points[(i+1)%len(points)]
   if (y1<=y<y2) or (y2<=y<y1): hits.append(x1+(y-y1)*(x2-x1)/(y2-y1))
  hits.sort()
  for a,b in zip(hits[0::2],hits[1::2]): rect(math.ceil(a),y,math.floor(b)-math.ceil(a)+1,1,c,e)
def noise_tile(box,palette,bw,bh):
 x0,y0,x1,y1=box; rect(x0,y0,x1-x0,y1-y0,palette[0])
 for row,y in enumerate(range(y0,y1,bh)):
  for x in range(x0-bw,x1,bw):
   at=x+(bw//2 if row%2 else 0)
   a=max(x0,at); b=min(x1,at+bw-1)
   if b<=a: continue
   col=rng.choice(palette); rect(a,y,b-a,min(bh-1,y1-y),col)
   for k in range(3):
    px=rng.randrange(int(a),int(b)); py=rng.randrange(y,min(y+bh-1,y1))
    base=rgb(col); d=rng.choice([-.025,.025,.045])
    rect(px,py,rng.choice([2,3,4]),2,tuple(max(0,min(1,v+d)) for v in base[:3])+(1,))
def lancet(x,y,w,h):
 # Concentric stepped arches, leaded panes and pixels of warm amber.
 pts=[(x,y+h),(x,y+h*.35),(x+w*.2,y+h*.14),(x+w*.5,y),(x+w*.8,y+h*.14),(x+w,y+h*.35),(x+w,y+h)]
 poly(pts,'5d5148'); poly([(x+3,y+h-3),(x+3,y+h*.38),(x+w*.5,y+6),(x+w-3,y+h*.38),(x+w-3,y+h-3)],'a58b5a')
 poly([(x+6,y+h-6),(x+6,y+h*.42),(x+w*.5,y+11),(x+w-6,y+h*.42),(x+w-6,y+h-6)],'f6b54d','eea332')
 for dy in range(22,int(h-8),12): rect(x+7,y+dy,w-14,2,'775237')
 rect(x+w//2-1,y+13,3,h-19,'735236')
 for a,b in [(9,28),(w-14,40),(9,h-12)]: rect(x+a,y+b,4,4,'ffdd7e','ffd075')
def fleur(cx,cy,scale=1):
 pts=[(0,-13),(4,-7),(2,-2),(6,-6),(10,-5),(11,-1),(8,2),(4,1),(3,5),(7,6),(7,9),(2,9),(0,13),(-2,9),(-7,9),(-7,6),(-3,5),(-4,1),(-8,2),(-11,-1),(-10,-5),(-6,-6),(-2,-2),(-4,-7)]
 poly([(cx+x*scale,cy+y*scale) for x,y in pts],'dec493')
PATCH={
 'side':(0,0,384,128),'roof':(0,128,384,320),'cap':(384,0,512,128),
 'bronze':(384,128,448,256),'iron':(448,128,512,256),
 'window':(0,320,64,448),'wall':(64,320,128,448),'dome':(128,320,256,448),
 'door':(256,320,384,448),'engine':(384,320,512,448),
 'collar':(0,448,128,512),'lamp':(128,448,192,512),'base':(192,448,384,512),
 'pod':(384,256,512,320)
}
noise_tile(PATCH['side'],['b4a48c','d3c2a3','c6b698','dbc9a7','bfb198','caba9d'],24,14)
rect(0,116,384,12,'665b50'); rect(0,112,384,4,'8a7353')
for x in [35,105,245,315]: lancet(x,19,27,68)
# Burgundy painted hanging heraldry, pixel art only (no geometry/transparent card).
rect(171,0,43,104,'722d38'); poly([(171,104),(192,122),(214,104)],'722d38'); rect(174,0,3,101,'a46653'); rect(208,0,3,101,'4e2730'); fleur(192,49,1.1)
for x in [10,85,160,235,310,378]:
 rect(x,0,3,112,'958369'); rect(x+3,0,2,112,'e5cfaa')
noise_tile(PATCH['roof'],['2c333f','343945','3c3d48','41434e','2f3743'],20,12)
noise_tile(PATCH['cap'],['c2b297','decbab','d1bea1','b3a58f'],19,12)
noise_tile(PATCH['bronze'],['8a673d','aa8250','bc965b','957044'],12,16)
rect(384,128,3,128,'e1bd76'); rect(444,128,4,128,'5f4939')
for y in range(135,250,24): rect(407,y,7,6,'4f463c'); rect(408,y,4,3,'d3b16b')
noise_tile(PATCH['iron'],['343b45','444953','4e5057','393c47'],16,18)
noise_tile(PATCH['wall'],['c7b496','d6c2a0','bca989'],16,14)
noise_tile(PATCH['window'],['bdab8f','d4c09c','c7b899'],16,14); lancet(12,336,40,91)
noise_tile(PATCH['dome'],['434750','54515a','5c5660','414652'],18,12)
rect(128,320,5,128,'b78e50'); rect(251,320,5,128,'98703c')
noise_tile(PATCH['door'],['262d36','343943','3a3f49','29313a'],16,21)
for x in [265,294,323,352,376]: rect(x,320,3,128,'141e28')
rect(256,382,128,4,'725d42')
noise_tile(PATCH['engine'],['103a4b','124956','16637a','1c7e92'],8,8)
for y in range(326,444,10):
 for x in range(390,508,10): rect(x,y,7,7,rng.choice(['39c9de','65e5e8','a3f5eb']),rng.choice(['22b5d0','4bd9dd','71e8e0']))
noise_tile(PATCH['collar'],['927549','b89960','a78a57','c0a16d'],16,13)
rect(0,448,128,5,'e0c28a'); rect(0,507,128,5,'5c4c3b'); rect(52,463,24,32,'332f31'); rect(56,468,16,22,'f9c463','efad39')
rect(128,448,64,64,'744f32'); rect(134,454,52,52,'ffc765','f3ab3d'); rect(140,461,40,36,'ffe393','ffd371')
noise_tile(PATCH['base'],['514c49','62594e','776b57','4b4947'],24,16)
noise_tile(PATCH['pod'],['343b46','4b4c52','3b414a','55545a'],20,12)
rect(431,256,16,64,'7e3740'); rect(428,256,3,64,'b79766'); rect(448,256,3,64,'b79766')
def save_image(name,pixels):
 img=bpy.data.images.new(name,width=S,height=S,alpha=True)
 img.pixels.foreach_set([v for pixel in pixels for v in pixel]); img.filepath_raw=str(TEX/(name+'.png')); img.file_format='PNG'; img.save(); return img
base_img=save_image('pilgrim_albedo',albedo); em_img=save_image('pilgrim_emission',emit)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
mat=bpy.data.materials.new('Pilgrim_Atlas'); mat.use_nodes=True; mat.use_backface_culling=True
bsdf=mat.node_tree.nodes.get('Principled BSDF'); bsdf.inputs['Roughness'].default_value=.82; bsdf.inputs['Metallic'].default_value=.18
for image,socket in [(base_img,'Base Color'),(em_img,'Emission Color')]:
 node=mat.node_tree.nodes.new('ShaderNodeTexImage'); node.image=image; node.interpolation='Closest'; mat.node_tree.links.new(node.outputs['Color'],bsdf.inputs[socket])
bsdf.inputs['Emission Strength'].default_value=1.2
parts=[]
def uv(patch,u,v):
 x0,y0,x1,y1=PATCH[patch]; return ((x0+1+(x1-x0-2)*u)/S,1-(y0+1+(y1-y0-2)*v)/S)
def mesh_obj(name,verts,faces,uvs):
 mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update(); layer=mesh.uv_layers.new(name='AtlasUV')
 for face,coords in zip(mesh.polygons,uvs):
  for li,coord in zip(face.loop_indices,coords): layer.data[li].uv=coord
 obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj); obj.data.materials.append(mat)
 for face in mesh.polygons: face.use_smooth=False
 parts.append(obj); return obj
Q=[(0,1),(0,0),(1,0),(1,1)]
def box(name,loc,size,patch='iron',open_back=False):
 x,y,z=loc; a,b,c=[v/2 for v in size]
 verts=[(x+dx*a,y+dy*b,z+dz*c) for dx,dy,dz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)]
 if open_back: faces.pop(2)
 return mesh_obj(name,verts,faces,[[uv(patch,*q) for q in Q] for _ in faces])
PROFILE=[(-3.2,-2.2),(3.2,-2.2),(4.5,-.8),(4.5,1.3),(3.9,2.8),(2.25,3.8),(0,4.05),(-2.25,3.8),(-3.9,2.8),(-4.5,1.3),(-4.5,-.8)]
def hull():
 n=len(PROFILE); verts=[(x,y,z) for y in [-8,9] for x,z in PROFILE]; faces=[]; coords=[]
 for i in range(n):
  j=(i+1)%n; faces.append((i,i+n,j+n,j))
  patch='roof' if i in range(3,9) else ('side' if i in [2,9] else 'base')
  if patch=='roof':
   # Roof atlas follows the barrel, keeping slate pixels consistent across facets.
   v0=(i-3)/6; v1=(i-2)/6
   coords.append([uv(patch,0,v0),uv(patch,1,v0),uv(patch,1,v1),uv(patch,0,v1)])
  elif patch=='side': coords.append([uv(patch,(verts[k][1]+8)/17,1-(verts[k][2]+.8)/2.1) for k in faces[-1]])
  else: coords.append([uv(patch,*q) for q in Q])
 faces.extend([tuple(range(n)),tuple(reversed(range(n,2*n)))])
 for face in faces[-2:]: coords.append([uv('cap',(verts[i][0]+4.6)/9.2,1-(verts[i][2]+2.3)/6.5) for i in face])
 return mesh_obj('CargoHull_Vault',verts,faces,coords)
hull()
def rib(y,index):
 n=len(PROFILE); verts=[]
 for offset in [0,.14]:
  for at in [y-.17,y+.17]:
   verts.extend([(x*(1+offset/4.5),at,z+(.10 if z>1 else -.05 if z<0 else 0)*offset/.14) for x,z in PROFILE])
 faces=[]
 for i in range(n):
  j=(i+1)%n
  faces.extend([(2*n+i,3*n+i,3*n+j,2*n+j),(i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)])
 return mesh_obj('BronzeFrame_%02d'%index,verts,faces,[[uv('bronze',*q) for q in Q] for _ in faces])
for i,y in enumerate([-7.6,-4.0,-1.3,2.4,5.8,8.55]): rib(y,i)
box('Keel',(0,0,-2.37),(6.3,15,.35),'base')
# Hollow bow collar, axis +Y. Visible front annulus, outer and recessed inner walls.
def collar(name,cx,cy,cz,outer,inner,depth,n=12,back=False):
 verts=[]
 for y,r in [(cy,outer),(cy-depth,outer),(cy,inner),(cy-depth,inner)]:
  verts.extend([(cx+math.sin(i*math.tau/n)*r,y,cz+math.cos(i*math.tau/n)*r) for i in range(n)])
 faces=[]; coords=[]
 for i in range(n):
  j=(i+1)%n
  for face,patch in [((i,j,2*n+j,2*n+i),'collar' if not back else 'iron'),((i,n+i,n+j,j),'bronze' if not back else 'iron'),((2*n+i,2*n+j,3*n+j,3*n+i),'door')]:
   faces.append(face); coords.append([uv(patch,*q) for q in Q])
 obj=mesh_obj(name,verts,faces,coords)
 if back: # Mirror the assembly to face aft.
  for v in obj.data.vertices: v.co.y=2*cy-v.co.y
  for poly_ in obj.data.polygons: poly_.flip()
 return obj
collar('Bow_DockingCollar',0,10.0,.4,3.05,2.16,.8,12)
def disk(name,cx,cy,cz,r,n,patch,normal_front=True):
 verts=[(cx+math.sin(i*math.tau/n)*r,cy,cz+math.cos(i*math.tau/n)*r) for i in range(n)]
 face=tuple(range(n)) if normal_front else tuple(reversed(range(n)))
 return mesh_obj(name,verts,[face],[[uv(patch,.5+(verts[i][0]-cx)/r/2,.5-(verts[i][2]-cz)/r/2) for i in face]])
disk('CargoDoor_Recess',0,9.14,.4,2.15,12,'door')
box('Bow_IdentityPanel',(0,9.12,3.25),(2.3,.18,.65),'bronze')
# Eight-sided elevated cockpit and its restrained faceted slate dome.
def revolve(name,rings,cy,n,patches,cap=True):
 verts=[(math.sin(i*math.tau/n)*r,cy+math.cos(i*math.tau/n)*r,z) for r,z in rings for i in range(n)]; faces=[]; coords=[]
 for k in range(len(rings)-1):
  for i in range(n):
   j=(i+1)%n; faces.append((k*n+i,(k+1)*n+i,(k+1)*n+j,k*n+j))
   patch=patches[k] if isinstance(patches[k],str) else patches[k][i]
   coords.append([uv(patch,0,1),uv(patch,0,0),uv(patch,1,0),uv(patch,1,1)])
 if cap:
  face=tuple(reversed(range((len(rings)-1)*n,len(rings)*n)));faces.append(face)
  coords.append([uv('dome',.5+verts[i][0]/(rings[-1][0]*2),.5+(verts[i][1]-cy)/(rings[-1][0]*2)) for i in face])
 return mesh_obj(name,verts,faces,coords)
revolve('Cupola_PaintedWindows',[(2.15,3.65),(2.15,5.4)],-4.5,8,[['window','window','window','wall','wall','window','window','window']],False)
revolve('Cupola_LowerPlinth',[(2.4,3.7),(2.4,3.96)],-4.5,8,['bronze'],False)
revolve('Cupola_Roof',[(2.42,5.35),(1.55,6.65),(.52,7.0)],-4.5,8,['dome','dome'])
revolve('Cupola_Eaves',[(2.45,5.27),(2.45,5.43)],-4.5,8,['bronze'],False)
for side in [-1,1]:
 x=side*2.22
 box('EnginePod_'+str(side),(x,-9.4,.35),(3.7,3.6,3.9),'pod',True)
 box('EngineClamp_'+str(side),(x,-8.5,.35),(3.85,.32,4.05),'bronze')
 collar('Engine_Nozzle_'+str(side),x,-11.25,.35,1.6,1.18,.35,8,True)
 # Open stern panel: the recessed emitter must not be hidden by a solid box face.
 outer=[(0,1.95),(1.85,1.95),(1.85,0),(1.85,-1.95),(0,-1.95),(-1.85,-1.95),(-1.85,0),(-1.85,1.95)]
 vertices=[(x+px,-11.2,.35+pz) for px,pz in outer]+[(x+math.sin(i*math.tau/8)*1.18,-11.2,.35+math.cos(i*math.tau/8)*1.18) for i in range(8)]
 faces=[(i,8+i,8+(i+1)%8,(i+1)%8) for i in range(8)]
 mesh_obj('Engine_Backplate_'+str(side),vertices,faces,[[uv('iron',(vertices[k][0]-x+1.85)/3.7,1-(vertices[k][2]-.35+1.95)/3.9) for k in face] for face in faces])
 disk('Engine_Emitter_'+str(side),x,-11.0,.35,1.17,8,'engine',False)
# Merge normals consistently on closed components; preserve deliberately open roof/collars.
import bmesh
for obj in parts:
 bm=bmesh.new(); bm.from_mesh(obj.data); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(obj.data); bm.free()
 if obj.name.startswith('Engine_Emitter'):
  for face in obj.data.polygons:
   if face.normal.y > 0: face.flip()
  obj.data.update()
# Produce one draw surface/material per exported LOD. Keep editable source pieces in .blend.
bpy.ops.object.select_all(action='DESELECT')
for obj in parts: obj.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.object.duplicate(); bpy.ops.object.join(); merged=bpy.context.object; merged.name='Pilgrim_LOD0'
# Slot consolidation keeps the export at one material surface.
merged.data.materials.clear(); merged.data.materials.append(mat)
for face in merged.data.polygons: face.material_index=0
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
def triangles(obj): return sum(len(p.vertices)-2 for p in obj.data.polygons)
main_tri=triangles(merged)
bpy.context.view_layer.update(); dimensions=[round(merged.dimensions.x,3),round(merged.dimensions.z,3),round(merged.dimensions.y,3)]
markers=[]
for name,loc in [('Engine_Port',(-2.22,-11.6,.35)),('Engine_Starboard',(2.22,-11.6,.35)),('Docking_Collar',(0,10.05,.4)),('Cockpit',(0,-4.5,4.7))]:
 marker=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(marker); marker.location=loc; marker.empty_display_size=.3; markers.append(marker); marker.select_set(True)
merged['triangle_budget']=main_tri; merged['front_axis']='Godot -Z'; merged['texture_atlas']='512x512; nearest; albedo + emission'
def export(path,obj):
 bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
 for marker in markers: marker.select_set(True)
 bpy.context.view_layer.objects.active=obj
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_materials='EXPORT',export_extras=True,export_yup=True,export_cameras=False,export_lights=False)
export(OUT/'pilgrim.glb',merged)
lod=merged.copy();lod.data=merged.data.copy();bpy.context.collection.objects.link(lod);lod.name='Pilgrim_LOD1'
mod=lod.modifiers.new('Distance_Simplification','DECIMATE');mod.ratio=.42;mod.use_collapse_triangulate=True
bpy.context.view_layer.objects.active=lod;bpy.ops.object.modifier_apply(modifier=mod.name)
lod_tri=triangles(lod);export(OUT/'pilgrim_lod1.glb',lod)
bpy.data.objects.remove(merged,do_unlink=True);bpy.data.objects.remove(lod,do_unlink=True)
# An editable source scene: asset pieces + named mounts, packed textures, studio camera.
for image in [base_img,em_img]: image.pack()
world=bpy.data.worlds.new('Studio');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.055,.07,.11,1);world.node_tree.nodes['Background'].inputs[1].default_value=.45;bpy.context.scene.world=world
for name,location,power,size in [('Key',(-12,12,20),2200,10),('Fill',(12,6,8),1100,8),('Rim',(0,-16,13),1900,7)]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj);obj.location=location;obj.rotation_euler=(Vector((0,0,1))-obj.location).to_track_quat('-Z','Y').to_euler()
camdata=bpy.data.cameras.new('Asset_Camera');cam=bpy.data.objects.new('Asset_Camera',camdata);bpy.context.collection.objects.link(cam);cam.location=(27,34,23);cam.rotation_euler=(Vector((0,0,1.4))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=31;bpy.context.scene.camera=cam
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
bpy.ops.object.select_all(action='DESELECT')
for obj in parts: obj.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D': area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'pilgrim_source.blend'))
manifest={'name':'Pilgrim Light Trader','lod0_triangles':main_tri,'lod1_triangles':lod_tri,'materials_per_lod':1,'atlas_size':[512,512],'front_axis':'-Z (Godot/glTF)','dimensions_godot':dimensions,'source':'tools/assets/build_pilgrim.py','textures':['pilgrim_albedo.png','pilgrim_emission.png']}
(OUT/'pilgrim_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('PILGRIM BUILD',json.dumps(manifest))
