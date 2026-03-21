@tool
extends EditorPlugin

# Autoloads must be registered in dependency order.
const _AUTOLOADS: Array[Array] = [
	["GBBEconomy",      "res://addons/grid_base_builder/autoloads/gbb_economy.gd"],
	["GBBGridSystem",   "res://addons/grid_base_builder/autoloads/gbb_grid_system.gd"],
	["GBBBuildManager", "res://addons/grid_base_builder/autoloads/gbb_build_manager.gd"],
	["GBBSellManager",  "res://addons/grid_base_builder/autoloads/gbb_sell_manager.gd"],
]


func _enable_plugin() -> void:
	for entry in _AUTOLOADS:
		add_autoload_singleton(entry[0], entry[1])


func _disable_plugin() -> void:
	# Reverse order to be safe.
	for i in range(_AUTOLOADS.size() - 1, -1, -1):
		remove_autoload_singleton(_AUTOLOADS[i][0])
