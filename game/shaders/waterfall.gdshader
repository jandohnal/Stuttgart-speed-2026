// Water running down the original's waterfall mesh (Waterfall, D-033). The flow coordinate comes
// from the height fallen, not from the mesh's UVs: its square root moves at a steady rate along a
// body falling from rest, so the pattern speeds up and its streaks stretch on the way down. Layers
// of the original's sheet texture at different speeds, broken up by noise, make the foam.
shader_type spatial;
render_mode cull_disabled, depth_draw_never;

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float top = 0.0; // height of the lip, m
uniform float flow = 0.35; // texture repeats per second
uniform float repeats = 0.6; // texture repeats per square root of a metre fallen
uniform vec3 water_color = vec3(0.50, 0.58, 0.62);
uniform vec3 foam_color = vec3(0.96, 0.97, 0.98);

varying float height;

void vertex() {
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float fall = sqrt(max(top - height, 0.0));
	float s = fall * repeats;
	vec4 a = texture(sheet, vec2(UV.x, s - TIME * flow));
	vec4 b = texture(sheet, vec2(UV.x * 1.7 + 0.31, s * 1.3 - TIME * flow * 1.45));
	float n = texture(noise, vec2(UV.x * 2.0, s * 0.35 - TIME * flow * 0.6)).r;
	float body = max(a.a, b.a * 0.85);
	float foam = smoothstep(0.25, 0.8, body * (0.55 + n));
	// Soft sides; a thin film of water between the streaks, thinner near the lip.
	float sides = smoothstep(0.0, 0.14, UV.x) * smoothstep(1.0, 0.86, UV.x);
	float film = 0.35 * smoothstep(0.0, 3.0, fall);
	ALBEDO = mix(water_color, foam_color, foam);
	ALPHA = clamp(max(foam, film) * sides, 0.0, 1.0);
	ROUGHNESS = mix(0.25, 0.8, foam);
	SPECULAR = 0.5;
}
