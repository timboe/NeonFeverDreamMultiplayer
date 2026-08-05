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
	var sb: StyleBoxFlat = (base as StyleBoxFlat).duplicate()
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
	btn.remove_theme_stylebox_override("hover")
