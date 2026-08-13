shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec2 pupil_offset = vec2(0.0, 0.0);
uniform float pupil_radius : hint_range(0.2, 1.0) = 0.62;
uniform float eye_seed : hint_range(0.0, 10.0) = 1.0;
uniform vec3 eye_outward = vec3(0.0, 0.0, 1.0);
uniform vec4 sclera_color : source_color = vec4(0.95, 0.95, 1.0, 1.0);
uniform vec4 pupil_color : source_color = vec4(0.01, 0.01, 0.03, 1.0);

varying vec3 eye_world_pos;
varying vec3 world_pos;
varying vec3 gaze_world_dir;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	eye_world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 right = normalize((MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 up = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// Idle wobble: two per-eye seeded layers — a slow drift (~1.3/s re-roll)
	// plus a fast twitch (~5/s) so the pupils roam independently and never
	// hold a pose, giving the googly darting look.
	float t1 = floor(TIME * 1.3);
	float t2 = floor(TIME * 5.0);
	vec2 w1 = vec2(
		hash(vec3(eye_seed, t1, 0.0)),
		hash(vec3(eye_seed + 3.1, t1 + 0.7, 0.0)));
	vec2 w2 = vec2(
		hash(vec3(eye_seed + 5.7, t2, 0.0)),
		hash(vec3(eye_seed + 8.3, t2 + 0.23, 0.0)));
	vec2 offset = clamp(pupil_offset + (w1 - 0.5) * 0.6 + (w2 - 0.5) * 0.4, vec2(-1.0), vec2(1.0));
	// eye_outward is the socket direction in the unit's local frame (set per
	// eye from the sphere's position) — the cap faces away from the body, with
	// the wobble/velocity offsets rolling it around inside the socket.
	vec3 out_dir = normalize((MODEL_MATRIX * vec4(eye_outward, 0.0)).xyz);
	gaze_world_dir = normalize(out_dir + right * offset.x + up * offset.y);
}

void fragment() {
	vec3 dir = normalize(world_pos - eye_world_pos);
	float facing = dot(dir, gaze_world_dir);
	float edge = cos(pupil_radius * 1.2);
	// Pupil cap renders on the gaze side (outward socket face), so from the
	// outside each eye shows a black pupil dot rolling inside a white surround.
	float pupil = smoothstep(edge - 0.02, edge, facing);
	vec3 col = mix(sclera_color.rgb, pupil_color.rgb, pupil);
	ALBEDO = col;
	ROUGHNESS = 0.35;
	SPECULAR = 0.2;
	// Sclera gets a strong emissive lift so it reads as bright white against
	// the dark neon lighting; the pupil stays dark (its col is near-black).
	EMISSION = col * (0.15 + (1.0 - pupil) * 0.55);
}
