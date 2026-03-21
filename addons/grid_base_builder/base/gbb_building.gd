class_name GBBBuilding
extends StaticBody3D

# Base class for placeable buildings.
#
# Visual mesh and CollisionShape3D belong in the scene, not here.
# grid_size is in building cells (1m each); set it per building via @export.
#
# Economy integration — connect these signals on the placed building instance:
#
#   building.construction_completed.connect(func(tab):
#       my_economy.free_slot(tab)
#       my_power.apply(building.power_usage)
#   )
#   building.sold.connect(func(refund): my_economy.earn(refund))
#   building.deselect_requested.connect(func(): my_selection.deselect_all())
#
# GBBBuildManager emits build_placed(building) right after placement,
# so that's the right place to connect these.

enum BuildAnim { RISE, SCALE, NONE }
enum ConstructionState { IDLE, BUILDING, ACTIVE }

# Kept here so hosts can read visual state without importing a separate enum file.
enum SelectionState { NONE, HOVERED, SELECTED, SELECTED_HOVERED }

signal construction_completed(tab_index: int)  # build animation done
signal sold(refund_amount: int)                 # sell() finished — host handles money
signal deselect_requested                       # sell() wants host to clear selection

# --- Placement ------------------------------------------
@export var grid_size: Vector2i = Vector2i(2, 2)

# --- Economics ------------------------------------------
@export var cost:        int = 0
## Positive = consumes power, negative = produces. Interpretation is up to the host.
@export var power_usage: int = 0

# --- Queue (C&C style sidebar) --------------------------
## 0 = enter preview immediately on click. >0 = sidebar countdown first.
@export var queue_time:  float    = 0.0
@export var build_time:  float    = 5.0
@export var build_anim:  BuildAnim = BuildAnim.RISE
@export var rise_height: float    = 2.0

# --- Indicator ------------------------------------------
@export var indicator_padding: float = 0.1

# --- Runtime state --------------------------------------
var is_preview: bool     = false   # set by GBBBuildManager before add_child
var grid_cell:  Vector2i = Vector2i.ZERO

var _state:              SelectionState    = SelectionState.NONE
var _construction_state: ConstructionState = ConstructionState.IDLE
var _build_elapsed:      float             = 0.0
var _tab_index:          int               = -1
var _final_y:            float             = 0.0

var _building_meshes: Array[MeshInstance3D] = []
var _bar_pivot: Node3D         = null
var _bar_bg:    MeshInstance3D = null
var _bar_fill:  MeshInstance3D = null

static var _tex_solid:  ImageTexture = null
static var _tex_dashed: ImageTexture = null

@onready var _select_indicator: MeshInstance3D = $SelectionIndicator
@onready var _hover_indicator:  MeshInstance3D = $HoverIndicator


func _ready() -> void:
	var cell_size_m := GBBGridSystem.BUILDING_SNAP * GBBGridSystem.CELL_SIZE
	var world_size  := Vector2(
		grid_size.x * cell_size_m + indicator_padding,
		grid_size.y * cell_size_m + indicator_padding
	)

	if not _tex_solid:
		_tex_solid  = _make_border_texture(256, false)
		_tex_dashed = _make_border_texture(256, true)

	var sel_mesh      := PlaneMesh.new()
	sel_mesh.size      = world_size
	_select_indicator.mesh = sel_mesh
	var sel_mat            := StandardMaterial3D.new()
	sel_mat.albedo_color   = Color(1.0, 1.0, 1.0, 0.9)
	sel_mat.albedo_texture = _tex_solid
	sel_mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	sel_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	_select_indicator.set_surface_override_material(0, sel_mat)
	_select_indicator.visible = false

	var hov_mesh      := PlaneMesh.new()
	hov_mesh.size      = world_size
	_hover_indicator.mesh = hov_mesh
	var hov_mat            := StandardMaterial3D.new()
	hov_mat.albedo_color   = Color(0.5, 0.85, 1.0, 0.55)
	hov_mat.albedo_texture = _tex_dashed
	hov_mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	hov_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_indicator.set_surface_override_material(0, hov_mat)
	_hover_indicator.visible = false

	if is_preview:
		return

	# Capture main meshes before start_construction adds progress bar nodes.
	for child in get_children():
		if child is MeshInstance3D \
				and child != _select_indicator \
				and child != _hover_indicator:
			_building_meshes.append(child)


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

# Called by GBBBuildManager right after the building is added to the scene.
func start_construction(tab_index: int) -> void:
	_tab_index          = tab_index
	_construction_state = ConstructionState.BUILDING
	_build_elapsed      = 0.0
	_final_y            = global_position.y

	_create_progress_bar()

	match build_anim:
		BuildAnim.RISE:
			global_position.y = _final_y - rise_height
		BuildAnim.SCALE:
			_set_mesh_scale(Vector3(0.01, 0.01, 0.01))
		BuildAnim.NONE:
			pass


func _process(delta: float) -> void:
	if _construction_state != ConstructionState.BUILDING:
		return

	_build_elapsed += delta
	var progress := clampf(_build_elapsed / build_time, 0.0, 1.0)

	if _bar_fill:
		_bar_fill.scale.x    = maxf(progress, 0.001)
		_bar_fill.position.x = (1.0 - progress) * _bar_fill_width() * 0.5

	if _bar_pivot:
		var camera := get_viewport().get_camera_3d()
		if camera:
			var dir := camera.global_position - _bar_pivot.global_position
			dir.y = 0.0
			if dir.length_squared() > 0.001:
				_bar_pivot.look_at(_bar_pivot.global_position + dir, Vector3.UP)

	match build_anim:
		BuildAnim.RISE:
			global_position.y = _final_y - rise_height * (1.0 - progress)
		BuildAnim.SCALE:
			var scale_factor := maxf(progress, 0.001)
			_set_mesh_scale(Vector3(scale_factor, scale_factor, scale_factor))
		BuildAnim.NONE:
			pass

	if progress >= 1.0:
		_activate()


func _activate() -> void:
	_construction_state = ConstructionState.ACTIVE
	global_position.y   = _final_y
	_set_mesh_scale(Vector3.ONE)

	if _bar_pivot:
		_bar_pivot.queue_free()
		_bar_pivot = null
	_bar_bg   = null
	_bar_fill = null

	# Let the host handle power and slot freeing via signal.
	construction_completed.emit(_tab_index)
	_tab_index = -1


# ---------------------------------------------------------------------------
# Sell
# ---------------------------------------------------------------------------

func sell() -> void:
	deselect_requested.emit()

	var nav_size := grid_size * GBBGridSystem.BUILDING_SNAP
	GBBGridSystem.free_cells(grid_cell, Vector2i(nav_size.x, nav_size.y))

	sold.emit(cost / 2)
	queue_free()


# ---------------------------------------------------------------------------
# Selection state  (host's selection system calls these)
# ---------------------------------------------------------------------------

func set_selection_state(new_state: SelectionState) -> void:
	_state = new_state
	var SS := SelectionState
	_select_indicator.visible = _state in [SS.SELECTED, SS.SELECTED_HOVERED]
	_hover_indicator.visible  = _state in [SS.HOVERED,  SS.SELECTED_HOVERED]


func get_selection_state() -> SelectionState:
	return _state


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _set_mesh_scale(s: Vector3) -> void:
	for mesh in _building_meshes:
		mesh.scale = s


func _create_progress_bar() -> void:
	var cell_size_m := GBBGridSystem.BUILDING_SNAP * GBBGridSystem.CELL_SIZE
	var bar_w       := float(grid_size.x) * cell_size_m
	var bar_height  := 0.10
	var bar_depth   := 0.003
	var local_y     := rise_height + 0.4

	_bar_pivot          = Node3D.new()
	_bar_pivot.position = Vector3(0.0, local_y, 0.0)
	add_child(_bar_pivot)

	var bg_mesh         := BoxMesh.new()
	bg_mesh.size         = Vector3(bar_w, bar_height, bar_depth)
	var bg_mat           := StandardMaterial3D.new()
	bg_mat.albedo_color  = Color(0.15, 0.15, 0.15)
	bg_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_bg              = MeshInstance3D.new()
	_bar_bg.mesh         = bg_mesh
	_bar_bg.set_surface_override_material(0, bg_mat)
	_bar_pivot.add_child(_bar_bg)

	var fill_mesh       := BoxMesh.new()
	fill_mesh.size       = Vector3(bar_w, bar_height, bar_depth)
	var fill_mat         := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.2, 0.85, 0.3)
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_fill            = MeshInstance3D.new()
	_bar_fill.mesh       = fill_mesh
	_bar_fill.set_surface_override_material(0, fill_mat)
	_bar_fill.position.z = -0.01
	_bar_fill.scale.x    = 0.001
	_bar_pivot.add_child(_bar_fill)


func _bar_fill_width() -> float:
	var cell_size_m := GBBGridSystem.BUILDING_SNAP * GBBGridSystem.CELL_SIZE
	return float(grid_size.x) * cell_size_m


# White rectangular border frame on a transparent background.
# dashed = true for the hover indicator, false for the selection indicator.
static func _make_border_texture(size: int, dashed: bool) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var t   := maxi(3, size / 16)
	for y in size:
		for x in size:
			var on_border := y < t or y >= size - t or x < t or x >= size - t
			if not on_border:
				continue
			if dashed:
				var d := x if (y < t or y >= size - t) else y
				if (d / (t * 3)) % 2 == 1:
					continue
			img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)
