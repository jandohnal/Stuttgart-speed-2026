// The original's sky (D-045, docs/formats/sky.md), drawn per view ray like Porsche.exe draws it
// before the scene: a parabolic dome with the sky layers of <Track>.txt and the horizon ring of
// <Track>.bin with the horz panorama tinted by hzcl. With use_panorama the dome is replaced by an
// HDRI (the HDRI option of D-019) and the ring stays in front of it.
// Coordinates: the original's are left-handed; x_original = -x here (the converters mirror X).
shader_type sky;

const float TAU_ = 6.28318530718;
const int SEGMENTS = 16;

// --- dome (SkyCnfig 0x3C: rotation, size, curvature, height) ---
uniform float dome_rotation = 0.0; // turns
uniform float dome_size = 1000.0;
uniform float dome_curvature = 0.0002;
uniform float dome_height = 100.0;
uniform float dome_cells = 15.0;

// --- layers: colour map of region A and B (blended by region_blend) times the cloud texture ---
uniform int layer_count = 1;
uniform int blend_mode = 0; // 0 normal (alpha), 1 additive, 2 attenuate, 3 modulate
uniform float region_blend = 0.0;
uniform sampler2D map_a0 : source_color, filter_linear, repeat_enable;
uniform sampler2D map_b0 : source_color, filter_linear, repeat_enable;
uniform sampler2D cloud0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D map_a1 : source_color, filter_linear, repeat_enable;
uniform sampler2D map_b1 : source_color, filter_linear, repeat_enable;
uniform sampler2D cloud1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D map_a2 : source_color, filter_linear, repeat_enable;
uniform sampler2D map_b2 : source_color, filter_linear, repeat_enable;
uniform sampler2D cloud2 : source_color, filter_linear_mipmap, repeat_enable;
// Per layer: xy = UV per dome cell (1 / scale), zw = wind in UV per second.
uniform vec4 layer0 = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 layer1 = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 layer2 = vec4(1.0, 1.0, 0.0, 0.0);
uniform float move_ratio = 0.0; // m driven per dome cell of parallax, 0 = none
uniform vec2 warp = vec2(0.0); // speed, amount

// --- horizon ring (SkyCnfig 0x04..0x3B) ---
uniform bool horizon_enabled = false;
// No mipmaps: they bled the tile row above into the clear top of the land (a dashed line).
uniform sampler2D horizon : source_color, filter_linear, repeat_disable;
uniform sampler2D horizon_colors : source_color, filter_nearest, repeat_disable; // hzcl 16x2
uniform float horizon_start = 0.0; // turns
uniform float horizon_offset = 0.0; // hzcl column of segment 0
uniform vec2 horizon_grid = vec2(4.0, 2.0); // horz tiles: columns, rows
uniform float horizon_base = -60.0;
uniform float horizon_top = 55.0;
uniform float horizon_radius = 400.0;
uniform vec4 horizon_tiles[16]; // x = tile, y = flip
uniform vec3 below_color : source_color = vec3(0.3);
uniform float horizon_energy = 1.0;

// --- HDRI instead of the dome ---
uniform bool use_panorama = false;
uniform sampler2D panorama : filter_linear;
uniform float panorama_energy = 1.0;

// --- sun sprite and brightness ---
uniform bool sun_enabled = false;
uniform sampler2D sun : source_color, filter_linear, repeat_disable;
uniform float sun_size = 0.06; // half width of the sprite as sine of the angle
uniform float energy = 1.0; // the whole sky (day / night)

vec4 layer_color(sampler2D map_a, sampler2D map_b, sampler2D cloud, vec2 uv) {
	vec4 m = mix(texture(map_a, uv), texture(map_b, uv), region_blend);
	return m * texture(cloud, uv);
}

vec3 blend(vec3 dst, vec4 src, int mode) {
	if (mode == 1) {
		return dst + src.rgb * src.a;
	} else if (mode == 2) {
		return dst * (1.0 - src.a);
	} else if (mode == 3) {
		return dst * mix(vec3(1.0), src.rgb, src.a);
	}
	return mix(dst, src.rgb, src.a);
}

vec3 dome(vec3 d, vec3 camera, float time) {
	// Ray from the camera onto y = height - curvature * (x^2 + z^2).
	float q = d.x * d.x + d.z * d.z;
	float t;
	if (q * dome_curvature < 1e-9) {
		t = dome_height / max(d.y, 1e-4);
	} else {
		t = (-d.y + sqrt(d.y * d.y + 4.0 * dome_curvature * q * dome_height)) / (2.0 * dome_curvature * q);
	}
	vec2 p = d.xz * t;
	float r = dome_rotation * TAU_;
	// Inverse of FUN_00460f40: x = cos r * lx + sin r * lz, z = -sin r * lx + cos r * lz.
	float lx = cos(r) * p.x - sin(r) * p.y;
	float lz = sin(r) * p.x + cos(r) * p.y;
	// Position on the dome, 0..1 from edge to edge (the colour maps span it once at scale 1).
	vec2 cell = vec2((dome_size * 0.5 - lx) / dome_size, (lz + dome_size * 0.5) / dome_size);
	if (move_ratio > 0.0) {
		// The camera's travel in the dome's frame, one dome cell per move_ratio metres.
		vec2 travel = vec2(cos(r) * camera.x - sin(r) * camera.z, sin(r) * camera.x + cos(r) * camera.z);
		cell += vec2(-travel.x, travel.y) / (move_ratio * dome_cells);
	}
	if (warp.y > 0.0) {
		cell += warp.y * 0.5 * vec2(sin(cell.y * 1.7 + time * warp.x * 3.1), cos(cell.x * 1.3 + time * warp.x * 2.3));
	}
	vec3 c = vec3(0.0);
	vec4 l0 = layer_color(map_a0, map_b0, cloud0, cell * layer0.xy + layer0.zw * time);
	c = l0.rgb;
	if (layer_count > 1) {
		c = blend(c, layer_color(map_a1, map_b1, cloud1, cell * layer1.xy + layer1.zw * time), blend_mode);
	}
	if (layer_count > 2) {
		c = blend(c, layer_color(map_a2, map_b2, cloud2, cell * layer2.xy + layer2.zw * time), blend_mode);
	}
	return c;
}

void sky() {
	vec3 d = vec3(-EYEDIR.x, EYEDIR.y, EYEDIR.z);
	vec3 camera = vec3(-POSITION.x, POSITION.y, POSITION.z);
	// Reflections and ambient light (cubemap pass) are rendered once: no wind there.
	float time = AT_CUBEMAP_PASS ? 0.0 : TIME;
	vec3 col;
	if (use_panorama) {
		col = texture(panorama, SKY_COORDS).rgb * panorama_energy;
	} else {
		col = dome(d, camera, time) * energy;
		if (sun_enabled && LIGHT0_ENABLED) {
			vec3 l = LIGHT0_DIRECTION;
			vec3 side = normalize(cross(abs(l.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0), l));
			vec3 up = cross(l, side);
			float facing = dot(EYEDIR, l);
			if (facing > 0.0) {
				vec2 suv = vec2(dot(EYEDIR, side), dot(EYEDIR, up)) / sun_size * 0.5 + 0.5;
				if (all(greaterThan(suv, vec2(0.0))) && all(lessThan(suv, vec2(1.0)))) {
					vec4 s = texture(sun, suv);
					col += s.rgb * s.a * LIGHT0_ENERGY;
				}
			}
		}
	}
	if (horizon_enabled) {
		float h = length(d.xz);
		if (h > 1e-4) {
			float y = d.y / h * horizon_radius;
			if (y < horizon_base) {
				col = below_color * horizon_energy;
			} else if (y <= horizon_top) {
				// Segment k spans start + k/16 turns; its corner is (sin, cos) * radius (FUN_00459d30).
				float a = fract(atan(d.x, d.z) / TAU_ - horizon_start);
				float s = a * float(SEGMENTS);
				int k = int(floor(s)) % SEGMENTS;
				float f = fract(s);
				vec4 tile = horizon_tiles[k];
				float column = mod(tile.x, horizon_grid.x);
				float row = floor(tile.x / horizon_grid.x);
				float u = (column + (tile.y > 0.5 ? 1.0 - f : f)) / horizon_grid.x;
				float down = (horizon_top - y) / max(horizon_top - horizon_base, 1e-3);
				// Porsche.exe maps 0.01..0.98 of the tile; keep 1.5 texels inside it for the filter.
				float margin = 1.5 / (float(textureSize(horizon, 0).y) / horizon_grid.y);
				float v = (row + clamp(0.01 + down * 0.97, margin, 1.0 - margin)) / horizon_grid.y;
				// hzcl: row 0 tints the top edge, row 1 the bottom one, one column per segment.
				float c0 = (mod(float(k) + horizon_offset, 16.0) + 0.5) / 16.0;
				float c1 = (mod(float(k + 1) + horizon_offset, 16.0) + 0.5) / 16.0;
				vec3 top = mix(texture(horizon_colors, vec2(c0, 0.25)).rgb, texture(horizon_colors, vec2(c1, 0.25)).rgb, f);
				vec3 bottom = mix(texture(horizon_colors, vec2(c0, 0.75)).rgb, texture(horizon_colors, vec2(c1, 0.75)).rgb, f);
				vec4 land = texture(horizon, vec2(u, v));
				land.rgb *= mix(top, bottom, down);
				col = mix(col, land.rgb * horizon_energy, land.a);
			}
		}
	}
	COLOR = col;
}
