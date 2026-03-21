# Grid Base Builder

A grid-based building placement system for Godot 4.x.

Handles ghost preview, placement validation, construction animations, and sell mode.
Economy integration is done through signals — the addon never touches your wallet, power, or queue systems directly.

Built with RTS and simulation games in mind, but works for any top-down builder.

---

## Requirements

- Godot 4.2+
- Forward Plus or Compatibility renderer

---

## Installation

1. Copy the `addons/grid_base_builder` folder into your project's `addons/` directory.
2. Open **Project → Project Settings → Plugins** and enable **Grid Base Builder**.

Enabling the plugin auto-registers four autoloads in the correct order:
`GBBEconomy` → `GBBGridSystem` → `GBBBuildManager` → `GBBSellManager`

---

## Quick Start

### 1. Wire up your economy

Call this once at startup (e.g. in your main scene's `_ready`):

```gdscript
# Register query functions so the build manager can check funds and queue slots.
GBBEconomy.register(
    func(amount): return my_wallet.can_afford(amount),
    func(tab):    return my_queue.has_free_slot(tab),
)

# Connect action signals so the addon can spend / earn through your economy.
GBBEconomy.spend_requested.connect(func(a): my_wallet.spend(a))
GBBEconomy.earn_requested.connect(func(a):  my_wallet.earn(a))
GBBEconomy.error_requested.connect(func(msg): show_notification(msg))

# Slot signals are optional — skip these if your game has no build queue limit.
GBBEconomy.slot_occupy_requested.connect(func(tab): my_queue.occupy(tab))
GBBEconomy.slot_free_requested.connect(func(tab):   my_queue.free(tab))
```

If you skip `register()`, all affordability checks pass and signals are no-ops — useful for prototyping.

### 2. Connect placed building signals

`GBBBuildManager.build_placed` fires every time a building lands. Connect building signals here:

```gdscript
GBBBuildManager.build_placed.connect(func(building: Node3D):
    building.construction_completed.connect(func(tab_index):
        my_power.apply(building.power_usage)
        my_queue.free_slot(tab_index)
    )
    building.sold.connect(func(refund): my_wallet.earn(refund))
    building.deselect_requested.connect(func(): my_selection.deselect_all())
)
```

### 3. Start a build

```gdscript
GBBBuildManager.start_build(my_building_scene)
# Player now sees a ghost that snaps to the grid.
# Left-click places it; right-click or call cancel_build() to abort.
```

---

## Creating a Building

Extend `GBBBuilding` and add your scene nodes:

**Required child nodes:**
- `SelectionIndicator` — `MeshInstance3D` (selection border, auto-sized)
- `HoverIndicator` — `MeshInstance3D` (hover border, auto-sized)

**Key exports:**

| Export | Type | Description |
|---|---|---|
| `grid_size` | `Vector2i` | Footprint in building cells (1 cell = 1m) |
| `cost` | `int` | Build cost passed to GBBEconomy |
| `power_usage` | `int` | Positive = consumes, negative = produces. Host interprets this. |
| `queue_time` | `float` | 0 = immediate preview. >0 = C&C-style sidebar countdown. |
| `build_time` | `float` | Construction animation duration in seconds |
| `build_anim` | `BuildAnim` | `RISE`, `SCALE`, or `NONE` |
| `rise_height` | `float` | RISE only: how deep underground the building starts |

**Signals emitted by GBBBuilding:**

| Signal | When |
|---|---|
| `construction_completed(tab_index)` | Build animation finished |
| `sold(refund_amount)` | `sell()` was called — host handles the money |
| `deselect_requested` | `sell()` wants the host to clear selection |

---

## Grid System

All coordinates are in **nav cells** (0.5m each). Buildings snap to **building cells** (1m = 2 nav cells).

```gdscript
# World position -> nav cell
GBBGridSystem.world_to_cell(position)

# Nav cell -> world center of a footprint
GBBGridSystem.cell_to_world(nav_cell, nav_size)

# Check if a footprint is free
GBBGridSystem.is_cells_free(origin, nav_size)

# Manually block / unblock cells (e.g. for water, cliffs, resource deposits)
GBBGridSystem.set_cell_flags(cell, GBBGridSystem.CellFlag.BUILDING)
GBBGridSystem.get_cell_flags(cell)

# Grid visualization
GBBGridSystem.set_display_mode(GBBGridSystem.DisplayMode.ALL)
GBBGridSystem.set_display_mode(GBBGridSystem.DisplayMode.HIDDEN)
```

---

## Sell Mode

```gdscript
GBBSellManager.start_sell()   # enter sell mode; next building click calls building.sell()
GBBSellManager.cancel_sell()  # exit sell mode

# To sell a specific building directly:
GBBSellManager.try_sell(building_node)
```

---

## Widgets

`GBBIconButtonSlot` is a standalone button widget with a C&C-style clockwise progress mask.
It has no dependency on the autoloads and can be used independently.

```gdscript
slot.setup("Q", 500)                      # hotkey label + cost display
slot.set_queue(GBBIconButtonSlot.QueueState.RUNNING, 0.4)  # 40% done
slot.clear()

# Localize status labels:
slot.label_paused   = "Paused"
slot.label_no_funds = "No Funds"
slot.label_ready    = "Ready"
slot.label_confirm  = "Cancel?"
```

---

## Notes

- `_ray_hit_ground` in `GBBBuildManager` assumes a flat ground at Y = 0. If your game has terrain, override it by extending `GBBBuildManager` and replacing that method.
- `CellFlag.BUILDING` is the only built-in flag. Use `set_cell_flags` / `get_cell_flags` with custom bitmask values to add your own (deposits, water, elevation zones, etc.).
- Shift-click places multiple buildings in a row (immediate mode only).

---

## License

MIT
