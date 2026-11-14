// Water for phones and the OpenGL renderer: never reads the screen or the depth buffer.
// The depth of the water comes from the mesh (vertex colour red = metres / 4).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx, depth_draw_never;

uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.13, 0.46, 0.44);
uniform vec3 deep_color : source_color = vec3(0.02, 0.17, 0.24);
uniform vec3 sky_tint : source_color = vec3(0.50, 0.68, 0.86);
uniform float wave_scale = 0.09;
uniform vec2 flow = vec2(0.035, 0.055);
uniform float night_factor = 0.0;

varying vec3 world_pos;
varying float depth_m;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth_m = COLOR.r * 4.0;
}

void fragment() {
	vec2 uv = world_pos.xz * wave_scale;
	vec3 n1 = texture(normal_a, uv + TIME * flow).rgb;
	vec3 n2 = texture(normal_b, uv * 1.7 - TIME * flow * 1.3 + vec2(0.3, 0.7)).rgb;
	NORMAL_MAP = (n1 + n2) * 0.5;
	NORMAL_MAP_DEPTH = 1.2;
	float fade = 1.0 - exp(-max(depth_m, 0.0) / 1.4);
	vec3 body = mix(shallow_color, deep_color, fade);
	float ripple = (n1.r - 0.5) + (n2.g - 0.5);
	body *= 1.0 + ripple * 0.7;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	body = mix(body, sky_tint, clamp(fres * 0.75 + 0.06, 0.0, 0.8));
	ALBEDO = body * mix(1.0, 0.22, night_factor);
	ALPHA = mix(0.6, 0.94, fade);
	ROUGHNESS = 0.1;
	SPECULAR = 0.5;
}
