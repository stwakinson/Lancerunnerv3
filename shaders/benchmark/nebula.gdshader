shader_type sky;

float hash(vec3 p) {
 p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
 p *= 17.0;
 return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise(vec3 p) {
 vec3 i = floor(p);
 vec3 f = fract(p);
 f = f * f * (3.0 - 2.0 * f);
 return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
                mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
            mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
                mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void sky() {
 vec3 p = EYEDIR * 4.0;
 float cloud = noise(p) * 0.55 + noise(p * 2.1) * 0.28 + noise(p * 4.3) * 0.12;
 float ribbon = exp(-pow((EYEDIR.y + EYEDIR.x * 0.34 - 0.12) * 5.5, 2.0));
 vec3 col = vec3(0.009, 0.018, 0.041);
 col += vec3(0.025, 0.14, 0.20) * ribbon * pow(cloud, 2.0) * 2.8;
 col += vec3(0.11, 0.08, 0.15) * pow(noise(p + 14.0), 4.0) * ribbon;
 vec3 cell = floor(EYEDIR * 620.0);
 float star = step(0.9986, hash(cell)) * pow(hash(cell + 9.0), 3.0);
 col += vec3(0.66, 0.83, 0.96) * star;
 COLOR = col;
}
