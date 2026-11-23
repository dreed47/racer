shader_type spatial;
// Ground with world-space grid lines, so you can see speed and position.

uniform vec3 base_color : source_color = vec3(0.30, 0.32, 0.34);
uniform vec3 line_color : source_color = vec3(0.80, 0.80, 0.78);
uniform float cell_size = 5.0;
uniform float line_width = 0.05;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = abs(fract(world_pos.xz / cell_size + 0.5) - 0.5) * cell_size;
	float d = min(cell.x, cell.y);
	float line = 1.0 - smoothstep(line_width, line_width + fwidth(d) * 1.5, d);
	ALBEDO = mix(base_color, line_color, line);
	ROUGHNESS = 0.9;
}
