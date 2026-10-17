extends RefCounted
static var sent: Array = []
static func local_one(_base: String) -> bool: return false
static func ollama(_base: String) -> bool: return false
static func bridge(_base: String) -> bool: return false
static func router(_base: String) -> bool: return false
static func gigachat(_base: String) -> bool: return false
static func yandex(_base: String) -> bool: return false
static func yandex_model(model: String, _catalog: String) -> String: return model
static func catalog_from_model(_model: String) -> String: return ""
static func _pax_hook(_name: String, event: Dictionary) -> Dictionary: return event
static func has_handlers(_name: String) -> bool: return false
static func substitute(text: String, _value: Variant = null) -> String: return text
static func setting() -> Dictionary: return {}
static func send(_destination: HTTPRequest, url: String, headers: PackedStringArray, _method: int, raw: String) -> int:
	sent.append({"url":url,"headers":headers,"body":JSON.parse_string(raw)}); return OK
static func chat(_key: String,_scope: String,_url: String,_raw: String) -> Array: return [0,PackedByteArray()]
