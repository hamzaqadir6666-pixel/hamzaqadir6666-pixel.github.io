// Alpha-tested, wind-animated foliage (tree canopies, palms, bushes, plants).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_disabled, world_vertex_coords;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.4;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind_strength = 0.35;
uniform float wind_speed = 1.0;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float sway_start_height = 1.0;   // local height where sway begins (trunks stay put)
uniform float sway_height_scale = 0.08;  // sway growth per metre above start
uniform float flutter = 0.06;            // small per-leaf shimmer
uniform float backlight : hint_range(0.0, 1.0) = 0.45;
uniform float brightness = 0.82;         // overall albedo scale (source textures are pale)
uniform float roughness_value = 0.75;
uniform float push_radius = 0.0;         // >0: bends away from the player (bushes/grass)
uniform vec3 player_pos = vec3(0.0, -1000.0, 0.0);

void vertex() {
	// world_vertex_coords: VERTEX is already in world space, MODEL_MATRIX[3] is the plant's root
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 wp = VERTEX;
	float h = max(wp.y - origin.y - sway_start_height, 0.0);
	float amp = h * sway_height_scale * wind_strength;
	float phase = dot(origin.xz, vec2(0.13, 0.17));
	float t = TIME * wind_speed;
	float gust = sin(t * 0.7 + phase) * 0.6 + sin(t * 1.9 + phase * 2.3) * 0.3 + sin(t * 0.23 + phase * 0.5) * 0.5;
	vec2 offs = wind_dir * gust * amp;
	// leaf flutter (high frequency, position dependent)
	float fl = sin(t * 5.3 + wp.x * 2.1 + wp.z * 1.7 + wp.y * 3.0) * flutter * wind_strength * clamp(h, 0.0, 1.0);
	wp.x += offs.x + fl;
	wp.z += offs.y + fl * 0.7;
	wp.y -= length(offs) * 0.15;
	if (push_radius > 0.0) {
		vec3 to = wp - player_pos;
		float dist = length(to.xz);
		float k = (1.0 - smoothstep(0.0, push_radius, dist)) * clamp(h + 0.3, 0.0, 1.0);
		wp.xz += normalize(to.xz + vec2(0.0001)) * k * 0.6;
		wp.y -= k * 0.25;
	}
	VERTEX = wp;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ALBEDO = a.rgb * tint * brightness;
	ROUGHNESS = roughness_value;
	// two-sided lighting: flip normals on back faces
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = vec3(backlight * 0.5) * a.rgb * vec3(0.9, 1.0, 0.5);
}
