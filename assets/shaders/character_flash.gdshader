shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.35, 0.30, 1.0);
uniform vec4 outline_color : source_color = vec4(0.035, 0.043, 0.071, 1.0);
uniform float outline_source_px = 4.1;
uniform vec2 shadow_source_offset = vec2(0.0, 7.0);
uniform float shadow_source_blur = 3.0;
uniform float shadow_strength = 0.056;
uniform vec4 frame_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Data texture: no source_color hint (the R channel is linear coverage).
uniform sampler2D outfit_mask : filter_linear, repeat_disable;
uniform vec3 outfit_hsv = vec3(0.0, 0.0, 1.0);
uniform float outfit_enabled : hint_range(0.0, 1.0) = 0.0;

vec3 recolor_clothes(vec3 rgb, vec2 uv) {
	float value = clamp(max(max(rgb.r, rgb.g), rgb.b) * outfit_hsv.z, 0.0, 1.0);
	vec3 hue = abs(fract(vec3(outfit_hsv.x) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	vec3 recolored = value * mix(vec3(1.0), clamp(hue - 1.0, 0.0, 1.0), outfit_hsv.y);
	float mask = texture(outfit_mask, uv).r * outfit_enabled;
	return mix(rgb, recolored, mask);
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV) * COLOR;
	pixel.rgb = recolor_clothes(pixel.rgb, UV);
	vec2 step_size = TEXTURE_PIXEL_SIZE * outline_source_px;
	float outline_alpha = 0.0;
	outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(step_size.x, 0.0)).a);
	outline_alpha = max(outline_alpha, texture(TEXTURE, UV - vec2(step_size.x, 0.0)).a);
	outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(0.0, step_size.y)).a);
	outline_alpha = max(outline_alpha, texture(TEXTURE, UV - vec2(0.0, step_size.y)).a);
	outline_alpha = max(outline_alpha, texture(TEXTURE, UV + step_size * 0.707).a);
	outline_alpha = max(outline_alpha, texture(TEXTURE, UV - step_size * 0.707).a);
	outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(step_size.x, -step_size.y) * 0.707).a);
	outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(-step_size.x, step_size.y) * 0.707).a);
	vec2 shadow_uv = UV - TEXTURE_PIXEL_SIZE * shadow_source_offset;
	vec2 blur = TEXTURE_PIXEL_SIZE * shadow_source_blur;
	vec2 frame_min = frame_uv_rect.xy + TEXTURE_PIXEL_SIZE * 0.5;
	vec2 frame_max = frame_uv_rect.zw - TEXTURE_PIXEL_SIZE * 0.5;
	float shadow_alpha = (
		texture(TEXTURE, clamp(shadow_uv, frame_min, frame_max)).a
		+ texture(TEXTURE, clamp(shadow_uv + vec2(blur.x, 0.0), frame_min, frame_max)).a
		+ texture(TEXTURE, clamp(shadow_uv - vec2(blur.x, 0.0), frame_min, frame_max)).a
		+ texture(TEXTURE, clamp(shadow_uv + vec2(0.0, blur.y), frame_min, frame_max)).a
		+ texture(TEXTURE, clamp(shadow_uv - vec2(0.0, blur.y), frame_min, frame_max)).a
	) * shadow_strength;
	float border_alpha = max(outline_alpha - pixel.a, 0.0);
	float backdrop_alpha = max(border_alpha, shadow_alpha * (1.0 - outline_alpha));
	vec3 backdrop_color = mix(vec3(0.02, 0.025, 0.035), outline_color.rgb, step(shadow_alpha, border_alpha));
	vec3 flashed_rgb = mix(pixel.rgb, flash_color.rgb, flash_amount);
	COLOR = vec4(mix(backdrop_color, flashed_rgb, pixel.a), max(pixel.a, backdrop_alpha));
}
