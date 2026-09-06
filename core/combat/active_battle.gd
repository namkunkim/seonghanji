class_name ActiveBattle
extends RefCounted

## G-10 slice 3 — the smallest replay-derived persistent battle contract.
##
## `SCN-03-E09-RED-CLIFF-01` is canonical: scenario Event 09 + fixed Red-Cliffs
## ordinal 01. It intentionally does not use a UI label, fleet choice, region owner,
## power ratio, diplomacy tier, or object address. This slice creates `pending` only.

const STATUS_PENDING: String = "pending"
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
## Reserved deterministic anchor for a later phase engine. It consumes no Rng stream.
var rng_anchor: String = ""

## Pending does not select forces or assign roles. Keep every participant surface
## explicitly empty until activation owns that decision.
var attacker_faction_id: String = ""
var defender_faction_id: String = ""
var attacker_fleet_ids: Array[String] = []
var defender_fleet_ids: Array[String] = []
var participant_roles: Dictionary = {}
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
		Rng._hash_string(rng_anchor),
		Rng._hash_string(attacker_faction_id),
		Rng._hash_string(defender_faction_id),
		attacker_fleet_ids.size(),
		defender_fleet_ids.size(),
		participant_roles.size(),
		1 if entry_available else 0,
	]
	for fleet_id in attacker_fleet_ids:
		values.append(Rng._hash_string(fleet_id))
	for fleet_id in defender_fleet_ids:
		values.append(Rng._hash_string(fleet_id))
	return values
