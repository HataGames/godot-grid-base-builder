extends Node

# Manages the building ghost (preview) and placement.
#
# Two placement paths:
#   pre_paid = false  money + slot charged at try_place().
#   pre_paid = true   already handled upstream (e.g. C&C queue); try_place() skips charging.

signal build_placed(building: Node3D)  # emitted on successful placement; host connects building signals here
signal build_cancelled                  # emitted when cancel_build() is called while pre_paid is true
signal build_suspended                  # emitted when suspend_build() is called (mode switch, not cancel)

var _active:       bool        = false
var _blueprint:    PackedScene = null
var _placer:       Node3D      = null
var _placer_size:  Vector2i    = Vector2i(1, 1)
var _current_cell: Vector2i    = Vector2i.ZERO
var _can_place:    bool        = false

var _current_tab:  int  = -1
var _pending_cost: int  = 0
var _pre_paid:     bool = false
var _just_placed:  bool = false   # guard: stops build_cancelled from firing after a successful place

var _mat_ok:  StandardMaterial3D
var _mat_bad: StandardMaterial3D


func _ready() -> void:
	_mat_ok = StandardMaterial3D.new()
	_mat_ok.albedo_color = Color(0.2, 1.0, 0.3, 0.45)
	_mat_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_mat_bad = StandardMaterial3D.new()
	_mat_bad.albedo_color = Color(1.0, 0.15, 0.15, 0.45)
	_mat_bad.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func is_active() -> bool:
	return _active


func is_pre_paid() -> bool:
	return _pre_paid


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Enter ghost-preview mode.
# tab_index / cost are only used when pre_paid = false (immediate placement path).
func start_build(blueprint: PackedScene, tab_index: int = -1, cost: int = 0,
		pre_paid: bool = false) -> void:
	cancel_build()
	_blueprint     = blueprint
	_current_tab   = tab_index
	_pending_cost  = cost
	_pre_paid      = pre_paid
	_active        = true

	_placer      = blueprint.instantiate()
	_placer_size = _placer.grid_size if "grid_size" in _placer else Vector2i(1, 1)

	if "is_preview" in _placer:
		_placer.is_preview = true

	for child in _placer.get_children():
		if child is CollisionShape3D:
			child.disabled = true

	_apply_placer_mat(_placer, _mat_ok)
	get_tree().get_root().add_child(_placer)
	GBBGridSystem.set_display_mode(GBBGridSystem.DisplayMode.BUILDING_PREVIEW)


# Remove the ghost for a mode switch without cancelling the queue.
# SideControlPanel (or equivalent) listens to build_suspended to restore its READY state.
func suspend_build() -> void:
	if not _active:
		return
	var was_pre_paid := _pre_paid
	_active        = false
	_blueprint     = null
	_current_tab   = -1
	_pending_cost  = 0
	_pre_paid      = false
	if _placer:
		_placer.queue_free()
		_placer = null
	GBBGridSystem.set_display_mode(GBBGridSystem.DisplayMode.HIDDEN)
	if was_pre_paid:
		build_suspended.emit()


func cancel_build() -> void:
	var should_emit := _active and _pre_paid and not _just_placed
	_active        = false
	_blueprint     = null
	_current_tab   = -1
	_pending_cost  = 0
	_pre_paid      = false
	if _placer:
		_placer.queue_free()
		_placer = null
	GBBGridSystem.set_display_mode(GBBGridSystem.DisplayMode.HIDDEN)
	if should_emit:
		build_cancelled.emit()


func try_place() -> void:
	if not _active or not _can_place or not _blueprint:
		return

	if not _pre_paid:
		if not GBBEconomy.can_afford(_pending_cost):
			GBBEconomy.show_error("Not enough funds")
			return
		if not GBBEconomy.has_free_slot(_current_tab):
			GBBEconomy.show_error("Build queue full")
			return
		GBBEconomy.spend(_pending_cost)
		GBBEconomy.occupy_slot(_current_tab)

	var nav_size := _placer_size * GBBGridSystem.BUILDING_SNAP
	var building := _blueprint.instantiate()

	if "grid_cell" in building:
		building.grid_cell = _current_cell

	get_tree().current_scene.add_child(building)
	building.global_position = GBBGridSystem.cell_to_world(_current_cell, nav_size)
	GBBGridSystem.occupy(_current_cell, nav_size, building)

	if building.has_method("start_construction"):
		building.start_construction(_current_tab)

	_just_placed = true
	build_placed.emit(building)

	if _pre_paid or not Input.is_key_pressed(KEY_SHIFT):
		cancel_build()

	_just_placed = false


# ---------------------------------------------------------------------------
# Ghost update
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _active or not _placer:
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var hit := _ray_hit_ground(get_viewport().get_mouse_position(), camera)
	if hit == Vector3.INF:
		return

	var nav_size   := _placer_size * GBBGridSystem.BUILDING_SNAP
	_current_cell   = GBBGridSystem.snap_cell(hit, nav_size)
	_can_place      = GBBGridSystem.is_cells_free(_current_cell, nav_size)
	_placer.global_position = GBBGridSystem.cell_to_world(_current_cell, nav_size)
	_apply_placer_mat(_placer, _mat_ok if _can_place else _mat_bad)
	GBBGridSystem.update_preview_focus(_current_cell, _placer_size)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Assumes a flat ground plane at Y = 0. Override this if your game uses terrain.
func _ray_hit_ground(mouse_pos: Vector2, camera: Camera3D) -> Vector3:
	var origin := camera.project_ray_origin(mouse_pos)
	var dir    := camera.project_ray_normal(mouse_pos)
	if abs(dir.y) < 0.001:
		return Vector3.INF
	var t := -origin.y / dir.y
	if t < 0.0:
		return Vector3.INF
	return origin + dir * t


func _apply_placer_mat(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_placer_mat(child, mat)
