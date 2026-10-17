extends RefCounted
## Native feature: no mod bootstrap, external helper, route ownership or credentials store.
const Policy = preload("res://src/ai/tuning/ProfilePolicy.gd")
const Identity = preload("res://src/ai/tuning/Identity.gd")
const PathsScript = preload("res://src/save/Paths.gd")
const SETTING := "ai_tuning_profiles"

static func from_settings(settings: Dictionary, base: String, model: String) -> Dictionary:
	var key: String = Identity.key(base,model)
	var records: Variant = settings.get(SETTING,{})
	var record: Variant = records.get(key,{}) if records is Dictionary else {}
	if key != "" and record is Dictionary and record.get("base") == Identity.base_url(base) and record.get("model") == model.strip_edges() and record.get("profile") is Dictionary:
		var checked: Dictionary = Policy.validate(record.profile)
		if checked.ok: return checked.profile
	return Policy.validate({}).profile

static func current(base: String, model: String) -> Dictionary:
	return from_settings(PathsScript.settings(),base,model)

static func update(settings: Dictionary, base: String, model: String, profile: Dictionary, reset: bool = false) -> Dictionary:
	var key: String = Identity.key(base,model)
	if key == "": return {"ok":false,"errors":["profile: invalid public endpoint/model."]}
	var checked: Dictionary = Policy.validate(profile)
	if not checked.ok: return checked
	var records: Dictionary = {}
	var original: Variant = settings.get(SETTING,{})
	if original is Dictionary:
		for id: Variant in original:
			var row: Variant = original[id]
			if not row is Dictionary or not row.get("base") is String or not row.get("model") is String or not row.get("profile") is Dictionary: continue
			if id != Identity.key(row.base,row.model) or id == "": continue
			var valid: Dictionary = Policy.validate(row.profile)
			if valid.ok: records[id] = {"base":Identity.base_url(row.base),"model":row.model.strip_edges(),"profile":valid.profile}
	if reset: records.erase(key)
	else:
		if not records.has(key) and records.size() >= 256: return {"ok":false,"errors":["profiles: at most 256 endpoint/model profiles may be saved."]}
		records[key] = {"base":Identity.base_url(base),"model":model.strip_edges(),"profile":checked.profile}
	# Mutate only our own generation section; no copy of native credentials is made.
	settings[SETTING] = records
	return {"ok":true,"errors":[]}

static func output_limit(profile: Dictionary, fallback: int, small_request: bool = false) -> int:
	var manual: int = Policy.output_budget(profile,fallback)
	return mini(manual,fallback) if small_request else manual

static func hook_limit(profile: Dictionary, requested: int) -> int:
	var manual: int = Policy.output_budget(profile,0)
	return mini(manual,clampi(requested,1,Policy.MAX_TOKENS)) if manual > 0 else clampi(requested,16,64000)

static func timeout(profile: Dictionary, fallback: float) -> float:
	var checked: Dictionary = Policy.validate(profile)
	if checked.ok and checked.profile.enabled and checked.profile.timeout_seconds > 0: return float(checked.profile.timeout_seconds)
	return fallback

static func apply_query(query: Array, profile: Dictionary, reserved_budget: int) -> Dictionary:
	var checked: Dictionary = Policy.validate(profile)
	if not checked.ok: return {"ok":false,"query":query.duplicate(true),"errors":checked.errors}
	var clean: Dictionary = checked.profile
	# The fit/queue caller already owns the reservation. A profile change may lower
	# this allowance, but never raise it after fitting or on a service/child request.
	var manual: int = Policy.output_budget(clean,0)
	if clean.enabled and manual > 0 and reserved_budget > 0:
		clean.max_output_tokens = mini(manual,reserved_budget)
		var fields: Array = Policy._existing(clean.extra,Policy.BUDGET_PATHS)
		for field: String in fields: Policy._set(clean.extra,field,clean.max_output_tokens)
		if clean.token_field == "auto" and fields.size() == 1 and fields[0] in Policy.TOKEN_FIELDS: clean.token_field = fields[0]
	return Policy.apply(query,clean)

static func input_guard(system: String, user: String, dossier: String, output: int, context: int) -> Dictionary:
	var need: int = ceili(float(system.length()+user.length()+dossier.length())/2.0)+output+1024
	return {"ok":context > 0 and need <= context,"errors":[] if context > 0 and need <= context else ["Full input plus reserved output exceeds the selected context window; increase context or lower output/input. No clipped request was sent."]}

static func query_budget(query: Array, fallback: int) -> int:
	if query.size() != 3 or not query[2] is Dictionary: return fallback
	var fields: Array = Policy._existing(query[2],Policy.BUDGET_PATHS)
	return int(Policy._get(query[2],fields[0])) if fields.size() == 1 else fallback

static func error_body(errors: Array, code: String = "generation_settings_invalid") -> PackedByteArray:
	return JSON.stringify({"error":{"type":"invalid_request_error","code":code,"message":"; ".join(PackedStringArray(errors.slice(0,8))).left(2000)}}).to_utf8_buffer()
