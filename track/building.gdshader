// Building walls and roofs in their vertex colours, with simple windows painted on the walls.
// UV is (metres from the middle of the wall, metres above the building's base).
// UV2 is (height of the wall's top, length of the wall). COLOR.a picks the window style:
// 0 for none (roofs and gable ends), then house, shop, store and civic in eighths.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 glass : source_color = vec3(0.10, 0.13, 0.17);

varying vec3 tint;
varying float style;

void vertex() {
	// Vertex colours are sRGB; light works in linear.
	tint = mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, COLOR.rgb));
	style = COLOR.a * 8.0;
}

// 1 inside a run of panes: width w every period p, centred on 0.
float panes(float x, float p, float w, float blur) {
	float d = abs(fract(x / p + 0.5) - 0.5) * p;
	return 1.0 - smoothstep(w / 2.0 - blur, w / 2.0 + blur, d);
}

// 1 between heights low and high.
float band(float y, float low, float high, float blur) {
	return smoothstep(low - blur, low + blur, y) * (1.0 - smoothstep(high - blur, high + blur, y));
}

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float top = UV2.x;
	float half_length = UV2.y / 2.0;
	vec2 blur2 = fwidth(UV);
	float blur = max(max(blur2.x, blur2.y), 0.02);
	float window = 0.0;
	float average = 0.0;
	int kind = int(style + 0.5);
	if (kind == 1) {
		// House: a window every 3.2 m along, one row per 2.8 m floor.
		float floor_y = mod(y - 1.2, 2.8);
		window = panes(x, 3.2, 1.0, blur) * band(floor_y, 0.0, 1.3, blur) * band(y, 1.0, top - 0.5, blur);
		average = 0.13;
	} else if (kind == 2) {
		// Shop: a shop window across the ground floor, smaller windows above.
		float ground = band(y, 0.7, 2.9, blur) * (1.0 - panes(x, 2.5, 0.25, blur));
		float upper = panes(x, 2.6, 1.0, blur) * band(mod(y - 4.0, 3.2), 0.0, 1.5, blur) * band(y, 3.8, top - 0.6, blur);
		window = max(ground, upper);
		average = 0.3;
	} else if (kind == 3) {
		// Big store: a few wide windows by the ground, plain wall above.
		window = panes(x, 14.0, 4.0, blur) * band(y, 0.6, 2.6, blur);
		average = 0.06;
	} else if (kind == 4) {
		// Civic: tall windows close together on each 3.8 m floor.
		window = panes(x, 2.6, 1.2, blur) * band(mod(y - 1.4, 3.8), 0.0, 2.2, blur) * band(y, 1.2, top - 0.8, blur);
		average = 0.25;
	}
	// No windows cut by a corner.
	window *= 1.0 - smoothstep(half_length - 1.0 - blur, half_length - 0.6 + blur, abs(x));
	// Far off, the panes get smaller than a pixel: show them as a slightly darker wall instead.
	float near = 1.0 - smoothstep(0.15, 0.45, blur);
	window = mix(average * 0.6, window, near);
	ALBEDO = mix(tint, glass, window);
	ROUGHNESS = mix(0.92, 0.25, window);
	SPECULAR = mix(0.3, 0.6, window);
}
