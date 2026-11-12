// Heightmap-displaced, splat-blended jungle terrain.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D control_map : filter_linear, repeat_disable; // R trail, G wetness, B forest, A clearing
uniform float world_size = 1024.0;
uniform float cell_size = 2.0;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform float uv_scale = 0.22;
uniform float normal_strength = 1.0;
uniform vec3 grass_tint : source_color = vec3(0.78, 0.92, 0.62);
uniform float wet_darkening = 0.45;

varying vec3 world_pos;

float sample_height(vec2 xz) {
	vec2 uv = (xz + vec2(world_size * 0.5)) / world_size;
	// texel-centre correction: the map has (N+1) samples across N cells
	vec2 ts = vec2(textureSize(height_map, 0));
	uv = (uv * (ts - 1.0) + 0.5) / ts;
	return textureLod(height_map, uv, 0.0).r;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = sample_height(wp.xz);
	VERTEX.y += h;
	world_pos = vec3(wp.x, h, wp.z);
	float e = cell_size;
	float hl = sample_height(wp.xz - vec2(e, 0.0));
	float hr = sample_height(wp.xz + vec2(e, 0.0));
	float hd = sample_height(wp.xz - vec2(0.0, e));
	float hu = sample_height(wp.xz + vec2(0.0, e));
	NORMAL = normalize(vec3(hl - hr, 2.0 * e, hd - hu));
	TANGENT = normalize(vec3(2.0 * e, hr - hl, 0.0));
	BINORMAL = normalize(vec3(0.0, hu - hd, 2.0 * e));
}

vec4 layer(sampler2D tex, vec2 uv, float macro) {
	// two scales blended to hide tiling at distance
	vec4 a = texture(tex, uv);
	vec4 b = texture(tex, uv * 0.137 + vec2(0.37, 0.11));
	return mix(a, b, 0.35) * mix(0.82, 1.12, macro);
}

void fragment() {
	vec2 uv = world_pos.xz * uv_scale;
	vec2 cuv = (world_pos.xz + vec2(world_size * 0.5)) / world_size;
	vec4 ctl = texture(control_map, cuv);
	float macro = texture(macro_noise, world_pos.xz * 0.006).r;
	float detail = texture(macro_noise, world_pos.xz * 0.05).r;

	// geometric normal in world space for slope-based rock
	float e = cell_size;
	float hl = sample_height(world_pos.xz - vec2(e, 0.0));
	float hr = sample_height(world_pos.xz + vec2(e, 0.0));
	float hd = sample_height(world_pos.xz - vec2(0.0, e));
	float hu = sample_height(world_pos.xz + vec2(0.0, e));
	vec3 wn = normalize(vec3(hl - hr, 2.0 * e, hd - hu));
	float slope = 1.0 - wn.y;

	float w_forest = smoothstep(0.30, 0.65, ctl.b + (detail - 0.5) * 0.35) * (1.0 - ctl.a);
	float w_trail = smoothstep(0.25, 0.7, ctl.r + (detail - 0.5) * 0.3);
	float w_mud = smoothstep(0.45, 0.9, ctl.g + (detail - 0.5) * 0.3) * smoothstep(1.6, 0.3, world_pos.y);
	float w_sand = smoothstep(0.25, -0.5, world_pos.y + (detail - 0.5) * 0.4);
	float w_rock = smoothstep(0.22, 0.42, slope + (detail - 0.5) * 0.12);
	w_rock = max(w_rock, smoothstep(26.0, 40.0, world_pos.y + detail * 6.0));

	vec4 alb = layer(grass_albedo, uv, macro);
	alb.rgb *= grass_tint;
	vec3 nrm = texture(grass_normal, uv).rgb;
	float rough = 0.92;

	vec4 f = layer(forest_albedo, uv, macro);
	alb = mix(alb, f, w_forest); nrm = mix(nrm, texture(forest_normal, uv).rgb, w_forest);
	vec4 d = layer(dirt_albedo, uv * 1.3, macro);
	alb = mix(alb, d, w_trail); nrm = mix(nrm, texture(dirt_normal, uv * 1.3).rgb, w_trail);
	vec4 m = layer(mud_albedo, uv, macro);
	m.rgb *= (1.0 - wet_darkening);
	alb = mix(alb, m, w_mud); nrm = mix(nrm, texture(mud_normal, uv).rgb, w_mud);
	rough = mix(rough, 0.45, w_mud);
	vec4 s = layer(sand_albedo, uv, macro);
	s.rgb *= mix(1.0, 0.6, smoothstep(0.1, -0.6, world_pos.y));
	alb = mix(alb, s, w_sand); nrm = mix(nrm, texture(sand_normal, uv).rgb, w_sand);
	rough = mix(rough, 0.55, w_sand * smoothstep(0.2, -0.3, world_pos.y));
	vec4 r = layer(rock_albedo, uv * 0.6, macro);
	alb = mix(alb, r, w_rock); nrm = mix(nrm, texture(rock_normal, uv * 0.6).rgb, w_rock);
	rough = mix(rough, 0.8, w_rock);

	ALBEDO = alb.rgb;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength;
	AO = mix(1.0, 0.72, w_forest * 0.8);
	AO_LIGHT_AFFECT = 0.4;
}
