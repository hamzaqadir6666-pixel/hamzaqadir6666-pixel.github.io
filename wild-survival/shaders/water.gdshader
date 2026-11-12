// River / lake water: depth-based colour, animated normals, shoreline foam, soft refraction.
shader_type spatial;
render_mode cull_back, depth_draw_always, diffuse_burley, specular_schlick_ggx;

uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.36, 0.30);
uniform vec3 deep_color : source_color = vec3(0.03, 0.12, 0.13);
uniform float depth_fade = 2.6;
uniform float clarity = 0.9;
uniform float wave_scale = 0.07;
uniform vec2 flow = vec2(0.03, 0.05);
uniform float refraction = 0.03;
uniform float foam_width = 0.35;
uniform float night_factor = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * wave_scale;
	vec3 n1 = texture(normal_a, uv + TIME * flow).rgb;
	vec3 n2 = texture(normal_b, uv * 1.7 - TIME * flow * 1.3 + vec2(0.3, 0.7)).rgb;
	vec3 n3 = texture(normal_a, uv * 0.31 + TIME * flow * 0.4).rgb;
	vec3 nm = normalize((n1 + n2 + n3) / 3.0 * 2.0 - 1.0);
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.9;

	// scene depth behind the surface
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float scene_z = -upos.z / upos.w;
	float water_z = -VERTEX.z;
	float thickness = max(scene_z - water_z, 0.0);

	vec2 ruv = SCREEN_UV + nm.xy * refraction * clamp(thickness, 0.0, 1.0);
	float d2 = texture(depth_tex, ruv).r;
	vec4 up2 = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, d2, 1.0);
	if (-up2.z / up2.w < water_z) { ruv = SCREEN_UV; }
	vec3 behind = textureLod(screen_tex, ruv, 0.0).rgb;

	float fade = 1.0 - exp(-thickness / depth_fade);
	vec3 body = mix(shallow_color, deep_color, fade) * mix(1.0, 0.25, night_factor);
	vec3 col = mix(behind * mix(vec3(1.0), shallow_color * 2.2, clamp(thickness * 0.8, 0.0, 1.0)), body, clamp(fade * clarity + 0.12, 0.0, 1.0));

	float foam = (1.0 - smoothstep(0.0, foam_width, thickness)) * (0.55 + 0.45 * n1.r);
	foam *= smoothstep(0.35, 0.65, texture(normal_b, uv * 3.0 + TIME * 0.05).g + 0.2);
	col = mix(col, vec3(0.85, 0.9, 0.88) * mix(1.0, 0.3, night_factor), foam * 0.6);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col * (1.0 - fres * 0.5);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = smoothstep(0.0, 0.08, thickness);
}
