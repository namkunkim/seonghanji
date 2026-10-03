extends SceneTree

## Task ID: V-73 후속 (docs/07-production/demo-rc-v73-a5-a6.md §6·§7)
## 이동 미리보기 receipt의 기동 % 내역 · 함선 손실 시 전투 자원 용량 상한 축소.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Effects := preload("res://core/demo_red_cliffs/red_cliffs_combat_effects.gd")
const Resources := preload("res://core/demo_red_cliffs/red_cliffs_combat_resources.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void: call_deferred("_run")


func _run() -> void:
	print("V-73 follow-up: movement preview mobility breakdown and resource capacity losses")
	_test_preview_breakdown()
	_test_capacity_reduction()
	_test_battle_applies_capacity_losses()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _setup() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); return loaded.setup.duplicate(true)


func _init_core(script, setup: Dictionary):
	var core = script.new(); var result: Dictionary = core.initialize(setup)
	_ok(result.ok, "core initializes: %s" % str(result.get("errors", []))); return core


func _test_preview_breakdown() -> void:
	var battle := Battle.new(); _ok(battle.initialize(_setup()).ok, "battle initializes")
	var preview: Dictionary = battle.movement_preview("RC-LIU-SQ-01", [[900, 590]], 0)
	_eq([int(preview.base_speed), int(preview.command_mobility_percent), int(preview.formation_mobility_percent), int(preview.mobility_percent), int(preview.effective_speed)],
		[140, 0, 5, 5, 147], "preview receipt carries the core speed breakdown (FRM-01 +5%)")
	_eq(int(preview.mobility_percent), int(preview.command_mobility_percent) + int(preview.formation_mobility_percent), "total is the core sum, not a UI sum")
	_ok(battle.set_formation_order("RC-LIU-SQ-01", "FRM-06").ok, "draft formation change staged")
	var planned: Dictionary = battle.movement_preview("RC-LIU-SQ-01", [[900, 590]], 0)
	_eq([int(planned.formation_mobility_percent), int(planned.effective_speed)], [15, 161], "breakdown follows the drafted formation")
	var fast_craft: Dictionary = battle.movement_preview("RC-LIU-FC-01", [[900, 590]], 0)
	_ok(fast_craft.ok and fast_craft.has("formation_mobility_percent") and fast_craft.has("command_mobility_percent"), "fuel-wrapped fast-craft preview keeps the breakdown")


func _test_capacity_reduction() -> void:
	var setup := _setup(); var resources = _init_core(Resources, setup); var effects = _init_core(Effects, setup)
	var state: Dictionary = resources.initial_state(); var effect_state: Dictionary = effects.initial_state()
	var intact: Dictionary = resources.apply_composition_losses(state, effects.current_compositions(effect_state), 1)
	_ok(intact.ok and intact.capacity_events.is_empty() and intact.resource_state == state, "no losses → no capacity change")
	var cao: Dictionary = state["RC-CAO-SQ-01"]
	_eq(int(cao.weapons.line_fire.carrier_capacity), 8, "two SHP-01 carry 4 sorties each")
	# 앞 사격에서 자원을 일부 써 둔다 — 현재량이 새 상한 아래면 그대로 남아야 한다.
	cao.weapons.artillery.ammo = 3; cao.shared.energy = 100; cao.shared.heat = 90
	cao.weapons.line_fire.carrier_ready = 5
	var original: Array = effect_state.squadrons["RC-CAO-SQ-01"].original_composition
	var ships_before := 0; for component in original: ships_before += int(component.count)
	effect_state.squadrons["RC-CAO-SQ-01"].current_composition = effects._composition_after_losses(original, 2)
	var reduced: Dictionary = resources.apply_composition_losses(state, effects.current_compositions(effect_state), 3)
	_ok(reduced.ok, "capacity reduction succeeds: %s" % str(reduced.get("errors", [])))
	var row: Dictionary = reduced.resource_state["RC-CAO-SQ-01"]
	_eq([int(row.weapons.line_fire.carrier_capacity), int(row.weapons.line_fire.carrier_ready)], [0, 0], "carrier sorties capacity and ready count follow the lost carriers")
	_eq(int(row.shared.energy_capacity), int(cao.shared.energy_capacity) - 2 * 12, "energy capacity drops by the per-ship share")
	_eq(int(row.shared.heat_capacity), int(cao.shared.heat_capacity) - 2 * 8, "heat capacity drops by the per-ship share")
	_eq(int(row.shared.energy), 100, "energy below the new cap is not cut (no per-ship inference)")
	_eq(int(row.shared.heat), mini(90, int(row.shared.heat_capacity)), "heat is clamped only to the new cap")
	_eq(int(row.weapons.artillery.ammo), 3, "spent ammo below the new cap stays as it is")
	_eq(reduced.capacity_events.size(), 1, "one capacity event for the damaged squadron")
	_eq([String(reduced.capacity_events[0].event_type), String(reduced.capacity_events[0].event_id)], ["resource_capacity_reduced", "CAP-03-RC-CAO-SQ-01"], "capacity event is deterministic")
	_eq(reduced.resource_state["RC-SUN-SQ-01"], state["RC-SUN-SQ-01"], "undamaged squadrons are untouched")
	_ok(state["RC-CAO-SQ-01"].weapons.line_fire.carrier_capacity == 8, "prior state is not mutated")

	# 대량 손실: 포격 플랫폼까지 잃으면 포격 탄약이 상한으로 잘린다.
	var full: Dictionary = resources.initial_state()
	effect_state.squadrons["RC-CAO-SQ-01"].current_composition = effects._composition_after_losses(original, 10)
	var heavy: Dictionary = resources.apply_composition_losses(full, effects.current_compositions(effect_state), 4)
	var heavy_row: Dictionary = heavy.resource_state["RC-CAO-SQ-01"]
	_eq([int(heavy_row.weapons.artillery.ammo), int(heavy_row.weapons.artillery.ammo_capacity)], [0, 0], "lost artillery platforms take their ammo cap with them")
	_ok(int(heavy_row.weapons.line_fire.ammo) <= int(heavy_row.weapons.line_fire.ammo_capacity), "current never exceeds the new cap")
	var again: Dictionary = resources.apply_composition_losses(heavy.resource_state, effects.current_compositions(effect_state), 5)
	_ok(again.ok and again.capacity_events.is_empty(), "re-applying the same composition is idempotent")
	var restored: Dictionary = resources.apply_composition_losses(heavy.resource_state, effects.current_compositions(effects.initial_state()), 6)
	_eq(restored.resource_state, heavy.resource_state, "capacity never grows back")
	_ok(not resources.apply_composition_losses(full, {"RC-CAO-SQ-01": "bad"}, 1).ok, "malformed composition rejected")


func _test_battle_applies_capacity_losses() -> void:
	var battle := Battle.new(); _ok(battle.initialize(_setup()).ok, "battle initializes")
	var effects = _init_core(Effects, _setup())
	var row: Dictionary = battle._state.combat_effect_state.squadrons["RC-CAO-SQ-01"]
	row.current_composition = effects._composition_after_losses(row.original_composition, 2); row.casualties_total = 2
	_ok(battle.submit_command_draft().ok, "Liu draft submits")
	_ok(battle.submit_sun_control_choice("ai").ok, "Sun AI selected")
	var receipt: Dictionary = battle.resolve_turn()
	_ok(receipt.ok, "turn resolves: %s" % str(receipt.get("errors", [])))
	var resource_row: Dictionary = battle.combat_resource_state()["RC-CAO-SQ-01"]
	_eq(int(resource_row.weapons.line_fire.carrier_capacity), 0, "resolution shrinks carrier capacity after the carriers are gone")
	var log: Dictionary = battle._current_log()
	var ids: Array = []; for event in log.get("resource_capacity_events", []): ids.append(String(event.squadron_id))
	_ok(ids.has("RC-CAO-SQ-01"), "turn log records the capacity reduction")
