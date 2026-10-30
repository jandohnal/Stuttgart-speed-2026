shader_type canvas_item;
// Menu background: cream ground with concentric rings and radial spokes (positions in menu
// design pixels; menu.gd moves the centres with the bottom-centre anchor of the porthole).

uniform vec4 ground : source_color = vec4(0.886, 0.851, 0.733, 1.0); // #E2D9BB
uniform vec4 line_col : source_color = vec4(0.431, 0.361, 0.196, 1.0); // #6E5C32
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform vec2 ring_center = vec2(1060.0, 820.0);
uniform float ring_period = 73.0;
uniform float ring_width = 3.0;
uniform float ring_alpha = 0.16;
uniform vec2 spoke_center = vec2(1172.0, 829.0);
uniform float spoke_step_deg = 12.0;
uniform float spoke_width_deg = 0.5;
uniform float spoke_alpha = 0.12;

void fragment() {
	vec2 p = UV * rect_size;

	float d = length(p - ring_center);
	float ring = step(ring_period - ring_width, mod(d, ring_period));

	vec2 s = p - spoke_center;
	float ang = degrees(atan(s.x, -s.y)) + 180.0;
	float spoke = step(mod(ang, spoke_step_deg), spoke_width_deg);

	vec3 c = ground.rgb;
	c = mix(c, line_col.rgb, ring * ring_alpha);
	c = mix(c, line_col.rgb, spoke * spoke_alpha);
	COLOR = vec4(c, 1.0);
}
