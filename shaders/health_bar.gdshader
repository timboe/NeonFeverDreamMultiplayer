shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float fraction : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.9, 0.15, 0.15, 0.95);
uniform vec4 bg_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);

void fragment() {
	if (UV.x <= fraction) {
		ALBEDO = fill_color.rgb;
		ALPHA = fill_color.a;
	} else {
		ALBEDO = bg_color.rgb;
		ALPHA = bg_color.a;
	}
}
