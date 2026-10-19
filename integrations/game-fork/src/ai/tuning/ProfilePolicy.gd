extends RefCounted
## Pure, explicit generation preferences. No model/provider names or API I/O.
const MAX_TOKENS := 10000000
const MAX_EXTRA_BYTES := 65536
const DEFAULTS := {"enabled":false,"vision_input":false,"vision_mode":"auto","context_tokens":0,"max_output_tokens":0,"timeout_seconds":0,"token_field":"auto","reasoning":"","reasoning_field":"auto","verbosity":"","temperature":null,"top_p":null,"extra":{}}
const TOKEN_FIELDS := ["max_tokens","max_completion_tokens","max_output_tokens"]
const BUDGET_PATHS := ["max_tokens","max_completion_tokens","max_output_tokens","generationConfig.maxOutputTokens"]
const EFFORT_PATHS := ["reasoning_effort","reasoning.effort","output_config.effort"]
const GENERATION_GROUPS := [BUDGET_PATHS,EFFORT_PATHS,["verbosity","text.verbosity"],["temperature","generationConfig.temperature"],["top_p","generationConfig.topP"]]
const PROTECTED := ["model","models","messages","message","system","systeminstruction","system_instruction","instructions","instruction","input","inputs","contents","content","prompt","prompts","tools","tool","tool_choice","tool_calls","functions","function_call","parallel_tool_calls","stream","stream_options","auth","authorization","authentication","api_key","apikey","api_token","access_token","auth_token","token","key","secret","password","credentials","headers","header","cookies","url","uri","base_url","endpoint","host","port","path","proxy","route","provider","destination","method"]
const PROFILE_ONLY := ["vision_input","vision_mode"]

static func _integer(value: Variant, zero: bool = true) -> bool:
	return (value is int or value is float) and not value is bool and is_finite(float(value)) and value == floorf(float(value)) and value >= (0 if zero else 1) and value <= MAX_TOKENS

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and not value is bool and is_finite(float(value)) and value >= low and value <= high

static func _choice(value: Variant) -> bool:
	if not value is String or value.length() > 80 or value != value.strip_edges(): return false
	for character: String in value:
		if character.unicode_at(0) < 32 or character.unicode_at(0) == 127: return false
	return true

static func _extra_scan(value: Variant, path: String, depth: int, budget: Array, errors: Array) -> void:
	budget[0] += 1
	if depth > 8 or budget[0] > 2048:
		if not errors.has("extra: JSON exceeds depth 8 or 2048 values."): errors.append("extra: JSON exceeds depth 8 or 2048 values.")
		return
	if value is Dictionary:
		for key: Variant in value:
			if budget[0] > 2048 or errors.size() >= 20: break
			if not key is String or key.is_empty() or key.length() > 160:
				errors.append(path+": JSON keys must be nonempty strings up to 160 characters."); continue
			var protected := false
			var profile_only := false
			for part: String in key.to_lower().replace("-","_").split("."):
				if part in PROTECTED: protected = true
				if part in PROFILE_ONLY: profile_only = true
			if profile_only:
				errors.append(path+"."+key.left(80)+": profile metadata is not an API generation parameter."); continue
			if protected:
				errors.append(path+"."+key.left(80)+": routing, credentials, prompts, tools and streaming are protected."); continue
			_extra_scan(value[key],path+"."+key.left(80),depth+1,budget,errors)
	elif value is Array:
		for index: int in value.size():
			if budget[0] > 2048: break
			_extra_scan(value[index],path+"[%d]"%index,depth+1,budget,errors)
	elif value is float:
		if not is_finite(value): errors.append(path+": number must be finite.")
	elif value != null and not value is String and not value is bool and not value is int:
		errors.append(path+": only JSON data is allowed.")

static func _has(value: Dictionary, path: String) -> bool:
	var current: Variant = value
	for key: String in path.split("."):
		if not current is Dictionary or not current.has(key): return false
		current = current[key]
	return true

static func _get(value: Dictionary, path: String) -> Variant:
	var current: Variant = value
	for key: String in path.split("."): current = current[key]
	return current

static func _set(value: Dictionary, path: String, setting: Variant) -> void:
	var keys: PackedStringArray = path.split(".")
	var current: Dictionary = value
	for index: int in keys.size()-1:
		if not current.has(keys[index]): current[keys[index]] = {}
		current = current[keys[index]]
	current[keys[-1]] = setting

static func _erase(value: Dictionary, path: String) -> void:
	var keys: PackedStringArray = path.split(".")
	var current: Dictionary = value
	for index: int in keys.size()-1:
		if not current.get(keys[index]) is Dictionary: return
		current = current[keys[index]]
	current.erase(keys[-1])

static func _existing(value: Dictionary, paths: Array) -> Array:
	var found: Array = []
	for path: String in paths:
		if _has(value,path): found.append(path)
	return found

static func _controls(value: Dictionary, prefix: String, errors: Array) -> void:
	for container: String in ["reasoning","text","output_config","generationConfig"]:
		if value.has(container) and not value[container] is Dictionary: errors.append(prefix+"."+container+": expected native generation object.")
	var budgets: Array = _existing(value,BUDGET_PATHS)
	if budgets.size() > 1: errors.append(prefix+": conflicting generation token fields; choose one.")
	for path: String in budgets:
		if not _integer(_get(value,path),false): errors.append(prefix+"."+path+": output budget must be an integer from 1 to 10000000.")
	if _existing(value,EFFORT_PATHS).size() > 1: errors.append(prefix+": conflicting reasoning fields; choose one.")
	for path: String in EFFORT_PATHS+["verbosity","text.verbosity"]:
		if _has(value,path) and (not _choice(_get(value,path)) or _get(value,path) == ""): errors.append(prefix+"."+path+": choose a nonempty supported value.")
	if _has(value,"verbosity") and _has(value,"text.verbosity"): errors.append(prefix+": conflicting verbosity fields; choose one.")
	for path: String in ["temperature","generationConfig.temperature"]:
		if _has(value,path) and not _number(_get(value,path),0,2): errors.append(prefix+"."+path+": temperature must be 0..2.")
	for path: String in ["top_p","generationConfig.topP"]:
		if _has(value,path) and not _number(_get(value,path),0,1): errors.append(prefix+"."+path+": top_p must be 0..1.")
	for pair: Array in [["temperature","generationConfig.temperature"],["top_p","generationConfig.topP"]]:
		if _has(value,pair[0]) and _has(value,pair[1]): errors.append(prefix+": conflicting sampling fields; choose one protocol shape.")

static func validate(profile: Dictionary) -> Dictionary:
	var errors: Array = []
	for key: Variant in profile:
		if key not in DEFAULTS: errors.append("profile: unknown field; only generation preferences are accepted.")
	var clean: Dictionary = DEFAULTS.duplicate(true)
	for key: String in DEFAULTS:
		if profile.has(key): clean[key] = profile[key]
	if not clean.enabled is bool: errors.append("enabled: expected boolean.")
	if not clean.vision_input is bool: errors.append("vision_input: expected boolean.")
	if not profile.has("vision_mode"): clean.vision_mode="on" if clean.enabled==true and clean.vision_input==true else "auto"
	if clean.vision_mode not in ["auto","on","off"]:errors.append("vision_mode: choose auto, on or off.")
	clean.vision_input=clean.vision_mode=="on"
	for key: String in ["context_tokens","max_output_tokens"]:
		if not _integer(clean[key]): errors.append(key+": expected integer 0 (auto) through 10000000.")
		else: clean[key] = int(clean[key])
	if not _integer(clean.timeout_seconds) or clean.timeout_seconds > 3600: errors.append("timeout_seconds: expected integer 0 (auto) through 3600.")
	else: clean.timeout_seconds = int(clean.timeout_seconds)
	if clean.token_field not in ["auto"]+TOKEN_FIELDS: errors.append("token_field: choose auto, max_tokens, max_completion_tokens or max_output_tokens.")
	if clean.reasoning_field not in ["auto","reasoning_effort","reasoning.effort"]: errors.append("reasoning_field: choose auto, reasoning_effort or reasoning.effort.")
	for key: String in ["reasoning","verbosity"]:
		if not _choice(clean[key]): errors.append(key+": expected an exact supported value up to 80 characters, or empty for auto.")
	if clean.temperature != null and not _number(clean.temperature,0,2): errors.append("temperature: expected null (auto) or number 0..2.")
	if clean.top_p != null and not _number(clean.top_p,0,1): errors.append("top_p: expected null (auto) or number 0..1.")
	if not clean.extra is Dictionary: errors.append("extra: expected JSON object.")
	else:
		_extra_scan(clean.extra,"extra",0,[0],errors)
		if errors.is_empty() and JSON.stringify(clean.extra).to_utf8_buffer().size() > MAX_EXTRA_BYTES: errors.append("extra: JSON exceeds 65536 bytes.")
		if errors.is_empty():
			_controls(clean.extra,"extra",errors)
			var budgets: Array = _existing(clean.extra,BUDGET_PATHS)
			if budgets.size() == 1 and clean.max_output_tokens > 0 and _get(clean.extra,budgets[0]) != clean.max_output_tokens: errors.append("extra: output budget conflicts with max_output_tokens.")
	return {"ok":errors.is_empty(),"profile":clean.duplicate(true) if errors.is_empty() else {},"errors":errors.slice(0,20)}

static func output_budget(profile: Dictionary, fallback: int) -> int:
	var checked: Dictionary = validate(profile)
	if not checked.ok or not checked.profile.enabled: return fallback
	var clean: Dictionary = checked.profile
	if clean.max_output_tokens > 0: return int(clean.max_output_tokens)
	var fields: Array = _existing(clean.extra,BUDGET_PATHS)
	return int(_get(clean.extra,fields[0])) if fields.size() == 1 else fallback

static func _protect_path(fields: Array, path: String) -> void:
	var prefix := ""
	for key: String in path.split("."):
		prefix += ("." if prefix != "" else "")+key
		if not fields.has(prefix): fields.append(prefix)

static func _protect_extra(fields: Array, extra: Dictionary, prefix: String = "") -> void:
	for key: String in extra:
		var path: String = prefix+("." if prefix != "" else "")+key
		_protect_path(fields,path)
		if extra[key] is Dictionary: _protect_extra(fields,extra[key],path)

## API paths (including parent objects) recovery must not silently omit.
## Semantic auto fields protect every protocol alias; custom JSON protects its paths.
static func protected_generation_fields(profile: Dictionary) -> Array:
	var checked: Dictionary = validate(profile)
	if not checked.ok or not checked.profile.enabled: return []
	var clean: Dictionary = checked.profile
	var fields: Array = []
	var requested: Array = [clean.max_output_tokens > 0 or clean.token_field != "auto",clean.reasoning != "",clean.verbosity != "",clean.temperature != null,clean.top_p != null]
	for index: int in GENERATION_GROUPS.size():
		if requested[index] or not _existing(clean.extra,GENERATION_GROUPS[index]).is_empty():
			for path: String in GENERATION_GROUPS[index]: _protect_path(fields,path)
	_protect_extra(fields,clean.extra)
	return fields

static func _protocol(url: String, body: Dictionary) -> String:
	var path: String = url.get_slice("?",0).get_slice("#",0)
	if path.ends_with("/chat/completions") and body.get("messages") is Array: return "chat"
	if path.ends_with("/responses") and body.has("input"): return "responses"
	if path.ends_with("/messages") and body.get("messages") is Array: return "messages"
	if (path.ends_with(":generateContent") or path.ends_with(":streamGenerateContent")) and body.get("contents") is Array: return "gemini"
	return ""

static func _requested(profile: Dictionary) -> bool:
	return profile.max_output_tokens > 0 or profile.reasoning != "" or profile.verbosity != "" or profile.temperature != null or profile.top_p != null or not profile.extra.is_empty() or profile.token_field != "auto"

static func _merge(target: Dictionary, extra: Dictionary) -> void:
	for key: String in extra:
		if extra[key] is Dictionary and target.get(key) is Dictionary: _merge(target[key],extra[key])
		else: target[key] = extra[key].duplicate(true) if extra[key] is Dictionary or extra[key] is Array else extra[key]

static func _failure(query: Array, errors: Array) -> Dictionary:
	return {"ok":false,"query":query.duplicate(true),"errors":errors.slice(0,20)}

static func apply(query: Array, profile: Dictionary) -> Dictionary:
	var checked: Dictionary = validate(profile)
	if not checked.ok: return _failure(query,checked.errors)
	var clean: Dictionary = checked.profile
	if not clean.enabled: return {"ok":true,"query":query.duplicate(true),"errors":[]}
	if query.size() != 3 or not query[0] is String or not query[2] is Dictionary: return _failure(query,["query: expected native URL, headers and JSON body."])
	var result: Array = query.duplicate(true)
	var body: Dictionary = result[2]
	var protocol: String = _protocol(query[0],body)
	if protocol == "": return _failure(query,["query: unsupported API shape; manual generation preferences were not applied."]) if _requested(clean) else {"ok":true,"query":result,"errors":[]}
	var errors: Array = []
	_controls(body,"query",errors)
	if not errors.is_empty(): return _failure(query,errors)
	var writes: Dictionary = {}
	var tokens: Array = _existing(body,BUDGET_PATHS)
	var token_path: String = str(tokens[0]) if not tokens.is_empty() else "max_tokens"
	if protocol == "responses": token_path = "max_output_tokens"
	elif protocol == "messages": token_path = "max_tokens"
	elif protocol == "gemini": token_path = "generationConfig.maxOutputTokens"
	if clean.token_field != "auto":
		if protocol == "chat" or (protocol in ["responses","messages"] and clean.token_field == token_path): token_path = clean.token_field
		else: errors.append("token_field: selected token field is incompatible with the native protocol.")
	if clean.max_output_tokens > 0: writes[token_path] = clean.max_output_tokens
	elif clean.token_field != "auto" and not tokens.is_empty() and not _has(clean.extra,token_path): writes[token_path] = _get(body,tokens[0])
	if clean.reasoning != "":
		var effort: String = "reasoning_effort"
		if protocol == "responses": effort = "reasoning.effort"
		elif protocol == "messages": effort = "output_config.effort"
		elif protocol == "gemini": errors.append("reasoning: no generic Gemini effort mapping; specify an actually supported native setting in extra.")
		elif clean.reasoning_field == "auto":
			var existing: Array = _existing(body,EFFORT_PATHS)
			if not existing.is_empty(): effort = existing[0]
		if clean.reasoning_field != "auto":
			if protocol == "chat" or clean.reasoning_field == effort: effort = clean.reasoning_field
			else: errors.append("reasoning_field: selected effort field is incompatible with the native protocol.")
		writes[effort] = clean.reasoning
	if clean.verbosity != "":
		if protocol == "chat": writes["verbosity"] = clean.verbosity
		elif protocol == "responses": writes["text.verbosity"] = clean.verbosity
		else: errors.append("verbosity: this protocol has no standard verbosity field; use supported native extra JSON.")
	if clean.temperature != null: writes["generationConfig.temperature" if protocol == "gemini" else "temperature"] = clean.temperature
	if clean.top_p != null: writes["generationConfig.topP" if protocol == "gemini" else "top_p"] = clean.top_p
	for path: String in writes:
		if _has(clean.extra,path) and _get(clean.extra,path) != writes[path]: errors.append("extra."+path+": conflicts with the explicit generation preference.")
	# A single extra alias replaces native defaults, but never a different explicit
	# semantic choice, even when its value happens to be equal.
	for group: Array in GENERATION_GROUPS:
		var extra_fields: Array = _existing(clean.extra,group)
		if extra_fields.size() != 1: continue
		if group == BUDGET_PATHS and clean.token_field != "auto" and token_path != extra_fields[0]: errors.append("extra."+str(extra_fields[0])+": conflicts with the explicit token_field.")
		for path: String in group:
			if writes.has(path) and path != extra_fields[0]: errors.append("extra."+str(extra_fields[0])+": conflicts with the explicit generation field "+path+".")
	if not errors.is_empty(): return _failure(query,errors)
	if writes.has(token_path):
		for old: String in tokens:
			if old != token_path: _erase(body,old)
	if clean.reasoning != "":
		for old: String in _existing(body,EFFORT_PATHS):
			if not writes.has(old): _erase(body,old)
	for path: String in writes: _set(body,path,writes[path])
	for group: Array in GENERATION_GROUPS:
		var extra_fields: Array = _existing(clean.extra,group)
		if extra_fields.size() == 1:
			for old: String in _existing(body,group):
				if old != extra_fields[0]: _erase(body,old)
	_merge(body,clean.extra)
	_controls(body,"query",errors)
	if not errors.is_empty(): return _failure(query,errors)
	return {"ok":true,"query":result,"errors":[]}
