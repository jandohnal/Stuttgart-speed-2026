// The original's headlight light on the track (CarBeam, Porsche.exe FUN_00452910, LayerVertexLight):
// light = (texel of nght - |height| * 32) / 256, added to the track's colour. UV = place in the nght
// texture (u across, v ahead), UV2.x = |height| of the point above or below the car in metres.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D pool : filter_linear, repeat_disable;  // nght, grey: the palette ramp is linear
uniform vec3 color = vec3(0.5);  // light colour 0xFF808080
uniform float height_falloff = 0.125;  // 32 / 256 per metre

void fragment() {
	float light = max(texture(pool, UV).r - UV2.x * height_falloff, 0.0);
	ALBEDO = color * light;
}
