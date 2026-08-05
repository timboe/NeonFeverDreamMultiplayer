// Soft radial glow disc — used behind the terminal cursor and the FPS crosshair.
shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);

void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;
	float a = smoothstep(1.0, 0.0, d);
	a *= a;
	COLOR = vec4(glow_color.rgb, glow_color.a * a);
}
