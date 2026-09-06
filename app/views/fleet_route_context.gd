class_name FleetRouteContext
extends RefCounted

## 함대 이동 관측 화면이 읽는 비변이 DTO다.
##
## 이동 경로와 지형은 UI가 받은 값을 믿지 않고 항상 `Orders.resolve_move`로
## 다시 판정한다. `pending_context`는 아직 다음 틱에 적용되지 않은 발행 명령을
## 식별하고, 적용 결과가 나온 뒤에도 도착/거부 상태를 이어 보는 데만 쓴다.
##
## 이 객체는 정확한 진행률을 만들지 않는다. 현재 `Fleet`에는 출항 틱이 없어서
## 도착 틱만으로 진행률을 역산하면 항로 변경 시 틀린 사실을 표시할 수 있다.

const SCHEMA_VERSION := 1

const STATUS_PENDING := "pending"
const STATUS_MOVING := "moving"
const STATUS_ARRIVED := "arrived"
const STATUS_REJECTED := "rejected"
const STATUS_UNAVAILABLE := "unavailable"

var _state: Dictionary = {}


## `pending_context` 권장 키:
##   command_seq, from_system, dest_region, issued_tick, estimated_arrival_tick
## `World.issue()` 반환값도 받는다(seq와 payload.region을 안전하게 펼쳐 읽는다).
## 결과를 받은 호출자는 status="rejected"/"arrived"와 error를 덧붙일 수 있다.
static func from_campaign(campaign, fleet_id: int,
		pending_context: Dictionary = {}) -> FleetRouteContext:
	var out := FleetRouteContext.new()
	out._state = _empty_state(fleet_id)

	if campaign == null:
		out._unavailable("캠페인이 없다")
		return out
	if campaign.world == null:
		out._unavailable("월드가 없다")
		return out
	if campaign.data == null:
		out._unavailable("게임 데이터가 없다")
		return out

	var fleet = _find_fleet(campaign.fleets, fleet_id)
	if fleet == null:
		out._unavailable("함대를 찾을 수 없다: %d" % fleet_id)
		return out
	if not fleet.is_alive():
		out._unavailable("소실된 함대는 이동을 관측할 수 없다: %d" % fleet_id)
		return out

	out._state["formation"] = String(fleet.formation)
	var moving: bool = bool(fleet.is_moving())
	out._state["departure_tick"] = int(fleet.departure_tick) if moving else int(
		pending_context.get("issued_tick", -1))
	var command_payload: Dictionary = pending_context.get("payload", {})
	var origin_system := String(fleet.at_system) if moving else String(
		pending_context.get("from_system",
			pending_context.get("origin_system", fleet.at_system)))
	var destination_region := String(fleet.target_region) if moving else String(
		pending_context.get("dest_region",
			pending_context.get("destination_region",
				pending_context.get("region", command_payload.get("region", "")))))
	out._set_endpoints(campaign.data, origin_system, destination_region)

	var requested_status := String(pending_context.get("status", ""))
	if destination_region == "":
		if requested_status == STATUS_REJECTED or bool(pending_context.get("rejected", false)):
			out._reject(_context_error(pending_context, "이동 명령이 거부되었다"))
		else:
			out._unavailable("이동 중인 함대가 아니며 관측할 발행 명령도 없다")
		return out

	var resolution: Dictionary = Orders.resolve_move(
		campaign.world.graph, campaign.data, origin_system, destination_region)
	if bool(resolution.get("ok", false)):
		out._state["destination_system"] = String(resolution.get(
			"dest_system", out._state["destination_system"]))
		out._state["destination_name"] = campaign.data.system_name(
			String(out._state["destination_system"]))
		out._state["path"] = (resolution.get("path", []) as Array).duplicate(true)
		out._state["corridors"] = (resolution.get("corridor_ids", []) as Array).duplicate(true)
		out._state["terrain"] = String(resolution.get("terrain", ""))
	else:
		out._state["error"] = String(resolution.get("reason", "이동 경로를 판정할 수 없다"))

	if moving:
		out._state["status"] = STATUS_MOVING
		out._state["arrival_tick"] = int(fleet.arrival_tick)
		out._state["remaining_ticks"] = maxi(
			0, int(fleet.arrival_tick) - int(campaign.world.clock.tick))
		return out

	if requested_status == STATUS_REJECTED or bool(pending_context.get("rejected", false)):
		out._reject(_context_error(pending_context, String(out._state["error"])))
		return out
	if not bool(resolution.get("ok", false)):
		out._reject(String(out._state["error"]))
		return out

	out._set_estimated_arrival(campaign, pending_context,
		int(resolution.get("travel_ticks", -1)))
	if requested_status == STATUS_ARRIVED:
		out._arrive()
		return out
	if requested_status == STATUS_UNAVAILABLE:
		out._unavailable(_context_error(pending_context, "이동 상태를 관측할 수 없다"))
		return out

	if pending_context.is_empty():
		out._unavailable("이동 중인 함대가 아니며 관측할 발행 명령도 없다")
		return out

	var command_seq := int(pending_context.get("command_seq",
		pending_context.get("seq", -1)))
	if _has_command(campaign.world.pending_commands, command_seq):
		out._state["status"] = STATUS_PENDING
		return out

	if _has_command(campaign.world.applied_commands, command_seq):
		if String(fleet.at_system) == String(out._state["destination_system"]):
			out._arrive()
		else:
			out._reject(_context_error(pending_context,
				"이동 명령이 적용되지 않았거나 거부되었다"))
		return out

	# 발행 직후 호출자가 아직 command_seq를 보관하지 못한 경우에도 미리보기는
	# 안전하게 pending으로 남긴다. 코어 적용 결과가 들어오면 새 DTO를 만든다.
	if requested_status == STATUS_PENDING or command_seq < 0:
		out._state["status"] = STATUS_PENDING
		return out

	if String(fleet.at_system) == String(out._state["destination_system"]) \
			and int(out._state["arrival_tick"]) >= 0 \
			and int(campaign.world.clock.tick) >= int(out._state["arrival_tick"]):
		out._arrive()
	else:
		out._reject(_context_error(pending_context, "이동 명령의 현재 상태를 확인할 수 없다"))
	return out


## 전체 계약의 깊은 복사본. UI가 반환값을 바꿔도 다음 갱신에는 영향이 없다.
func snapshot() -> Dictionary:
	return _state.duplicate(true)


func status() -> String:
	return String(_state.get("status", STATUS_UNAVAILABLE))


func is_available() -> bool:
	return status() != STATUS_UNAVAILABLE


static func _empty_state(fleet_id: int) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"status": STATUS_UNAVAILABLE,
		"fleet_id": fleet_id,
		"origin_system": "",
		"origin_name": "",
		"destination_region": "",
		"destination_region_name": "",
		"destination_system": "",
		"destination_name": "",
		"arrival_tick": -1,
		"departure_tick": -1,
		"remaining_ticks": -1,
		"path": [],
		"corridors": [],
		"terrain": "",
		"formation": "",
		"error": "",
	}


static func _find_fleet(fleets: Array, fleet_id: int):
	for fleet in fleets:
		if fleet != null and int(fleet.id) == fleet_id:
			return fleet
	return null


static func _has_command(commands: Array[Dictionary], command_seq: int) -> bool:
	if command_seq < 0:
		return false
	for command in commands:
		if int(command.get("seq", -1)) == command_seq:
			return true
	return false


static func _context_error(context: Dictionary, fallback: String) -> String:
	var message := String(context.get("error", context.get("reason", fallback)))
	return message if message != "" else fallback


func _set_endpoints(data: GameData, origin_system: String,
		destination_region: String) -> void:
	_state["origin_system"] = origin_system
	_state["origin_name"] = data.system_name(origin_system) if origin_system != "" else ""
	_state["destination_region"] = destination_region
	if destination_region != "" and data.regions.has(destination_region):
		_state["destination_region_name"] = String(
			data.regions[destination_region].get("name", destination_region))
		_state["destination_system"] = data.system_of(destination_region)
		_state["destination_name"] = data.system_name(
			String(_state["destination_system"]))


func _set_estimated_arrival(campaign, context: Dictionary,
		travel_ticks: int) -> void:
	var arrival := int(context.get("estimated_arrival_tick",
		context.get("expected_arrival_tick",
			context.get("route_arrival_tick", -1))))
	if arrival < 0 and travel_ticks >= 0:
		var issued_tick := int(context.get("issued_tick", campaign.world.clock.tick))
		arrival = issued_tick + maxi(travel_ticks, 1)
	_state["arrival_tick"] = arrival
	_state["remaining_ticks"] = maxi(
		0, arrival - int(campaign.world.clock.tick)) if arrival >= 0 else -1


func _unavailable(message: String) -> void:
	_state["status"] = STATUS_UNAVAILABLE
	_state["error"] = message


func _reject(message: String) -> void:
	_state["status"] = STATUS_REJECTED
	_state["arrival_tick"] = -1
	_state["remaining_ticks"] = -1
	_state["error"] = message if message != "" else "이동 명령이 거부되었다"


func _arrive() -> void:
	_state["status"] = STATUS_ARRIVED
	_state["remaining_ticks"] = 0
