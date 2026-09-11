extends SceneTree

## DEMO-RC-G6-03 — 자동 보급 영역·한 턴 정박·처리량·결정론적 우선순위 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const FastCraft := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_formation.gd")
const CombatResources := preload("res://core/demo_red_cliffs/red_cliffs_combat_resources.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const BattleView := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G6-03 — 자동 보급 영역·한 턴 정박·처리량·결정론적 우선순위 UI")
	root.size = Vector2i(1600, 900)
	await _test_zone_queue_and_completion()
	await _test_movement_interruption()
	_test_actual_g4_refill_receipt()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail]); quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)

func _battle():
	var loaded := Setup.load_default(); _ok(loaded.ok, "default setup loads")
	var battle = Battle.new(); _ok(battle.initialize(loaded.setup).ok, "battle initializes"); return battle

func _view(battle):
	var view := BattleView.new(); _ok(view.configure(battle, 1, "g6-03-ui").ok, "battle view configures"); root.add_child(view); return view

func _test_zone_queue_and_completion() -> void:
	var battle = _battle(); var view = _view(battle); await _settle()
	var map = view.find_child("AppliedSquadronMap", true, false); var sources: Array = map.fast_craft_supply_sources_for_test()
	_ok(sources.any(func(row): return String(row.get("source_type", "")) == "supply_ship"), "map receives allied supply-ship zones")
	_ok(sources.any(func(row): return String(row.get("source_type", "")) == "carrier"), "map receives allied carrier zones")
	_ok(sources.any(func(row): return String(row.get("source_type", "")) == "friendly_base"), "map receives friendly base zones")
	_ok(sources.any(func(row): return String(row.get("faction_id", "")) == "sun_quan"), "Liu map includes mutual-allied Sun zones")
	_ok(not sources.any(func(row): return String(row.get("faction_id", "")) == "cao_cao"), "enemy supply zones stay private")
	var select: Button = view.find_child("Select_RC-LIU-FC-01", true, false); select.pressed.emit(); await _settle()
	var title: Label = view.find_child("FastCraftSupplyTitle", true, false); _ok(title != null and title.text.contains("자동 보급") and title.text.contains("수동 조작 없음"), "automatic-only supply contract is explicit")
	var state: Label = view.find_child("FastCraftSupplyState", true, false)
	_ok(state != null and state.text.contains("연료 6000/10000 bp") and not state.text.contains("탄약 6000/10000 bp"), "fuel uses supply receipt without an invented parallel ammo gauge")
	_ok(state.text.contains("진입 T1") and state.text.contains("연속 정박 0/1턴"), "queue entry and one-turn stationary progress are visible")
	_ok(state.text.contains("처리 순위 1") and state.text.contains("처리량 4 전대/턴"), "core priority rank and base throughput are visible")
	var priority: Label = view.find_child("FastCraftSupplyPriority", true, false); _ok(priority.text.contains("잔여 연료 낮은 순") and priority.text.contains("진입 턴 빠른 순") and priority.text.contains("전대 ID 오름차순"), "deterministic priority receipt is explained")
	var manual_buttons := view.find_children("*", "Button", true, false).filter(func(node): return String(node.text).contains("보급")); _eq(manual_buttons.size(), 0, "no manual supply button exists")
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g6-03-fast-craft-supply"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); await process_frame
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU image")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("fast-craft-supply-1600x900.png"))) == OK, "GPU capture saved")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok and battle.resolve_turn().ok, "turn resolves automatic supply"); view._refresh(); await _settle()
	var completed_state: Label = view.find_child("FastCraftSupplyState_RC-LIU-FC-01", true, false); _ok(completed_state != null and completed_state.text.contains("연료 10000/10000 bp"), "completion refills fuel only to displayed maximum")
	var completed: Label = view.find_child("FastCraftSupplyLatest_RC-LIU-FC-01", true, false); _ok(completed != null and completed.text.contains("보급 완료") and completed.text.contains("연료 +4000 bp") and completed.text.contains("실제 G4 유한 자원 반영"), "completion event distinguishes fuel from authoritative G4 finite resources")
	var completion: Dictionary = battle.viewer_fast_craft_supply("liu_bei").events.filter(func(row): return String(row.get("status", "")) == "completed")[0]
	_ok(completion.has("combat_resource_before") and completion.has("combat_resource_after") and completion.has("combat_resource_refill"), "viewer completion retains authoritative G4 refill receipt")
	_ok(battle.viewer_fast_craft_supply("cao_cao").resources.is_empty(), "enemy viewer receives no Liu resources or queue")
	view.free()

func _test_movement_interruption() -> void:
	var battle = _battle(); var view = _view(battle); await _settle()
	_ok(battle.set_order_move("RC-LIU-FC-01", [[800, 720]], 0).ok, "fast craft move order stages")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok and battle.resolve_turn().ok, "movement turn resolves"); view._refresh(); await _settle()
	var interrupted: Label = view.find_child("FastCraftSupplyLatest_RC-LIU-FC-01", true, false)
	_ok(interrupted != null and interrupted.text.contains("정박 중단") and interrupted.text.contains("영역 이탈"), "leaving supply zone displays interruption")
	var state: Label = view.find_child("FastCraftSupplyState_RC-LIU-FC-01", true, false); _ok(state != null and state.text.contains("자동 대기열 없음"), "interruption removes automatic queue")
	view.free()

func _test_actual_g4_refill_receipt() -> void:
	var loaded := Setup.load_default(); var formation = FastCraft.new(); _ok(formation.initialize(loaded.setup).ok, "finite-resource fixture initializes")
	_ok(formation.set_equipment("RC-LIU-FC-01", "FAST-EQ-TORPEDO").ok, "fixture applies torpedo equipment"); var applied: Dictionary = formation.apply(); _ok(applied.ok, "torpedo fixture applies")
	var resources = CombatResources.new(); _ok(resources.initialize(applied.applied_setup).ok, "G4 resource authority initializes")
	var state: Dictionary = resources.initial_state(); state["RC-LIU-FC-01"].weapons.torpedo.special = 1
	var refilled: Dictionary = resources.refill_fast_craft_finite(["RC-LIU-FC-01"], state, 1); _ok(refilled.ok, "G4 finite refill receipt resolves")
	var core_event: Dictionary = refilled.events[0].duplicate(true); core_event.merge({"status":"completed", "source_id":"RC-BASE-LIU-01", "fuel_granted_basis_points":4000}, true)
	var fixture_battle = Battle.new(); _ok(fixture_battle.initialize(applied.applied_setup).ok, "torpedo viewer authority initializes")
	var view := BattleView.new(); view.configure(fixture_battle, int(applied.formation_revision), String(applied.digest)); var text: String = view._fast_supply_event_text(core_event)
	_ok(text.contains("뇌격 특수 +11"), "UI renders exact G4 special refill delta from core receipt")
	_ok(not text.contains("탄약 +") or int(core_event.combat_resource_refill.torpedo.ammo_granted) > 0, "UI invents no finite ammo grant")
	view.free()

func _test_source_boundary() -> void:
	var map_source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_tactical_map.gd")
	var view_source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
	_ok("Node3D" not in map_source and ".glb" not in map_source and "Node3D" not in view_source, "supply presentation remains 2D only")
	_ok("viewer_fast_craft_supply" in view_source and "priority_rank" in view_source and "capacity_squadrons_per_turn" in view_source, "UI consumes core supply receipt without priority calculation")
	_ok("ammo_basis_points" not in view_source and "combat_resource_refill" in view_source and "own_combat_resources" in view_source, "finite ammo and special use authoritative G4 receipts only")
	_ok("ManualSupply" not in view_source and "request_resupply" not in view_source, "no manual supply mutation path exists")
	_ok("mission_success" not in view_source and "rescue_result" not in view_source and "capture_result" not in view_source, "G6-04+ outcomes are not implemented")

func _settle() -> void:
	await process_frame
	await process_frame
