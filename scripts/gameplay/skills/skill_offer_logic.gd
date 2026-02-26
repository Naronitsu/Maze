extends RefCounted
class_name SkillOfferLogic

## Builds level-up skill offers: 2 from chosen stat pool, 1 synergy-weighted from any pool.
## Queries stats_component for stat levels and uses SkillManager for equipped skills' tags.

## Synergy bonus per matching tag (additive to base weight 1.0).
const SYNERGY_WEIGHT_PER_TAG: float = 0.6


## Returns 3 skill choices: 2 from chosen stat pool, 1 from any pool (synergy-weighted).
## Avoids duplicate skill_id and uses stats_component + equipped skills for weighting.
static func get_skill_choices(
	player: Node, chosen_stat: StringName, pool_by_stat: Dictionary, all_pools: Array
) -> Array[Dictionary]:
	var sm := player.get_node_or_null("SkillManager") as Node
	var stats := player.get_node_or_null("Stats") as Node
	if sm == null:
		return []

	# Query stats_component for current stat levels (e.g. to weight offers by investment later).
	# Example: stats.get_stat(&"Agility") -> 4; _stat_levels[&"Agility"] = 4
	var _stat_levels: Dictionary = _get_stat_levels(stats)

	var pool: SkillPool = pool_by_stat.get(chosen_stat, null)
	if pool == null and all_pools.is_empty():
		return []

	var equipped_tags: Array[StringName] = _collect_equipped_tags(sm)
	var chosen_ids: Array[StringName] = []
	var out: Array[Dictionary] = []

	# --- 2 from chosen stat's pool (rarity-weighted, no duplicate) ---
	var stat_pool_list: Array = []
	if pool != null:
		for def in pool.passives:
			if def == null:
				continue
			stat_pool_list.append(def)

	for _i in range(2):
		var choice_def: PassiveDef = _weighted_pick_one_passive(
			stat_pool_list, chosen_ids, equipped_tags, true
		)
		if choice_def == null:
			break
		chosen_ids.append(choice_def.id)
		out.append(_build_choice_dict(choice_def, sm))

	# --- 1 from any pool, synergy-weighted (exclude already chosen) ---
	var all_passives: Array = []
	for p in all_pools:
		if p == null:
			continue
		for def in p.passives:
			if def != null and not chosen_ids.has(def.id):
				all_passives.append(def)

	var synergy_def: PassiveDef = _weighted_pick_one_passive(
		all_passives, chosen_ids, equipped_tags, false
	)
	if synergy_def != null:
		out.append(_build_choice_dict(synergy_def, sm))

	return out


## Read stat levels from stats_component for optional weighting/display.
static func _get_stat_levels(stats: Node) -> Dictionary:
	var result: Dictionary = {}
	if stats == null or not stats.has_method("get_stat"):
		return result
	var names: Array[StringName] = [&"Agility", &"Perception", &"Focus", &"Resolve", &"Composure"]
	for k in names:
		result[k] = int(stats.get_stat(k))
	return result


## Collect all tags from currently equipped passives (for synergy weighting).
static func _collect_equipped_tags(skill_manager: Node) -> Array[StringName]:
	var tags: Array[StringName] = []
	if skill_manager == null:
		return tags
	if not "equipped_passives" in skill_manager:
		return tags
	var list = skill_manager.get("equipped_passives") as Array
	if list == null:
		return tags
	for def in list:
		if def == null:
			continue
		if "tags" in def:
			var t: Array = def.get("tags") as Array
			if t != null:
				for tag in t:
					if tag != null and tag not in tags:
						tags.append(tag as StringName)
	return tags


## Weight for a candidate def when picking the "synergy" slot (match equipped tags).
static func _synergy_weight(def: PassiveDef, equipped_tags: Array[StringName]) -> float:
	if def == null or equipped_tags.is_empty():
		return 1.0
	var w := 1.0
	for tag in def.tags:
		if tag in equipped_tags:
			w += SYNERGY_WEIGHT_PER_TAG
	return w


## Pick one passive from candidates, weighted by rarity (for stat pool) or synergy * rarity (for any pool).
## Excludes any def whose id is in exclude_ids. Removes the picked def from candidates in-place if remove_chosen.
static func _weighted_pick_one_passive(
	candidates: Array,
	exclude_ids: Array[StringName],
	equipped_tags: Array[StringName],
	use_rarity_only: bool
) -> PassiveDef:
	var weighted: Array[Dictionary] = []  # { def, weight }
	for def in candidates:
		if def == null:
			continue
		var d: PassiveDef = def as PassiveDef
		if d == null or d.id in exclude_ids:
			continue
		var rw := d.rarity_weight
		var w := rw
		if not use_rarity_only:
			w = rw * _synergy_weight(d, equipped_tags)
		weighted.append({"def": d, "weight": maxf(0.001, w)})
	if weighted.is_empty():
		return null
	var total := 0.0
	for x in weighted:
		total += x.weight
	var r := randf() * total
	for x in weighted:
		r -= x.weight
		if r <= 0.0:
			return x.def as PassiveDef
	return weighted.back().def as PassiveDef


static func _build_choice_dict(def: PassiveDef, skill_manager: Node) -> Dictionary:
	var id: StringName = def.id
	var owned := false
	var cur_level := 0
	if skill_manager != null:
		if "passive_instances" in skill_manager:
			owned = (skill_manager.passive_instances as Dictionary).has(id)
		if "levels" in skill_manager:
			cur_level = int((skill_manager.levels as Dictionary).get(id, 0))
	var label := def.display_name
	if owned:
		label = "%s (Upgrade → %d)" % [def.display_name, cur_level + 2]
	else:
		label = "%s (New)" % def.display_name
	return {"kind": "skill", "type": "passive", "skill_id": id, "def": def, "text": label}
