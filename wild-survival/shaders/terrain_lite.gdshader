// Terrain for phones and the OpenGL renderer: the heights are already in the mesh (no height
// texture is read), no normal maps, seven textures in total so it fits old mobile GPUs.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D control_map : filter_linear, repeat_disable; // R trail, G wetness, B forest, A clearing
uniform float world_size = 1024.0;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.22;
uniform vec3 grass_tint : source_color = vec3(0.78, 0.92, 0.62);
uniform float brightness = 0.8;

varying vec3 world_pos;
varying float slope;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	slope = 1.0 - normalize(NORMAL).y;
}

void fragment() {
	vec2 uv = world_pos.xz * uv_scale;
	vec2 cuv = (world_pos.xz + vec2(world_size * 0.5)) / world_size;
	vec4 ctl = texture(control_map, cuv);
	float macro = texture(macro_noise, world_pos.xz * 0.006).r;
	float detail = texture(macro_noise, world_pos.xz * 0.05).r;

	float w_forest = smoothstep(0.30, 0.65, ctl.b + (detail - 0.5) * 0.35) * (1.0 - ctl.a);
	float w_trail = smoothstep(0.25, 0.7, ctl.r + (detail - 0.5) * 0.3);
	float w_mud = smoothstep(0.45, 0.9, ctl.g + (detail - 0.5) * 0.3) * smoothstep(1.6, 0.3, world_pos.y);
	float w_sand = smoothstep(0.25, -0.5, world_pos.y + (detail - 0.5) * 0.4);
	float w_rock = smoothstep(0.22, 0.42, slope + (detail - 0.5) * 0.12);
	w_rock = max(w_rock, smoothstep(26.0, 40.0, world_pos.y + detail * 6.0));

	vec3 alb = texture(grass_albedo, uv).rgb * grass_tint;
	alb = mix(alb, texture(forest_albedo, uv).rgb, w_forest);
	vec3 dirt = texture(dirt_albedo, uv * 1.3).rgb;
	alb = mix(alb, dirt, w_trail);
	alb = mix(alb, dirt * 0.5, w_mud);
	vec3 sand = texture(sand_albedo, uv).rgb * mix(1.0, 0.6, smoothstep(0.1, -0.6, world_pos.y));
	alb = mix(alb, sand, w_sand);
	alb = mix(alb, texture(rock_albedo, uv * 0.6).rgb, w_rock);
	alb *= mix(0.82, 1.12, macro);

	ALBEDO = alb * brightness * mix(1.0, 0.8, w_forest);
	ROUGHNESS = 1.0;
}
