class_name GBBIconButtonSlot
extends Button

# Slot button with C&C-style queue display.
# All visuals are drawn on a transparent overlay so they don't affect layout.
#
# Queue states drive the clock-wipe mask and border colors:
#   RUNNING       — dark mask sweeps away clockwise as progress increases
#   PAUSED_MANUAL — dimmer mask + pause bars
#   PAUSED_AUTO   — red flashing mask (insufficient funds)
#   READY         — gold border, no mask
#   READY_CONFIRM — red border, cancel prompt

enum QueueState { NONE, RUNNING, PAUSED_MANUAL, PAUSED_AUTO, READY, READY_CONFIRM }

signal right_clicked

# Override these to localize status labels.
var label_paused:  String = "Paused"
var label_no_funds: String = "No Funds"
var label_ready:   String = "Ready"
var label_confirm: String = "Cancel?"

var _icon_rect:      ColorRect
var _hotkey_label:   Label
var _cost_label:     Label
var _border_overlay: Control

var _base_icon_color := Color(0.22, 0.32, 0.22)
var _is_hovered: bool = false
var _is_pressed: bool = false
var _is_empty:   bool = true

var _queue_state:    QueueState = QueueState.NONE
var _queue_progress: float      = 0.0
var _flash_time:     float      = 0.0


func _ready() -> void:
	flat = true
	custom_minimum_size = Vector2(54, 54)
	clip_contents = true

	_icon_rect = ColorRect.new()
	_icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_rect)

	_hotkey_label = Label.new()
	_hotkey_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hotkey_label.offset_top   = -18
	_hotkey_label.offset_right = 20
	_hotkey_label.add_theme_font_size_override("font_size", 9)
	_hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotkey_label)

	_cost_label = Label.new()
	_cost_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_cost_label.offset_top  = -18
	_cost_label.offset_left = -36
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cost_label.add_theme_font_size_override("font_size", 9)
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cost_label)

	_border_overlay = Control.new()
	_border_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_border_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border_overlay.connect("draw", _on_overlay_draw)
	add_child(_border_overlay)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)

	clear()


func _process(delta: float) -> void:
	if _queue_state == QueueState.PAUSED_AUTO:
		_flash_time += delta
		_border_overlay.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _queue_state != QueueState.NONE:
				right_clicked.emit()
				accept_event()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _on_overlay_draw() -> void:
	var rect   := Rect2(Vector2.ZERO, _border_overlay.size)
	var center := rect.size * 0.5

	if _queue_state != QueueState.NONE:
		_draw_queue_overlay(rect, center)

	var show_hover_border := _queue_state == QueueState.NONE \
			or _queue_state == QueueState.READY \
			or _queue_state == QueueState.READY_CONFIRM
	if show_hover_border:
		if _is_pressed:
			_border_overlay.draw_rect(rect, Color(0.75, 0.75, 0.75, 0.35), true)
			_border_overlay.draw_rect(rect, Color.WHITE, false, 1.5)
		elif _is_hovered:
			_border_overlay.draw_rect(rect, Color.WHITE, false, 1.5)


func _draw_queue_overlay(rect: Rect2, center: Vector2) -> void:
	match _queue_state:
		QueueState.RUNNING:
			_draw_clock_mask(rect, center, _queue_progress, Color(0.0, 0.0, 0.0, 0.60))

		QueueState.PAUSED_MANUAL:
			_draw_clock_mask(rect, center, _queue_progress, Color(0.0, 0.0, 0.0, 0.45))
			_draw_pause_bars(Vector2(center.x, center.y - 7.0))
			_draw_centered_text(rect, label_paused, 9, Color.WHITE, 8.0)

		QueueState.PAUSED_AUTO:
			var flash := sin(_flash_time * TAU * 1.5) * 0.5 + 0.5
			var alpha := lerpf(0.35, 0.75, flash)
			_draw_clock_mask(rect, center, _queue_progress, Color(0.55, 0.0, 0.0, alpha))
			_draw_centered_text(rect, label_no_funds, 10, Color.WHITE)

		QueueState.READY:
			_border_overlay.draw_rect(rect, Color(0.95, 0.80, 0.10, 0.45), false, 2.0)
			_draw_centered_text(rect, label_ready, 11, Color(0.98, 0.92, 0.30))

		QueueState.READY_CONFIRM:
			_border_overlay.draw_rect(rect, Color(0.90, 0.20, 0.20, 0.85), false, 2.5)
			_draw_centered_text(rect, label_confirm, 9, Color(1.0, 0.82, 0.82))


# Clockwise wipe mask: fully covered at progress=0, fully revealed at progress=1.
func _draw_clock_mask(rect: Rect2, center: Vector2, progress: float, color: Color) -> void:
	if progress >= 1.0:
		return
	if progress <= 0.0:
		_border_overlay.draw_rect(rect, color)
		return
	var mask_start := -PI * 0.5 + progress * TAU
	var mask_sweep := TAU * (1.0 - progress)
	var radius     := (rect.size * 0.5).length() + 2.0
	const STEPS    := 64
	var polygon    := PackedVector2Array()
	polygon.append(center)
	for i in range(STEPS + 1):
		var angle := mask_start + mask_sweep * float(i) / float(STEPS)
		polygon.append(center + Vector2(cos(angle), sin(angle)) * radius)
	_border_overlay.draw_colored_polygon(polygon, color)


func _draw_centered_text(rect: Rect2, text: String, font_size: int, color: Color,
		y_offset: float = 0.0) -> void:
	var font        := ThemeDB.fallback_font
	var text_height := font.get_height(font_size)
	var baseline_y  := rect.get_center().y + font.get_ascent(font_size) - text_height * 0.5 + y_offset
	_border_overlay.draw_string(font, Vector2(rect.position.x, baseline_y),
			text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)


func _draw_pause_bars(pos: Vector2) -> void:
	var bar_h := 9.0
	var bar_w := 3.0
	var gap   := 5.0
	_border_overlay.draw_rect(Rect2(pos.x - gap * 0.5 - bar_w, pos.y - bar_h * 0.5, bar_w, bar_h), Color(1.0, 1.0, 1.0, 0.90))
	_border_overlay.draw_rect(Rect2(pos.x + gap * 0.5,         pos.y - bar_h * 0.5, bar_w, bar_h), Color(1.0, 1.0, 1.0, 0.90))


# ---------------------------------------------------------------------------
# Mouse callbacks
# ---------------------------------------------------------------------------

func _on_mouse_entered() -> void:
	_is_hovered = true
	_border_overlay.queue_redraw()


func _on_mouse_exited() -> void:
	_is_hovered = false
	_border_overlay.queue_redraw()


func _on_button_down() -> void:
	_is_pressed = true
	_border_overlay.queue_redraw()


func _on_button_up() -> void:
	_is_pressed = false
	_border_overlay.queue_redraw()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(hotkey: String, cost: int, icon_color: Color = Color(0.22, 0.32, 0.22)) -> void:
	_base_icon_color   = icon_color
	_is_empty          = false
	disabled           = false
	modulate           = Color.WHITE
	_hotkey_label.text = hotkey
	_cost_label.text   = str(cost)
	_icon_rect.color   = icon_color
	set_queue(QueueState.NONE)


func clear() -> void:
	_base_icon_color   = Color(0.08, 0.08, 0.08, 1.0)
	_is_empty          = true
	disabled           = true
	modulate           = Color(0.4, 0.4, 0.4, 0.5)
	_hotkey_label.text = ""
	_cost_label.text   = ""
	_icon_rect.color   = Color(0.08, 0.08, 0.08, 1.0)
	set_queue(QueueState.NONE)


func set_panel_focused(focused: bool) -> void:
	if _is_empty or _queue_state != QueueState.NONE:
		return
	modulate = Color(1.0, 1.0, 0.65, 1.0) if focused else Color.WHITE


func set_queue(state: QueueState, progress: float = 0.0) -> void:
	_queue_state    = state
	_queue_progress = progress
	if state == QueueState.NONE:
		_flash_time = 0.0
	_border_overlay.queue_redraw()


func set_interactable(v: bool) -> void:
	if _is_empty:
		return
	disabled = not v
	modulate = Color.WHITE if v else Color(0.45, 0.45, 0.45, 0.65)
