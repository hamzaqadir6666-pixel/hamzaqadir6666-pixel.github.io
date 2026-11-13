// River / lake water: animated ripples, depth-based colour and transparency, shoreline foam,
// sky-tinted reflection. Written so the surface stays visible even if the depth buffer
// cannot be read (it then falls back to an opaque, animated surface).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform vec3 shallow_color : source_color = vec3(0.13, 0.46, 0.44);
uniform vec3 deep_color : source_color = vec3(0.02, 0.17, 0.24);
uniform vec3 sky_tint : source_color = vec3(0.50, 0.68, 0.86);
uniform vec3 foam_color : source_color = vec3(0.86, 0.92, 0.90);
uniform float depth_fade = 1.4;      // metres of water until the deep colour takes over
uniform float min_opacity = 0.45;    // opacity of the water body right at the shore
uniform float max_opacity = 0.94;
uniform float wave_scale = 0.09;
uniform vec2 flow = vec2(0.035, 0.055);
uniform float wave_strength = 1.0;
uniform float ripple_contrast = 0.35;
uniform float refraction = 0.025;
uniform float foam_width = 0.30;
uniform float night_factor = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// world-space height of whatever is drawn behind the water at this screen position
float scene_height(vec2 suv, mat4 inv_proj, mat4 inv_view, out bool valid) {
	float d = texture(depth_tex, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 ndc = vec4(suv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
#else
	vec4 ndc = vec4(suv * 2.0 - 1.0, d, 1.0);
#endif
	vec4 v = inv_proj * ndc;
	valid = abs(v.w) > 1e-6;
	if (!valid) {
		return -1000.0;
	}
	v /= v.w;
	return (inv_view * vec4(v.xyz, 1.0)).y;
}

void fragment() {
	// ---- moving ripples (three scrolling layers of two normal maps)
	vec2 uv = world_pos.xz * wave_scale;
	vec3 n1 = texture(normal_a, uv + TIME * flow).rgb;
	vec3 n2 = texture(normal_b, uv * 1.7 - TIME * flow * 1.3 + vec2(0.3, 0.7)).rgb;
	vec3 n3 = texture(normal_a, uv * 0.31 + TIME * flow * 0.4).rgb;
	vec3 nm = normalize((n1 + n2 + n3) / 3.0 * 2.0 - 1.0);
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.3 * wave_strength;

	// ---- how deep is the water here (vertical metres); 3 m assumed if depth is unreadable
	bool ok;
	float ground_y = scene_height(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, ok);
	float depth_m = world_pos.y - ground_y;
	if (!ok || !(depth_m > -0.5) || depth_m > 500.0) {
		depth_m = 3.0;   // sky / far plane behind, or no usable depth: treat as deep water
	}
	depth_m = max(depth_m, 0.0);

	// ---- what is seen through the water, wobbling with the ripples
	vec2 ruv = SCREEN_UV + nm.xy * refraction * clamp(depth_m, 0.0, 1.0);
	bool ok2;
	float ground2 = scene_height(ruv, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, ok2);
	if (!ok2 || ground2 > world_pos.y) {
		ruv = SCREEN_UV;   // never pull things in front of the water into the refraction
	}
	vec3 behind = texture(screen_tex, clamp(ruv, vec2(0.001), vec2(0.999))).rgb;

	// ---- water body colour
	float night_dim = mix(1.0, 0.22, night_factor);
	float fade = 1.0 - exp(-depth_m / depth_fade);
	vec3 body = mix(shallow_color, deep_color, fade);
	// light and dark bands that travel with the ripples, so waves read even without highlights
	float ripple = (n1.r - 0.5) + (n2.g - 0.5) + (n3.r - 0.5) * 0.6;
	body *= 1.0 + ripple * ripple_contrast * 2.0;
	// reflection of the sky, stronger at grazing angles
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	body = mix(body, sky_tint, clamp(fres * 0.75 + 0.06, 0.0, 0.8));
	body *= night_dim;

	// ---- shoreline foam and drifting foam flecks
	float shore = 1.0 - smoothstep(0.0, foam_width, depth_m);
	float fleck = smoothstep(0.50, 0.72, texture(normal_b, uv * 3.0 + TIME * 0.05).g);
	float foam = clamp(shore * (0.45 + 0.55 * fleck), 0.0, 1.0);
	float crest = smoothstep(0.24, 0.42, ripple) * 0.18;   // faint white on the ripple tops
	body = mix(body, foam_color * night_dim, clamp(foam * 0.7 + crest, 0.0, 1.0));

	// ---- blend: clear at the very edge, tinted glass in the shallows, nearly opaque when deep
	float opacity = mix(min_opacity, max_opacity, fade);
	opacity = max(opacity, foam * 0.8);
	opacity *= smoothstep(0.0, 0.05, depth_m);   // soft edge where water meets the bank
	EMISSION = behind * (1.0 - opacity);         // the refracted scene, unlit (already shaded)
	ALBEDO = body * opacity;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
