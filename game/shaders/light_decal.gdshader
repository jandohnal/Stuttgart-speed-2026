// Light decal of the original (D-044, docs/formats/map.md): a texture from <track>.env laid over
// the car while it drives through a section of <track>.map (tunnel lamps, tree shade). Drawn as
// a next pass of the car's materials. As in Porsche.exe, the texture is projected from above in
// the car's own frame (u across, v along the car), scaled by the section's texturesize and aspect
// and shifted by the car's offset from the road slice it is on, so the pattern scrolls over the
// car once per slice. The texture's colour is the light's, its alpha the pattern and strength;
// black with alpha darkens (shade), coloured lightens (lamps).
// Blend: the original mixes the texture over the car by its alpha. Over our lit PBR paint that
// turned the car flat white under a lamp, so the colour is added as light (rgb * a) and the car
// is only darkened by as much as the colour is dark (a * (1 - brightness)): black shade darkens
// as in the original, lamps brighten the car and keep its shading.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D decal : source_color, filter_linear_mipmap, repeat_enable;
uniform mat4 world_to_car; // inverse of the car's transform
uniform vec2 scale = vec2(0.1667); // 1 / texturesize, aspect / texturesize
uniform vec2 offset = vec2(0.5); // slice offset + 0.5
uniform vec3 tint = vec3(1.0); // lightdecal colour of the track's [header]
// Share of the texture's light added to the car. At 1 (and still at 0.35) a car under the middle
// of an Alps tunnel lamp (white, alpha 0.5-1) was white all over in our linear HDR lighting; the
// glow peaks mid-slice and fades to ~0.05 at the slice ends, so driving it is a short flash.
uniform float strength = 0.25;

varying vec2 decal_uv;

void vertex() {
	vec3 local = (world_to_car * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz;
	// The converter mirrors X (right-handed glTF); the original's x across the car is -x here.
	decal_uv = vec2(-local.x, local.z) * scale + offset;
}

void fragment() {
	vec4 t = texture(decal, decal_uv);
	vec3 light = t.rgb * tint;
	ALBEDO = light * t.a * strength; // premultiplied: added to the car
	ALPHA = t.a * (1.0 - clamp(max(light.r, max(light.g, light.b)), 0.0, 1.0)); // darkening share
}
