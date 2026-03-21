extends Node

# Global grid manager.
#
# The grid lives on the XZ plane. Vector2i(x, y) maps to world (x*CELL_SIZE, 0, z*CELL_SIZE).
# Note: grid "y" = world "z".
#
# Two layers:
#   Nav cell  (CELL_SIZE = 0.5m) — base unit for occupancy and pathfinding hooks.
#   Building cell (1m = 2 nav cells) — snap unit for placement.
#
# All occupancy and coordinate functions use nav-cell space.
# Building placement passes nav_size = grid_size * BUILDING_SNAP.

const CELL_SIZE     := 0.5
const BUILDING_SNAP := 2      # nav cells per building cell (1 building cell = 1m)
const PREVIEW_RINGS := 2      # building-cell rings drawn around the ghost footprint
const ALL_RANGE_M   := 30     # metres covered each way in ALL display mode

enum DisplayMode { HIDDEN, ALL, BUILDING_PREVIEW }

enum CellFlag {
	BUILDING = 1 << 0,  # a placed building occupies this cell
}

# Dictionary[Vector2i, int] — CellFlag bitmask per nav cell.
var _grid_flags: Dictionary = {}

var _display_mode:     DisplayMode = DisplayMode.HIDDEN
var _focus_nav_origin: Vector2i    = Vector2i.ZERO
var _focus_bld_size:   Vector2i    = Vector2i(1, 1)

var _mesh_inst: MeshInstance3D
var _imesh:     ImmediateMesh

# Ring 0 = footprint interior (never drawn). Rings 1+ fade toward the edge.
const _RING_ALPHA: Array[float] = [0.0, 1.0, 0.3, 0.6, 0.3, 0.08]
const _BASE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const _Y_OFFSET   := 0.02   # lift lines above ground to avoid z-fighting


func _ready() -> void:
	_imesh     = ImmediateMesh.new()
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = _imesh

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode     = BaseMaterial3D.CULL_DISABLED
	_mesh_inst.material_override = mat

	add_child(_mesh_inst)


func _process(_delta: float) -> void:
	if _display_mode != DisplayMode.HIDDEN:
		_rebuild_mesh()


# ---------------------------------------------------------------------------
# Display mode
# ---------------------------------------------------------------------------

func set_display_mode(mode: DisplayMode) -> void:
	_display_mode = mode
	if mode == DisplayMode.HIDDEN:
		_imesh.clear_surfaces()


# Called by GBBBuildManager every frame while a ghost is active.
func update_preview_focus(nav_origin: Vector2i, bld_size: Vector2i) -> void:
	_focus_nav_origin = nav_origin
	_focus_bld_size   = bld_size


# ---------------------------------------------------------------------------
# Coordinate helpers
# ---------------------------------------------------------------------------

# World position -> nav cell containing it.
func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.z / CELL_SIZE))


# Nav cell origin + nav footprint size -> world-space center of that footprint.
func cell_to_world(nav_cell: Vector2i, nav_size: Vector2i) -> Vector3:
	return Vector3(
		nav_cell.x * CELL_SIZE + nav_size.x * CELL_SIZE * 0.5,
		0.0,
		nav_cell.y * CELL_SIZE + nav_size.y * CELL_SIZE * 0.5
	)


# Snap a world hit point to the nearest 1m building-grid origin.
# Returns the top-left NAV cell of the footprint (always a multiple of BUILDING_SNAP).
func snap_cell(world_hit: Vector3, nav_size: Vector2i) -> Vector2i:
	var step    := BUILDING_SNAP * CELL_SIZE
	var half_wx := (nav_size.x / BUILDING_SNAP) * step * 0.5
	var half_wz := (nav_size.y / BUILDING_SNAP) * step * 0.5
	var ox_m    := roundf(world_hit.x - half_wx)
	var oz_m    := roundf(world_hit.z - half_wz)
	return Vector2i(roundi(ox_m / CELL_SIZE), roundi(oz_m / CELL_SIZE))


# ---------------------------------------------------------------------------
# Occupancy
# ---------------------------------------------------------------------------

# True if no cell in the footprint has any bit in block_mask set.
# Default blocks only BUILDING; pass a custom mask if your game adds extra flags.
func is_cells_free(origin: Vector2i, nav_size: Vector2i,
		block_mask: int = CellFlag.BUILDING) -> bool:
	for dx in range(nav_size.x):
		for dz in range(nav_size.y):
			if _grid_flags.get(origin + Vector2i(dx, dz), 0) & block_mask:
				return false
	return true


# Mark cells as occupied by a building.
func occupy(origin: Vector2i, nav_size: Vector2i, _building: Node) -> void:
	for dx in range(nav_size.x):
		for dz in range(nav_size.y):
			var cell := origin + Vector2i(dx, dz)
			_grid_flags[cell] = _grid_flags.get(cell, 0) | CellFlag.BUILDING


# Clear BUILDING flag from cells (other flags, if any, are preserved).
func free_cells(origin: Vector2i, nav_size: Vector2i) -> void:
	for dx in range(nav_size.x):
		for dz in range(nav_size.y):
			var cell: Vector2i  = origin + Vector2i(dx, dz)
			var flags: int      = _grid_flags.get(cell, 0) & ~CellFlag.BUILDING
			if flags == 0:
				_grid_flags.erase(cell)
			else:
				_grid_flags[cell] = flags


# Raw flag access — useful if your game extends CellFlag with its own bits.
func get_cell_flags(cell: Vector2i) -> int:
	return _grid_flags.get(cell, 0)


func set_cell_flags(cell: Vector2i, flags: int) -> void:
	if flags == 0:
		_grid_flags.erase(cell)
	else:
		_grid_flags[cell] = flags


# ---------------------------------------------------------------------------
# Grid rendering
# ---------------------------------------------------------------------------

func _rebuild_mesh() -> void:
	_imesh.clear_surfaces()
	_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	match _display_mode:
		DisplayMode.ALL:
			_draw_full_grid()
		DisplayMode.BUILDING_PREVIEW:
			_draw_preview_grid()
	_imesh.surface_end()


func _draw_full_grid() -> void:
	var color      := Color(_BASE_COLOR.r, _BASE_COLOR.g, _BASE_COLOR.b, 0.25)
	var step       := BUILDING_SNAP * CELL_SIZE
	var half_range := float(ALL_RANGE_M)
	var line_count := int(ALL_RANGE_M / step)
	for gi in range(-line_count, line_count + 1):
		var world_coord := gi * step
		_add_line(Vector3(-half_range, _Y_OFFSET, world_coord), Vector3(half_range, _Y_OFFSET, world_coord), color, color)
		_add_line(Vector3(world_coord, _Y_OFFSET, -half_range), Vector3(world_coord, _Y_OFFSET, half_range), color, color)


func _draw_preview_grid() -> void:
	# Convert nav origin to building-cell space.
	var foot_x := _focus_nav_origin.x / BUILDING_SNAP
	var foot_z := _focus_nav_origin.y / BUILDING_SNAP
	var foot_w := _focus_bld_size.x
	var foot_h := _focus_bld_size.y

	var min_bx := foot_x - PREVIEW_RINGS
	var min_bz := foot_z - PREVIEW_RINGS
	var max_bx := foot_x + foot_w + PREVIEW_RINGS
	var max_bz := foot_z + foot_h + PREVIEW_RINGS

	var step := BUILDING_SNAP * CELL_SIZE

	# Horizontal segments.
	for cell_z in range(min_bz, max_bz + 1):
		for cell_x in range(min_bx, max_bx):
			var ring_a := _cell_ring(cell_x, cell_z,     foot_x, foot_z, foot_w, foot_h)
			var ring_b := _cell_ring(cell_x, cell_z - 1, foot_x, foot_z, foot_w, foot_h)
			if maxi(ring_a, ring_b) > PREVIEW_RINGS:
				continue
			var alpha := maxf(_ring_alpha(ring_a), _ring_alpha(ring_b))
			if alpha <= 0.0:
				continue
			var color := Color(_BASE_COLOR.r, _BASE_COLOR.g, _BASE_COLOR.b, alpha)
			_add_line(
				Vector3(cell_x * step,       _Y_OFFSET, cell_z * step),
				Vector3((cell_x + 1) * step, _Y_OFFSET, cell_z * step),
				color, color
			)

	# Vertical segments.
	for cell_x in range(min_bx, max_bx + 1):
		for cell_z in range(min_bz, max_bz):
			var ring_a := _cell_ring(cell_x,     cell_z, foot_x, foot_z, foot_w, foot_h)
			var ring_b := _cell_ring(cell_x - 1, cell_z, foot_x, foot_z, foot_w, foot_h)
			if maxi(ring_a, ring_b) > PREVIEW_RINGS:
				continue
			var alpha := maxf(_ring_alpha(ring_a), _ring_alpha(ring_b))
			if alpha <= 0.0:
				continue
			var color := Color(_BASE_COLOR.r, _BASE_COLOR.g, _BASE_COLOR.b, alpha)
			_add_line(
				Vector3(cell_x * step, _Y_OFFSET, cell_z * step),
				Vector3(cell_x * step, _Y_OFFSET, (cell_z + 1) * step),
				color, color
			)


# Chebyshev ring distance from building cell (cx, cy) to a rectangular footprint.
# Returns 0 if inside the footprint.
func _cell_ring(cx: int, cy: int, foot_x: int, foot_y: int, foot_w: int, foot_h: int) -> int:
	if cx >= foot_x and cx < foot_x + foot_w and cy >= foot_y and cy < foot_y + foot_h:
		return 0
	var dist_x := maxi(0, maxi(foot_x - cx, cx - (foot_x + foot_w - 1)))
	var dist_y := maxi(0, maxi(foot_y - cy, cy - (foot_y + foot_h - 1)))
	return maxi(dist_x, dist_y)


func _ring_alpha(ring: int) -> float:
	if ring < 0 or ring >= _RING_ALPHA.size():
		return 0.0
	return _RING_ALPHA[ring]


func _add_line(a: Vector3, b: Vector3, ca: Color, cb: Color) -> void:
	_imesh.surface_set_color(ca)
	_imesh.surface_add_vertex(a)
	_imesh.surface_set_color(cb)
	_imesh.surface_add_vertex(b)
