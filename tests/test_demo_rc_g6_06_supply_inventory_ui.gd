extends SceneTree

## DEMO-RC-G6-06 — 보급함 재고·손상 처리량·거점 재적재 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const BattleView := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0

func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)

func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])

func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G6-06 — 보급함 재고·손상 처리량·거점 재적재")
	root.size = Vector2i(1600, 900)
	await _test_read_only_provider_panel()
	_test_authoritative_event_text()
	_test_viewer_and_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)

func _battle():
	var loaded := Setup.load_default(); _ok(loaded.ok, "default setup loads")
	var battle = Battle.new(); _ok(battle.initialize(loaded.setup).ok, "battle initializes"); return battle

func _view(battle):
	var view := BattleView.new(); _ok(view.configure(battle, 1, "g6-06-ui").ok, "battle view configures"); root.add_child(view); return view

func _test_read_only_provider_panel() -> void:
	var battle = _battle(); var receipt: Dictionary = battle.viewer_supply_inventory("liu_bei")
	_ok(receipt.ok and receipt.has("providers") and receipt.has("events"), "public viewer receipt exposes providers and events")
	_ok(not receipt.providers.is_empty(), "Liu viewer receives own supply provider")
	var provider: Dictionary = receipt.providers[0]; var view = _view(battle); await _settle()
	_eq(view.find_children("SupplyInventoryTitle", "Label", true, false).size(), 1, "independent inventory panel renders exactly once")
	var title: Label = view.find_child("SupplyInventoryTitle", true, false)
	_ok(title != null and title.text.contains("자동 판정") and title.text.contains("읽기 전용"), "panel states automatic read-only contract")
	var state: Label = view.find_child("SupplyInventoryState_%s" % String(provider.source_id), true, false)
	var fuel: Dictionary = provider.inventory.fuel; var ammo: Dictionary = provider.inventory.ammo; var materials: Dictionary = provider.inventory.supply_materials
	_ok(state != null and state.text.contains("통합 재고") and state.text.contains("함 연료 %d/%d bp" % [fuel.current, fuel.maximum]), "provider renders exact core fuel inventory")
	_ok(state.text.contains("함 탄약 %d/%d units" % [ammo.current, ammo.maximum]) and state.text.contains("보급 물자 %d/%d units" % [materials.current, materials.maximum]), "provider renders exact core ammo and material inventory")
	_ok(state.text.contains("중파 %d" % int(provider.ship_status_counts.moderate_damage)) and state.text.contains("대파 %d" % int(provider.ship_status_counts.heavy_damage)), "provider renders core ship damage counts")
	_ok(state.text.contains("처리율 %d bp/턴" % provider.effective_throughput_basis_points_per_turn) and state.text.contains("이번 턴 잔여 %d전대" % provider.available_capacity_squadrons_this_turn) and state.text.contains("정상 기준 %d전대/턴" % provider.base_capacity_squadrons_per_turn), "provider separates weighted throughput from current available capacity")
	_ok(state.text.contains("거점 재적재") and state.text.contains("진행 %d/%d턴" % [provider.reload.progress_turns, provider.reload.required_turns]), "provider renders authoritative base reload progress")
	var boundary: Label = view.find_child("SupplyInventoryBoundary", true, false)
	_ok(boundary != null and boundary.text.contains("보급함 간 물자 이전 없음") and boundary.text.contains("아군 거점에서만") and boundary.text.contains("G8-00"), "transfer, base-only reload, and authority boundaries are explicit")
	var forbidden := view.find_children("*", "Button", true, false).filter(func(node):
		var text := String(node.text); return text.contains("물자 이전") or text.contains("재적재") or text.contains("손상") or text.contains("파괴") or text.contains("나포"))
	_eq(forbidden.size(), 0, "no manual inventory, damage, destroy, or capture controls exist")
	var selectable: Button = view.find_child("Select_RC-LIU-SQ-01", true, false)
	if selectable != null: selectable.pressed.emit(); await _settle()
	_eq(view.find_children("SupplyInventoryTitle", "Label", true, false).size(), 1, "panel remains single after squadron selection changes")
	if DisplayServer.get_name() != "headless":
		var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false)
		if scroll != null:
			scroll.scroll_horizontal = 0
			scroll.scroll_vertical = 0
		await process_frame; await process_frame
		var output_dir := "res://out/demo-rc-g6-06-supply-inventory"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU image")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("supply-inventory-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _test_authoritative_event_text() -> void:
	var view := BattleView.new()
	var damaged := view._supply_inventory_event_text({"status":"status_applied","turn":2,"source_id":"SUPPLY_SHIP-RC-LIU-SQ-01","stock_before":{"fuel_basis_points":20000,"ammo_units":24,"supply_material_units":8},"stock_after":{"fuel_basis_points":10000,"ammo_units":12,"supply_material_units":4}})
	_ok(damaged.contains("손상·파괴 처리량 변경") and damaged.contains("통합 재고") and damaged.contains("파괴 비율만 손실"), "status event explains throughput-only damage and proportional destruction loss")
	var captured := view._supply_inventory_event_text({"status":"captured_discarded","turn":2,"source_id":"SUPPLY_SHIP-RC-LIU-SQ-01","before":{"fuel_basis_points":9000,"ammo_units":9,"supply_material_units":3},"after":{"fuel_basis_points":0,"ammo_units":0,"supply_material_units":0},"captor_gain":0})
	_ok(captured.contains("나포 즉시 폐기") and captured.contains("적 보급 기능·재고 획득 없음"), "capture event exposes discard and zero enemy gain")
	var reloaded := view._supply_inventory_event_text({"status":"base_reloaded","turn":3,"source_id":"SUPPLY_SHIP-RC-LIU-SQ-01","base_source_id":"RC-BASE-LIU-01","before":{"fuel_basis_points":1,"ammo_units":1,"supply_material_units":1},"after":{"fuel_basis_points":10000,"ammo_units":12,"supply_material_units":4}})
	_ok(reloaded.contains("거점 자동 재적재 완료") and reloaded.contains("연료 1 bp") and reloaded.contains("연료 10000 bp"), "reload event renders core before and after stock")
	view.free()

func _test_viewer_and_source_boundary() -> void:
	var battle = _battle()
	for viewer_id in ["liu_bei", "sun_quan", "cao_cao"]:
		var receipt: Dictionary = battle.viewer_supply_inventory(viewer_id)
		_ok(receipt.providers.all(func(row): return String(row.get("faction_id", "")) == viewer_id), "%s viewer receives no enemy exact provider row" % viewer_id)
	var view_source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
	_ok("viewer_supply_inventory" in view_source and "effective_throughput_basis_points_per_turn" in view_source and "available_capacity_squadrons_this_turn" in view_source and "ship_status_counts" in view_source and "effective_capacity_squadrons_per_turn" not in view_source, "UI consumes separated public throughput projection")
	_ok("_apply_authoritative_supply_ship_status" not in view_source and "apply_authoritative_status" not in view_source and "capture_source" not in view_source, "UI exposes no authoritative mutation path")
	_ok("Node3D" not in view_source and ".glb" not in view_source, "inventory presentation remains Control-based 2D")

func _settle() -> void:
	await process_frame
	await process_frame
