extends SceneTree

## 함대 이동 관측 상태의 독립 회귀 시험.
##
## 기존 홈 HUD 시험과 단위 시험 러너의 점유 구간을 건드리지 않기 위해 standalone으로
## 실행한다. 화면 통합 전에도 pending → moving → arrived/rejected 상태 계약과 비차단
## 시간 진행을 고정한다.

const Harness := preload("res://tests/harness.gd")
const FleetRouteContextScript := preload("res://app/views/fleet_route_context.gd")
const TacticalRouteViewScript := preload("res://app/views/tactical_route_view.gd")

var _pass := 0
var _fail := 0


func _ok(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  실패: ", label)


func _eq(got, wanted, label: String) -> void:
	_ok(got == wanted, "%s — 기대 %s, 실제 %s" % [label, str(wanted), str(got)])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("함대 이동 관측 전환 시험")
	var data := GameData.load_all()
	var campaign := Campaign.scenario_03(data, 906)
	campaign.world.player_faction = "손권"
	var fleet = _stationary_fleet(campaign, "손권")
	_ok(fleet != null, "손권 주둔 함대 확보")
	if fleet == null:
		_finish()
		return
	var composition: Dictionary = fleet.ships_by_kind()
	var composition_total := 0
	for kind in Economy.SHIP_KINDS:
		composition_total += int(composition.get(String(kind), 0))
	_eq(composition_total, fleet.ships, "함종별 결정론 배분의 합은 실제 총 척수")
	_eq(fleet.ships_by_kind(), composition, "함종별 배분은 같은 Fleet에서 결정론적")

	var destination_region := _reachable_destination(campaign, fleet.at_system)
	_ok(destination_region != "", "출발 성계와 다른 도달 가능 목적 권역 확보")
	if destination_region == "":
		_finish()
		return

	var resolution: Dictionary = Orders.resolve_move(
		campaign.world.graph, data, fleet.at_system, destination_region)
	var issued_tick := int(campaign.world.clock.tick)
	var command: Dictionary = campaign.world.issue(Domestic.CMD_FLEET_MOVE, {
		"faction": fleet.owner,
		"fleet": fleet.id,
		"region": destination_region,
	}, 0)
	var pending_input := {
		"command_seq": int(command["seq"]),
		"from_system": String(fleet.at_system),
		"dest_region": destination_region,
		"issued_tick": issued_tick,
		"estimated_arrival_tick": issued_tick + maxi(int(resolution["travel_ticks"]), 1),
	}

	# 발행 직후에는 명령만 대기한다. 코어가 적용하기 전에 이동 성공으로 보이면 안 된다.
	var pending = FleetRouteContextScript.from_campaign(campaign, fleet.id, pending_input)
	var pending_state: Dictionary = pending.snapshot()
	_eq(pending_state["status"], "pending", "발행 직후 pending")
	_ok(not fleet.is_moving(), "발행 직후 Fleet은 아직 이동 중이 아님")
	_eq(pending_state["fleet_id"], fleet.id, "pending 함대 ID")
	_eq(pending_state["origin_system"], fleet.at_system, "pending 출발 성계")
	_eq(pending_state["destination_region"], destination_region, "pending 목적 권역")
	_eq(pending_state["path"], resolution["path"], "pending 경로는 코어 판정값")
	_eq(pending_state["corridors"], resolution["corridor_ids"], "pending 회랑은 코어 판정값")
	_eq(pending_state["terrain"], resolution["terrain"], "pending 지형은 코어 판정값")
	_ok(not pending_state.has("progress") and not pending_state.has("progress_ratio"),
		"출발 tick 없이 정확 진행률을 발명하지 않음")
	_ok(not (String(pending_state["origin_name"]) == "형주" \
		and String(pending_state["destination_name"]) == "오회"),
		"데모의 형주→오회 고정 경로가 아님")

	var view = TacticalRouteViewScript.new()
	view.size = Vector2(1280, 720)
	root.add_child(view)
	await process_frame
	view.setup(data, campaign)
	view.open_fleet(fleet.id, pending_input)
	var view_pending: Dictionary = view.get("_context").duplicate(true)
	_ok(view.visible, "open_fleet이 관측 화면 표시")
	_eq(view_pending["status"], "pending", "관측 화면도 pending 표시")
	_eq(view_pending["origin_name"], pending_state["origin_name"],
		"관측 화면 출발지는 DTO 값")
	_eq(view_pending["destination_name"], pending_state["destination_name"],
		"관측 화면 목적지는 DTO 값")
	_ok(not bool(view.call("_has_battle_data")), "일반 이동에는 전투 패널 데이터 없음")
	_eq(view.mouse_filter, Control.MOUSE_FILTER_STOP,
		"항로 관측은 뒤의 홈 지도 입력을 차단")
	var commands_before_view_input := campaign.world.pending_commands.size()
	var applied_before_view_input := campaign.world.applied_commands.size()
	var passive_click := InputEventMouseButton.new()
	passive_click.button_index = MOUSE_BUTTON_LEFT
	passive_click.pressed = true
	passive_click.position = Vector2(12, view.size.y - 12)
	view.call("_gui_input", passive_click)
	_ok(view.visible, "닫기 영역 밖 클릭은 관측 화면을 유지")
	_eq(campaign.world.pending_commands.size(), commands_before_view_input,
		"관측 화면 클릭은 pending 이동 명령을 발행하지 않음")
	_eq(campaign.world.applied_commands.size(), applied_before_view_input,
		"관측 화면 클릭은 적용 명령을 만들지 않음")
	_ok(not fleet.is_moving(), "관측 화면 클릭은 다음 tick 전 함대 상태를 바꾸지 않음")

	# 다음 tick에 명령이 적용되면 실제 Fleet 상태가 화면 계약의 권위가 된다.
	campaign.step()
	_ok(fleet.is_moving(), "다음 tick에 함대 이동 적용")
	_eq(fleet.departure_tick, int(campaign.world.clock.tick),
		"적용 tick을 실제 Fleet 출항 tick으로 기록")
	var moving = FleetRouteContextScript.from_campaign(campaign, fleet.id, pending_input)
	var moving_state: Dictionary = moving.snapshot()
	_eq(moving_state["status"], "moving", "적용 뒤 moving")
	_eq(moving_state["arrival_tick"], fleet.arrival_tick, "실제 Fleet 도착 tick 사용")
	_eq(moving_state["remaining_ticks"],
		fleet.arrival_tick - campaign.world.clock.tick, "moving 남은 tick")
	_eq(moving_state["path"], resolution["path"], "moving 경로도 같은 코어 판정값")
	view.refresh()
	_eq(String((view.get("_context") as Dictionary)["status"]), "moving",
		"관측 화면 refresh가 pending에서 moving으로 전환")

	var before_remaining := int(moving_state["remaining_ticks"])
	campaign.world.clock.step_ticks(1)
	var refreshed_state: Dictionary = FleetRouteContextScript.from_campaign(
		campaign, fleet.id, pending_input).snapshot()
	_eq(refreshed_state["remaining_ticks"], before_remaining - 1,
		"시계가 한 tick 진행하면 remaining도 1 감소")
	view.refresh()
	_eq(int((view.get("_context") as Dictionary)["remaining_ticks"]),
		before_remaining - 1, "관측 화면 remaining 갱신")

	# DTO/관측 화면을 열어 둔 사실은 Campaign 시계를 멈추지 않는다.
	var tick_before_advance := int(campaign.world.clock.tick)
	var paused_before := bool(campaign.world.clock.paused)
	var tree_paused_before := paused
	var time_scale_before := Engine.time_scale
	var held_context = FleetRouteContextScript.from_campaign(campaign, fleet.id, pending_input)
	_eq(campaign.advance(GameClock.REAL_MS_PER_TICK), 1, "관측 중에도 x1 한 tick 진행")
	_eq(campaign.world.clock.tick, tick_before_advance + 1, "관측 중 Campaign tick 증가")
	_eq(campaign.world.clock.paused, paused_before, "관측이 Campaign pause를 바꾸지 않음")
	_eq(paused, tree_paused_before, "관측이 SceneTree pause를 바꾸지 않음")
	_ok(is_equal_approx(Engine.time_scale, time_scale_before),
		"관측이 Engine time_scale을 바꾸지 않음")
	_ok(held_context != null, "시간 진행 중 관측 컨텍스트 유지")
	view.refresh()
	_eq(int((view.get("_context") as Dictionary)["remaining_ticks"]),
		before_remaining - 2, "열린 관측 화면은 시간 진행 후 최신 remaining 표시")
	var closed_ids: Array[int] = []
	view.closed.connect(func(closed_id: int): closed_ids.append(closed_id))
	view.call("_close")
	_ok(not view.visible, "관측 화면 닫기")
	_eq(closed_ids, [fleet.id], "closed 신호가 닫힌 함대 ID 전달")

	# 적용된 명령의 목적 성계에 도착한 상태는 같은 command_seq로 arrived가 된다.
	var destination_system := String(moving_state["destination_system"])
	fleet.at_system = destination_system
	fleet.target_region = ""
	fleet.arrival_tick = -1
	fleet.departure_tick = -1
	var arrived_state: Dictionary = FleetRouteContextScript.from_campaign(
		campaign, fleet.id, pending_input).snapshot()
	_eq(arrived_state["status"], "arrived", "적용 명령 목적 성계 도착")
	_eq(arrived_state["remaining_ticks"], 0, "도착 뒤 remaining 0")
	_eq(fleet.departure_tick, -1, "도착 함대는 출항 tick을 보유하지 않음")

	var rejected_input: Dictionary = pending_input.duplicate(true)
	rejected_input["status"] = "rejected"
	rejected_input["error"] = "시험 거부"
	var rejected_state: Dictionary = FleetRouteContextScript.from_campaign(
		campaign, fleet.id, rejected_input).snapshot()
	_eq(rejected_state["status"], "rejected", "명시적 거부 상태")
	_eq(rejected_state["error"], "시험 거부", "거부 이유 보존")

	var invalid_state: Dictionary = FleetRouteContextScript.from_campaign(
		campaign, 999999, {}).snapshot()
	_eq(invalid_state["status"], "unavailable", "없는 함대 unavailable")
	_ok(String(invalid_state["error"]) != "", "없는 함대 오류 이유")
	view.open_fleet(999999)
	_eq(String((view.get("_context") as Dictionary)["status"]), "unavailable",
		"관측 화면도 없는 함대 unavailable")

	var dead_campaign := Campaign.scenario_03(data, 907)
	dead_campaign.world.player_faction = "손권"
	var dead_fleet = _stationary_fleet(dead_campaign, "손권")
	_ok(dead_fleet != null, "사망 함대 시험 대상 확보")
	if dead_fleet != null:
		var dead_destination := _reachable_destination(dead_campaign, dead_fleet.at_system)
		dead_fleet.ships = 0
		var dead_state: Dictionary = FleetRouteContextScript.from_campaign(
			dead_campaign, dead_fleet.id, {
				"from_system": dead_fleet.at_system,
				"dest_region": dead_destination,
				"status": "pending",
			}).snapshot()
		_eq(dead_state["status"], "unavailable", "사망 함대 관측 차단")
		view.setup(data, dead_campaign)
		view.open_fleet(dead_fleet.id, {
			"from_system": dead_fleet.at_system,
			"dest_region": dead_destination,
			"status": "pending",
		})
		_eq(String((view.get("_context") as Dictionary)["status"]), "unavailable",
			"관측 화면도 사망 함대 차단")

	# snapshot 반환값은 깊은 복사라 화면의 가공이 다음 갱신을 오염시키지 않는다.
	var leaked: Dictionary = moving.snapshot()
	leaked["path"].clear()
	_ok(not moving.snapshot()["path"].is_empty(), "관측 snapshot 깊은 복사")
	view.free()

	_finish()


func _stationary_fleet(campaign, owner: String):
	for fleet in campaign.fleets:
		if fleet.owner == owner and fleet.is_alive() and not fleet.is_moving():
			return fleet
	return null


func _reachable_destination(campaign, from_system: String) -> String:
	var region_ids: Array = campaign.data.region_ids.duplicate()
	region_ids.sort()
	for region_id in region_ids:
		var rid := String(region_id)
		var resolved: Dictionary = Orders.resolve_move(
			campaign.world.graph, campaign.data, from_system, rid)
		if bool(resolved.get("ok", false)) \
				and String(resolved.get("dest_system", "")) != from_system \
				and int(resolved.get("travel_ticks", -1)) > 2:
			return rid
	return ""


func _finish() -> void:
	print("FleetRouteTransition: %d 통과 / %d 실패" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)
