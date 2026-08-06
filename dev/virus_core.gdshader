shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 player_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float cloak_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float energy : hint_range(0.0, 3.0) = 1.0;
uniform float churn_seed : hint_range(0.0, 10.0) = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0.0, 0.0, 0.0)), hash(i + vec3(1.0, 0.0, 0.0)), u.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), u.x), u.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), u.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), u.x), u.y),
		u.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * noise3(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

// 2D signed distance to a segment (chevron arms)
float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	float t = TIME * 0.9 + churn_seed * 3.0;
	vec3 dir = length(VERTEX) < 0.0001 ? vec3(0.0, 1.0, 0.0) : normalize(VERTEX);
	// Layer the surface with fbm noise and an upward-travelling wave so the
	// mass bubbles and churns like an electric cloud.
	float n = fbm(VERTEX * 1.4 + vec3(0.0, -t * 0.8, t * 0.6));
	float wave = 0.16 * sin(VERTEX.y * 2.6 - TIME * 2.4) * (0.5 + 0.5 * n);
	VERTEX += dir * (wave + n * 0.10);
}

void fragment() {
	float n = fbm(VERTEX * 2.0 + vec3(0.0, -TIME * 0.7, TIME * 0.5));
	vec3 N = normalize(NORMAL);
	vec3 V = normalize(VIEW);
	float ndv = abs(dot(N, V));
	float rim = pow(1.0 - ndv, 3.0);
	// Chevron glyph etched onto the surface (object-space XZ projection),
	// echoed as a nested chevron inside it.
	vec2 p = VERTEX.xz;
	vec2 apex = vec2(0.0, 0.62);
	vec2 l = vec2(-0.72, -0.28);
	vec2 r = vec2(0.72, -0.28);
	float d = min(sd_segment(p, apex, l), sd_segment(p, apex, r));
	float glyph = 1.0 - smoothstep(0.05, 0.11, d);
	float d2 = min(sd_segment(p, apex * 0.55, l * 0.55), sd_segment(p, apex * 0.55, r * 0.55));
	glyph = max(glyph, 1.0 - smoothstep(0.035, 0.08, d2));
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0 + churn_seed * 10.0);
	vec3 col = player_color.rgb;
	float brightness = 0.35 + rim * 1.6 + glyph * 1.7 * pulse + n * 0.4 * pulse;
	ALBEDO = col * (0.06 + brightness * 0.35);
	EMISSION = col * brightness * energy * (0.25 + 1.75 * cloak_alpha);
	ROUGHNESS = 0.4;
	METALLIC = 0.3;
	SPECULAR = 0.4;
	ALPHA = cloak_alpha;
}
