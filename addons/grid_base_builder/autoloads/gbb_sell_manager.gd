extends Node

# Manages sell mode.
# When active, the next click on a building calls try_sell(), which delegates to building.sell().

signal sell_mode_changed(active: bool)
signal building_sold

var _active: bool = false


func is_active() -> bool:
	return _active


func start_sell() -> void:
	if _active:
		return
	# If a ghost is showing, get rid of it first.
	if GBBBuildManager.is_active():
		if GBBBuildManager.is_pre_paid():
			GBBBuildManager.suspend_build()
		else:
			GBBBuildManager.cancel_build()
	_active = true
	sell_mode_changed.emit(true)


func cancel_sell() -> void:
	if not _active:
		return
	_active = false
	sell_mode_changed.emit(false)


# Pass the clicked node; building.sell() handles grid cleanup, refund signal, queue_free.
func try_sell(building: Node) -> void:
	if not _active:
		return
	if building.has_method("sell"):
		building.sell()
		building_sold.emit()
