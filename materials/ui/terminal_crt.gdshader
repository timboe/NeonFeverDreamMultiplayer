// CRT / terminal overlay for the diegetic building HUDs.
// Draws a faint phosphor glow (visible colour cast over the whole screen),
// scanlines, a vignette (screen falloff) and a subtle rolling flicker.
shader_type canvas_item;

uniform float viewport_height : hint_range(64.0, 1024.0) = 480.0;
uniform float scanline_spacing : hint_range(1.0, 16.0) = 4.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.25;
uniform vec3 phosphor_tint : source_color = vec3(0.5, 1.0, 0.8);
uniform float phosphor_glow : hint_range(0.0, 0.5) = 0.09;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.355;
uniform float flicker_amount : hint_range(0.0, 0.25) = 0.045;

void fragment() {
	// Scanlines: dark bands running horizontally.
	float line = 0.5 + 0.5 * sin(UV.y * TAU * viewport_height / scanline_spacing);
	float scan = (1.0 - line) * scanline_strength;

	// Vignette: darker toward the edges (screen curvature falloff).
	float d = distance(UV, vec2(0.5));
	float vig = vignette_strength * smoothstep(0.4, 0.95, d);

	// Subtle phosphor flicker, rolling down the screen.
	float flick = flicker_amount * (0.5 + 0.5 * sin(TIME * 55.0 + floor(UV.y * viewport_height) * 2.5));

	float a = clamp(phosphor_glow + scan + vig + flick, 0.0, 1.0);
	COLOR = vec4(phosphor_tint * a, a);
}
