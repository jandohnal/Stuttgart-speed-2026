shader_type canvas_item;
// Porthole photo: archive photo (or a radial placeholder) cropped to cover the square, graded to
// a slightly sepia black and white, with scanlines, guide lines and a vignette, masked to a circle.

uniform sampler2D photo : source_color, filter_linear_mipmap;
uniform bool has_photo = false;
uniform float photo_aspect = 1.0; // width / height of the photo
uniform float size_px = 1088.0;
uniform float sepia = 0.15;
uniform float contrast = 1.15;
uniform vec3 guide_x = vec3(218.0, 464.0, 566.0);
uniform float guide_y = 70.0;

vec3 placeholder(vec2 uv) {
	// #A49E91 at (50%, 35%) -> #6F6A60 at 55 % -> #2C2A26 at the edge
	float r = length(uv - vec2(0.5, 0.35)) / 0.75;
	vec3 a = vec3(0.643, 0.620, 0.569);
	vec3 b = vec3(0.435, 0.416, 0.376);
	vec3 c = vec3(0.173, 0.165, 0.149);
	return r < 0.55 ? mix(a, b, r / 0.55) : mix(b, c, clamp((r - 0.55) / 0.45, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV;
	vec3 col;
	if (has_photo) {
		vec2 cover = photo_aspect > 1.0 ? vec2(1.0 / photo_aspect, 1.0) : vec2(1.0, photo_aspect);
		col = texture(photo, (uv - 0.5) * cover + 0.5).rgb;
	} else {
		col = placeholder(uv);
	}
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(grey), grey * vec3(1.07, 0.98, 0.82), sepia);
	col = clamp((col - 0.5) * contrast + 0.5, 0.0, 1.0);

	vec2 p = uv * size_px;
	float scan = step(mod(p.y, 4.0), 1.0) * 0.05;
	col = mix(col, vec3(1.0), scan);
	float guide = step(abs(p.x - guide_x.x), 1.0) + step(abs(p.x - guide_x.y), 1.0)
		+ step(abs(p.x - guide_x.z), 1.0) + step(abs(p.y - guide_y), 1.0);
	col = mix(col, vec3(1.0), min(guide, 1.0) * 0.28);

	float r = length(uv - 0.5);
	col *= 1.0 - smoothstep(0.3, 0.5, r) * 0.45;
	float edge = fwidth(r);
	COLOR = vec4(col, 1.0 - smoothstep(0.5 - edge, 0.5, r));
}
