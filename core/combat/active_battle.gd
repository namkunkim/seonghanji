class_name ActiveBattle
extends RefCounted

## G-10 slice 3 — the smallest replay-derived persistent battle contract.
##
## `SCN-03-E09-RED-CLIFF-01` is canonical: scenario Event 09 + fixed Red-Cliffs
## ordinal 01. It intentionally does not use a UI label, fleet choice, region owner,
## power ratio, diplomacy tier, or object address. This slice creates `pending` only.

const STATUS_PENDING: String = "pending"
const STATUS_ACTIVE: String = "active"
const STATUS_RESOLVED: String = "resolved"
const STATUS_CANCELLED: String = "cancelled"
const RED_CLIFF_REGION_ID: String = "RGN-04"
const RED_CLIFF_SYSTEM_ID: String = "SYS-13"
## Canonical map-body identity for the display anchor named 구지 (Guji).
const RED_CLIFF_ANCHOR_BODY_ID: String = "BODY-RGN-04-01"

var battle_id: String = ""
var cause_event_id: String = ""
var scenario_id: String = "SCN-03"
var status: String = STATUS_PENDING

## Authority location is fixed by the approved scenario contract. Guji is a display
## anchor only; neither field is a region-ownership precondition.
var region_id: String = RED_CLIFF_REGION_ID
var system_id: String = RED_CLIFF_SYSTEM_ID
var anchor_body_id: String = RED_CLIFF_ANCHOR_BODY_ID

var created_tick: int = 0
## Undefined while pending.  The phase engine is intentionally out of this slice;
## activation merely establishes its deterministic first phase.
var started_tick: int = -1
var campaign_stage: int = 0
var combat_phase: int = -1
## The first narrow active slice advances Contact (1) to Barrage (2) on the next
## campaign tick.  A later battle engine owns phases 3–5; it must not rewrite this
## recorded transition.
var phase_advanced_tick: int = -1
var resolved_tick: int = -1
## Result is deliberately a small, canonical player-input fact.  It is not a
## hidden combat calculation or a UI snapshot: the campaign reducer applies it
## once after phase 2 and replay derives the same resolved record from the log.
var result: Dictionary = {}
var result_applied: bool = false
var cancelled_tick: int = -1
var cancellation_reason: String = ""
## Reserved deterministic anchor for a later phase engine. It consumes no Rng stream.
var rng_anchor: String = ""

## Pending does not select forces or assign roles. Keep every participant surface
## explicitly empty until activation owns that decision.
var attacker_faction_id: String = ""
var defender_faction_id: String = ""
var attacker_fleet_ids: Array[String] = []
var defender_fleet_ids: Array[String] = []
var participant_roles: Dictionary = {}
## A scenario participant, not a general faction or Fleet.  It never enters fleet
## arrival checks and exists only when the approved Event 07 manifest says so.
var liu_contingent_id: String = ""
var entry_available: bool = false


static func red_cliff_pending(created_at_tick: int, canonical_id: String,
		cause_id: String) -> ActiveBattle:
	var battle := ActiveBattle.new()
	battle.battle_id = canonical_id
	battle.cause_event_id = cause_id
	battle.created_tick = created_at_tick
	battle.rng_anchor = "%d|%s" % [created_at_tick, canonical_id]
	battle._normalize_pending_identity()
	return battle


func _normalize_pending_identity() -> void:
	attacker_fleet_ids.sort()
	defender_fleet_ids.sort()
	# A pending record may not smuggle participant assignments through an arbitrary map.
	participant_roles.clear()
	attacker_faction_id = ""
	defender_faction_id = ""
	entry_available = false
	status = STATUS_PENDING
	started_tick = -1
	campaign_stage = 0
	combat_phase = -1
	phase_advanced_tick = -1
	resolved_tick = -1
	result.clear()
	result_applied = false
	cancelled_tick = -1
	cancellation_reason = ""
	liu_contingent_id = ""


func activate_red_cliff(attacker_ids: Array[String], defender_ids: Array[String],
		roles: Dictionary, contingent_id: String, at_tick: int) -> void:
	if status != STATUS_PENDING:
		return
	attacker_fleet_ids = attacker_ids.duplicate()
	defender_fleet_ids = defender_ids.duplicate()
	attacker_fleet_ids.sort()
	defender_fleet_ids.sort()
	participant_roles = roles.duplicate(true)
	attacker_faction_id = "cao_side"
	defender_faction_id = "sun_liu_side"
	liu_contingent_id = contingent_id
	started_tick = at_tick
	campaign_stage = 7
	combat_phase = 1
	phase_advanced_tick = -1
	resolved_tick = -1
	result.clear()
	result_applied = false
	cancelled_tick = -1
	cancellation_reason = ""
	entry_available = true
	status = STATUS_ACTIVE


func cancel_pending(at_tick: int, reason: String) -> void:
	if status != STATUS_PENDING:
		return
	cancelled_tick = at_tick
	cancellation_reason = reason
	entry_available = false
	status = STATUS_CANCELLED


## Contact is visible for the activation tick only.  This is a deterministic
## state transition, not a command and it consumes no RNG.
func advance_red_cliff_phase(at_tick: int) -> bool:
	if status != STATUS_ACTIVE or combat_phase != 1 or at_tick <= started_tick:
		return false
	combat_phase = 2
	phase_advanced_tick = at_tick
	return true


func resolve_red_cliff(winner_faction_id: String, at_tick: int) -> bool:
	if status != STATUS_ACTIVE or combat_phase != 2 or result_applied:
		return false
	if winner_faction_id != "cao_side" and winner_faction_id != "sun_liu_side":
		return false
	result = {"winner_faction_id": winner_faction_id}
	result_applied = true
	resolved_tick = at_tick
	entry_available = false
	status = STATUS_RESOLVED
	return true


## Ordered scalar values only: Campaign.digest owns the hash and avoids Dictionary order.
func digest_values() -> Array:
	var values: Array = [
		Rng._hash_string(battle_id),
		Rng._hash_string(cause_event_id),
		Rng._hash_string(scenario_id),
		Rng._hash_string(status),
		Rng._hash_string(region_id),
		Rng._hash_string(system_id),
		Rng._hash_string(anchor_body_id),
		created_tick,
		started_tick,
		campaign_stage,
		combat_phase,
		phase_advanced_tick,
		resolved_tick,
		1 if result_applied else 0,
		Rng._hash_string(String(result.get("winner_faction_id", ""))),
		cancelled_tick,
		Rng._hash_string(cancellation_reason),
		Rng._hash_string(rng_anchor),
		Rng._hash_string(attacker_faction_id),
		Rng._hash_string(defender_faction_id),
		attacker_fleet_ids.size(),
		defender_fleet_ids.size(),
		participant_roles.size(),
		Rng._hash_string(liu_contingent_id),
		1 if entry_available else 0,
	]
	for fleet_id in attacker_fleet_ids:
		values.append(Rng._hash_string(fleet_id))
	for fleet_id in defender_fleet_ids:
		values.append(Rng._hash_string(fleet_id))
	var role_ids: Array = participant_roles.keys()
	role_ids.sort()
	for fleet_id in role_ids:
		values.append(Rng._hash_string(String(fleet_id)))
		values.append(Rng._hash_string(String(participant_roles[fleet_id])))
	return values
