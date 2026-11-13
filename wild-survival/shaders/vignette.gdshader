// HUD damage / low-health vignette.
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.6, 0.0, 0.0, 1.0);
uniform float strength = 0.0;

void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(tint.rgb, smoothstep(0.25, 0.8, d) * strength);
}
