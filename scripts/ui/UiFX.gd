class_name UiFX
extends RefCounted

# Attach a subtle pulsing glow to a button's hover stylebox. The hover stylebox
# is duplicated per-button so the shared theme resource is never mutated.
static func attach_glow_pulse(btn: Button, glow_color: Color = Color(0, 1, 1, 0.6)) -> void:
	if btn == null:
		return
	btn.mouse_entered.connect(_hover_enter.bind(btn, glow_color))
	btn.mouse_exited.connect(_hover_exit.bind(btn))

static func _hover_enter(btn: Button, glow_color: Color) -> void:
	if not is_instance_valid(btn):
		return
	var base := btn.get_theme_stylebox("hover")
	if not (base is StyleBoxFlat):
		return
	# Stash the effective hover stylebox (which may itself be a per-button
	# tinted override, e.g. HUD/TerminalHUD theming) so _hover_exit can restore
	# it instead of deleting the tint with the override.
	btn.set_meta("_ui_fx_hover_orig", base)
	var sb: StyleBoxFlat = (base as StyleBoxFlat).duplicate()
	# Re-tint the border with the accent colour too, so hover never falls back
	# to the default cyan theming.
	sb.border_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.9)
	sb.shadow_color = glow_color
	btn.add_theme_stylebox_override("hover", sb)
	var base_size: float = sb.shadow_size
	var tween := btn.create_tween().set_loops()
	tween.tween_property(sb, "shadow_size", base_size + 6.0, 0.45)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sb, "shadow_size", base_size, 0.45)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	btn.set_meta("_ui_fx_glow", tween)

static func _hover_exit(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	if btn.has_meta("_ui_fx_glow"):
		var tween = btn.get_meta("_ui_fx_glow")
		if tween and tween.is_valid():
			tween.kill()
		btn.remove_meta("_ui_fx_glow")
	if btn.has_meta("_ui_fx_hover_orig"):
		var orig = btn.get_meta("_ui_fx_hover_orig")
		btn.remove_meta("_ui_fx_hover_orig")
		if is_instance_valid(orig):
			btn.add_theme_stylebox_override("hover", orig)
			return
	btn.remove_theme_stylebox_override("hover")

# Apply the animated menu backdrop (grid + vignette + pulse) to a background rect.
static func apply_menu_backdrop(rect: ColorRect) -> void:
	if rect == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://materials/ui/menu_backdrop.gdshader")
	rect.material = mat

# Breathing "glow" on a title label — gently pulses the alpha.
static func pulse_title(title: Label, low_alpha: float = 0.65) -> void:
	if title == null:
		return
	var tween := title.create_tween().set_loops()
	tween.tween_property(title, "modulate:a", low_alpha, 1.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(title, "modulate:a", 1.0, 1.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
