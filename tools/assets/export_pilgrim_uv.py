#!/usr/bin/env python3
"""Export the real GLB UV layout and a labelled painting reference. Requires Pillow."""
import json,struct,html
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'docs/pilgrim-model'; OUT.mkdir(parents=True,exist_ok=True)
raw=(ROOT/'assets/models/pilgrim/pilgrim.glb').read_bytes(); length,kind=struct.unpack_from('<II',raw,12)
gltf=json.loads(raw[20:20+length]); binary_at=20+length; binlen,bintype=struct.unpack_from('<II',raw,binary_at); blob=raw[binary_at+8:binary_at+8+binlen]
def accessor(index):
 a=gltf['accessors'][index]; v=gltf['bufferViews'][a['bufferView']]; n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]; typ={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]; fmt='<'+typ*n; size=struct.calcsize(fmt); stride=v.get('byteStride',size); offset=v.get('byteOffset',0)+a.get('byteOffset',0)
 return [struct.unpack_from(fmt,blob,offset+i*stride) for i in range(a['count'])]
primitive=gltf['meshes'][0]['primitives'][0]; uv=accessor(primitive['attributes']['TEXCOORD_0']); indices=[x[0] for x in accessor(primitive['indices'])]; edges=set()
for i in range(0,len(indices),3):
 triangle=indices[i:i+3]
 for a,b in zip(triangle,triangle[1:]+triangle[:1]):
  p=tuple(round(v*512,3) for v in uv[a]); q=tuple(round(v*512,3) for v in uv[b]); edges.add(tuple(sorted([p,q])))
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">','<title>Pilgrim actual UV layout, top-left texture origin</title>','<g fill="none" stroke="#ffb84f" stroke-width="0.45" opacity="0.8">']
for (x1,y1),(x2,y2) in sorted(edges): svg.append(f'<path d="M{x1},{y1} L{x2},{y2}"/>')
svg+=['</g>','</svg>']; (OUT/'pilgrim_uv_layout.svg').write_text('\n'.join(svg))
# Transparent raster overlay can be placed directly above the albedo in a paint tool.
wire=Image.new('RGBA',(512,512)); wd=ImageDraw.Draw(wire)
for p,q in edges: wd.line([p,q],fill=(255,184,79,170),width=1)
wire.save(OUT/'pilgrim_uv_overlay.png')
albedo=Image.open(ROOT/'assets/textures/pilgrim/pilgrim_albedo.png').convert('RGB'); emission=Image.open(ROOT/'assets/textures/pilgrim/pilgrim_emission.png').convert('RGB')
font_path='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
def font(n): return ImageFont.truetype(font_path,n)
canvas=Image.new('RGB',(1500,1120),'#101b2b'); draw=ImageDraw.Draw(canvas)
draw.text((40,26),'PILGRIM / UV TEXTURE SHEET',font=font(34),fill='#ead3a7')
draw.text((42,78),'Actual model atlas  |  512 x 512  |  nearest sampling  |  repeated parts share UV regions',font=font(17),fill='#b3c6d3')
canvas.paste(albedo.resize((768,768),Image.Resampling.NEAREST),(40,128))
draw.rectangle((39,127,809,897),outline='#c4a475',width=2)
legend=[('SIDE', (0,0,384,128),'Cargo sides: stone, windows and heraldry'),('CAP',(384,0,512,128),'Front and rear hull bulkheads'),('ROOF',(0,128,384,320),'Faceted slate barrel roof'),('BRONZE',(384,128,448,256),'Reusable structural ribs and trim'),('IRON',(448,128,512,256),'Dark housing and recessed metal'),('PODS',(384,256,512,320),'Stern engine cases'),('WINDOW',(0,320,64,448),'Cupola lancet window'),('WALL',(64,320,128,448),'Blank cupola wall'),('DOME',(128,320,256,448),'Cupola roof and painted edging'),('DOOR',(256,320,384,448),'Recessed docking hatch'),('EXHAUST',(384,320,512,448),'Cyan emissive engine faces'),('COLLAR',(0,448,128,512),'Docking collar, trim and marker lamps'),('LAMP',(128,448,192,512),'Reusable amber emissive panel'),('BASE',(192,448,384,512),'Underside and keel')]
for i,(name,box,desc) in enumerate(legend):
 y=130+i*52; x=850
 crop=albedo.crop(box); crop.thumbnail((44,40),Image.Resampling.NEAREST); canvas.paste(crop,(x,y))
 draw.text((x+58,y),f'{i+1:02d}  {name}',font=font(16),fill='#ecd5a9'); draw.text((x+58,y+23),desc,font=font(13),fill='#b4c3d0')
 x0,y0,x1,y1=box; b=(40+x0*1.5,128+y0*1.5,40+x1*1.5,128+y1*1.5);draw.rectangle(b,outline='#d5a85c',width=1)
 draw.rectangle((b[0]+2,b[1]+2,b[0]+31,b[1]+25),fill='#122238');draw.text((b[0]+5,b[1]+4),f'{i+1:02d}',font=font(14),fill='#fff0ca')
canvas.paste(emission.resize((176,176),Image.Resampling.NEAREST),(40,920))
draw.text((239,932),'EMISSION MAP',font=font(21),fill='#ecd5a9')
draw.text((239,970),'Black = no glow. Amber = windows/lamps. Cyan = engines.',font=font(16),fill='#b4c3d0')
draw.text((239,1006),'Use the clean PNG as paintable albedo; labels are only on this guide.',font=font(16),fill='#b4c3d0')
draw.text((239,1041),'UV overlay and SVG are exported from the actual 812-triangle GLB.',font=font(16),fill='#b4c3d0')
canvas.save(OUT/'pilgrim_texture_guide.png')
print('Exported',len(edges),'unique UV edges and labelled texture guide')
