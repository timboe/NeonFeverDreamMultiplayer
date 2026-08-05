// Menu backdrop: faint cyan grid, ambient pulse and a vignette over a dark base.
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.02, 0.02, 0.05, 1.0);
uniform vec3 grid_color : source_color = vec3(0.0, 1.0, 1.0);
uniform float grid_alpha : hint_range(0.0, 0.3) = 0.05;
uniform float grid_spacing : hint_range(4.0, 256.0) = 20.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float pulse_amount : hint_range(0.0, 0.3) = 0.12;

void fragment() {
	vec3 col = base_color.rgb;

	// Faint grid.
	vec2 g = abs(fract(UV * grid_spacing) - 0.5);
	float line = 1.0 - smoothstep(0.46, 0.5, max(g.x, g.y));
	col = mix(col, grid_color, grid_alpha * line);

	// Slow ambient pulse.
	col *= 1.0 + pulse_amount * (0.5 + 0.5 * sin(TIME * 0.5));

	// Vignette.
	float d = distance(UV, vec2(0.5));
	col *= 1.0 - vignette_strength * smoothstep(0.35, 0.85, d);

	COLOR = vec4(col, base_color.a);
}
