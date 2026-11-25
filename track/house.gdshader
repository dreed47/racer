// Modelled houses (see HouseKit) in their vertex colours, with the wall or roof texture drawn here
// so it costs no geometry. UV is metres (along the face, up the face). COLOR.a picks the texture
// in eighths: 0 plain, 1 lap siding, 2 brick, 3 board and batten, 4 shingles, 5 metal roof,
// 6 garage door panels, 7 glass.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 mortar : source_color = vec3(0.62, 0.6, 0.56);

varying vec3 tint;
varying float kind;

void vertex() {
	// Vertex colours are sRGB; light works in linear.
	tint = mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, COLOR.rgb));
	kind = COLOR.a * 8.0;
}

// 1 on a line of the given width at every multiple of period. Once the lines get finer than a
// pixel they fade to their average, so far walls don't shimmer.
float lines(float v, float period, float width, float fw) {
	float d = abs(fract(v / period + 0.5) - 0.5) * period;
	float line = 1.0 - smoothstep(width * 0.5, width * 0.5 + fw, d);
	float fade = 1.0 - smoothstep(period * 0.25, period * 0.7, fw);
	return mix(width / period, line, fade);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 fw2 = fwidth(uv);
	float fw = max(max(fw2.x, fw2.y), 0.002);
	int k = int(kind + 0.5);
	vec3 albedo = tint;
	float rough = 0.88;
	float spec = 0.3;
	float metal = 0.0;
	if (k == 1) {
		// Lap siding: a shadow line under each 0.2 m board.
		albedo *= 1.0 - 0.3 * lines(uv.y, 0.2, 0.025, fw);
	} else if (k == 2) {
		// Brick: 0.075 m courses of 0.21 m bricks, every other course shifted half a brick.
		float course = floor(uv.y / 0.075);
		float x = uv.x + 0.105 * mod(course, 2.0);
		float near = 1.0 - smoothstep(0.04, 0.12, fw);
		float shade = mix(1.0, 0.86 + 0.26 * hash(vec2(floor(x / 0.21), course)), near);
		float joint = max(lines(uv.y, 0.075, 0.012, fw), lines(x, 0.21, 0.012, fw) * near);
		vec3 grout = mortar * mortar;
		albedo = mix(albedo * shade, grout, joint * 0.85);
	} else if (k == 3) {
		// Board and batten: a raised batten every 0.4 m, lit on one edge.
		albedo *= 1.0 + 0.35 * lines(uv.x, 0.4, 0.05, fw) - 0.25 * lines(uv.x + 0.035, 0.4, 0.02, fw);
	} else if (k == 4) {
		// Shingles: a dark line under each 0.25 m row, tabs a little different in shade.
		float row = floor(uv.y / 0.25);
		float tab = floor((uv.x + 0.45 * mod(row, 2.0)) / 0.9);
		float near = 1.0 - smoothstep(0.05, 0.2, fw);
		float shade = mix(1.0, 0.85 + 0.3 * hash(vec2(tab, row)), near);
		albedo *= shade * (1.0 - 0.35 * lines(uv.y, 0.25, 0.03, fw));
	} else if (k == 5) {
		// Standing seam metal: a bright rib every 0.45 m down the slope.
		albedo *= 1.0 + 0.4 * lines(uv.x, 0.45, 0.04, fw);
		rough = 0.45;
		spec = 0.5;
		metal = 0.4;
	} else if (k == 6) {
		// Garage door: a groove between each 0.53 m panel.
		albedo *= 1.0 - 0.35 * lines(uv.y, 0.53, 0.03, fw);
		rough = 0.6;
	} else if (k == 7) {
		rough = 0.12;
		spec = 0.7;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
}
