extends Node
## Optional selected-model metadata; no prompts, credentials or catalogue persistence.
const Identity = preload("res://src/ai/tuning/Identity.gd")
const MAX_BYTES := 4194304
signal changed
var _cache: Dictionary = {}
var _pending: Dictionary = {}

func info(base: String, model: String) -> Dictionary:
	var key: String = Identity.key(base,model)
	if _pending.has(key): return {"pending":true}
	if not _cache.has(key): return {}
	if Time.get_ticks_msec() >= int(_cache[key].expires):
		_cache.erase(key)
		return {}
	return _cache[key].info.duplicate(true)

func request(base: String, model: String, query: Array) -> void:
	var normalized: String = Identity.base_url(base)
	var key: String = Identity.key(base,model)
	if key == "" or _pending.has(key) or query.size() != 3 or not query[0] is String: return
	if query[0] not in [normalized+"/chat/completions",normalized+"/messages",normalized+"/responses"]: return
	if not query[1] is PackedStringArray and not query[1] is Array: return
	var headers := PackedStringArray()
	for value: Variant in query[1]:
		if not value is String or "\n" in value or "\r" in value: return
		headers.append(value)
	var http := HTTPRequest.new()
	http.timeout = 8
	http.max_redirects = 0
	http.body_size_limit = MAX_BYTES
	add_child(http)
	_pending[key] = http
	http.request_completed.connect(_received.bind(key,model,http),CONNECT_ONE_SHOT)
	var sent: int = http.request(normalized+"/models",headers,HTTPClient.METHOD_GET)
	if sent != OK: _received(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray(),key,model,http)
	changed.emit()

static func _integer(value: Variant) -> int:
	return int(value) if (value is int or value is float) and not value is bool and is_finite(float(value)) and value == floorf(float(value)) and value > 0 and value <= 10000000 else 0

static func parse(bytes: PackedByteArray, model: String) -> Dictionary:
	if bytes.size() > MAX_BYTES: return {"error":"metadata_too_large"}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK: return {"error":"metadata_invalid_json"}
	var value: Variant = json.data
	var rows: Variant = value.get("data",value.get("models",[])) if value is Dictionary else value
	if not rows is Array: return {"error":"metadata_no_models"}
	var selected: Dictionary = {}
	for row: Variant in rows:
		if row is Dictionary and row.get("id") == model:
			if not selected.is_empty(): return {"error":"metadata_ambiguous_model"}
			selected = row
	if selected.is_empty(): return {"error":"metadata_model_absent"}
	var result: Dictionary = {}
	for field: String in ["supported_parameters","supported_endpoints"]:
		if selected.get(field) is Array and selected[field].all(func(x: Variant): return x is String and x.length() <= 160): result[field] = selected[field].duplicate()
	for field: String in ["context_length","context_window","max_input_tokens"]:
		var number: int = _integer(selected.get(field))
		if number > 0: result["context_tokens"] = mini(int(result.get("context_tokens",number)),number)
	for field: String in ["max_output_tokens","max_completion_tokens"]:
		var number: int = _integer(selected.get(field))
		if number > 0: result["max_output_tokens"] = mini(int(result.get("max_output_tokens",number)),number)
	var top: Variant = selected.get("top_provider")
	if top is Dictionary and _integer(top.get("max_completion_tokens")) > 0:
		var number: int = _integer(top.max_completion_tokens)
		result["max_output_tokens"] = mini(int(result.get("max_output_tokens",number)),number)
	for pair: Array in [["supported_reasoning_efforts","reasoning_values"],["reasoning_values","reasoning_values"],["supported_verbosity","verbosity_values"],["verbosity_values","verbosity_values"]]:
		var options: Variant = selected.get(pair[0])
		if options is Array and options.all(func(x: Variant): return x is String and x.length() <= 80): result[pair[1]] = options.duplicate()
	if result.get("supported_endpoints") is Array and "/messages" in result.supported_endpoints and "/chat/completions" not in result.supported_endpoints: result["protocol"] = "messages"
	return result

func _received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, key: String, model: String, http: HTTPRequest) -> void:
	if not _pending.has(key) or _pending[key] != http:
		if is_instance_valid(http): http.queue_free()
		return
	_pending.erase(key)
	if is_instance_valid(http): http.queue_free()
	var details: Dictionary = parse(body,model) if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 else {"error":"metadata_http_"+str(code)}
	if _cache.size() >= 32 and not _cache.has(key): _cache.erase(_cache.keys()[0])
	_cache[key] = {"info":details,"expires":Time.get_ticks_msec()+(60000 if details.has("error") else 1800000)}
	changed.emit()

func cancel_all() -> void:
	for http: HTTPRequest in _pending.values():
		if is_instance_valid(http):
			http.cancel_request()
			http.queue_free()
	_pending.clear()
