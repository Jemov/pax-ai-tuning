extends Node
const Store = preload("res://src/ai/tuning/GenerationProfile.gd")
var base_url := "https://fixture.invalid/v1"
var model := "Future"
var api_key := "OPAQUE_FIXTURE_ONLY"
var reflections := "auto"
var claude_effort := "low"
var gigachat_scope := "native"
var saving := "medium"
var world_ := ""
var side_status := Callable()
var side := ""
var veil_ := ""
var our_name := ""
var lang_hint := ""
var via_network := Callable()
var local_window := 0
var generation_error: Array = []
var failures: Array = []
var queue: Array = []
var _channels: Dictionary = {}
var channel := "assistant"
var builder: RefCounted
var rpm_limit := 0
signal request_silent(channel: String, code: int)
var wait_sec := 150.0
var http_results: HTTPRequest
var http_argument: HTTPRequest
func _without_term() -> bool: return false
func connected() -> bool: return true
func _reload_if_changed() -> void: pass
func channel_name(_destination: HTTPRequest) -> String: return channel
func small() -> bool: return false
func small_prompt(_channel: String) -> String: return ""
func profile() -> Dictionary: return {}
func _env_by_world(value: String) -> String: return value
func _called() -> String: return ""
func body_for_openai(value: Dictionary,_base: String,_model: String) -> Dictionary: return value
func generation_profile() -> Dictionary: return Store.current(base_url,model)
func generation_output_limit(fallback: int, small_request: bool = false) -> int: return Store.output_limit(generation_profile(),fallback,small_request)
func generation_timeout(fallback: float) -> float: return Store.timeout(generation_profile(),fallback)
func generation_request_timeout(_destination: HTTPRequest) -> float: return generation_timeout(150)
func generation_failure(destination: HTTPRequest, errors: Array, code: String = "generation_settings_invalid") -> bool:
	destination.set_meta("generation_settings_error",true)
	_curl_answer.call_deferred(destination,400,Store.error_body(errors,code)); return true
func _curl_answer(_destination: HTTPRequest, status: int, bytes: PackedByteArray) -> void:
	var response: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	failures.append({"status":status,"code":response.error.code,"message":response.error.message})
func guard() -> Object: return self
func requests() -> RefCounted: return builder
func gate(packet: Array, _delay: float) -> bool: queue = packet; return false
func _to_dump(_destination: HTTPRequest,_url: String,_body: String) -> void: pass
func _is_opencode_or_space_bunny() -> bool: return false
