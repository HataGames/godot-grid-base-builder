extends Node

# Economy interface bridge.
#
# GBBBuildManager and GBBBuilding never call your game's economy system directly.
# Instead they call methods here, which emit signals your game connects to.
#
# Minimal setup — call register() once at startup:
#
#   GBBEconomy.register(
#       func(amount): return my_wallet.can_afford(amount),
#       func(tab):    return my_queue.has_free_slot(tab),
#   )
#   GBBEconomy.spend_requested.connect(func(a): my_wallet.spend(a))
#   GBBEconomy.earn_requested.connect(func(a):  my_wallet.earn(a))
#
# If you don't register anything, all checks pass and signals are ignored —
# useful when prototyping without an economy system.

signal spend_requested(amount: int)
signal earn_requested(amount: int)
signal slot_occupy_requested(tab: int)
signal slot_free_requested(tab: int)
signal error_requested(msg: String)

var _can_afford_fn: Callable
var _has_slot_fn:   Callable


func register(can_afford_fn: Callable, has_slot_fn: Callable) -> void:
	_can_afford_fn = can_afford_fn
	_has_slot_fn   = has_slot_fn


# --- Query functions (called by build manager / building base class) ---

func can_afford(amount: int) -> bool:
	if _can_afford_fn.is_valid():
		return _can_afford_fn.call(amount)
	return true


func has_free_slot(tab: int) -> bool:
	if _has_slot_fn.is_valid():
		return _has_slot_fn.call(tab)
	return true


# --- Action functions (emit signals for the host to handle) ---

func spend(amount: int) -> void:
	spend_requested.emit(amount)


func earn(amount: int) -> void:
	earn_requested.emit(amount)


func occupy_slot(tab: int) -> void:
	slot_occupy_requested.emit(tab)


func free_slot(tab: int) -> void:
	slot_free_requested.emit(tab)


func show_error(msg: String) -> void:
	error_requested.emit(msg)
