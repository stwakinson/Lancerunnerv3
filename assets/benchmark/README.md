# Artois nebula

`artois_nebula.png` is an AI-generated, painterly 2:1 equirectangular panorama
based on the approved pink/gold/blue nebula concept in this project conversation.
This is the game-ready derivative generated from that approved image, not a
recovered original file. The source pixels are retained without resampling.

**Actual dimensions: 1774 × 887, LDR PNG.** The generator returned this size even
though 4096 × 2048 was requested. This is not native 4K or HDR. Replace this image
with an authored higher-resolution panorama later without changing the scene.

The sky shader performs a narrow crossfade across longitude zero and blends each
pole toward a representative colour. These runtime corrections suppress the
visible wrap and pole pinching; they do not make the underlying generated image
a mathematically seamless asset. Mipmaps are enabled for later minification tuning; the sky shader explicitly
samples the base LOD to avoid wrap-derivative filtering streaks.

The planet uses the repository's existing Solar System Scope Jupiter texture;
see `assets/textures/CREDITS.txt` for its CC BY 4.0 attribution.
