extends SceneTree
const Store = preload("res://src/ai/tuning/GenerationProfile.gd")
const Paths = preload("res://src/save/Paths.gd")
const Builder = preload("res://NativeRequestBuilder.gd")
const ProviderFixture = preload("res://tests/NativeProviderFixture.gd")
const Dependencies = preload("res://tests/NativeDependencies.gd")
var errors: Array = []
func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)
func save(profile: Dictionary, model: String = "Future") -> void:
	var result: Dictionary = Store.update(Paths.fixture,"https://fixture.invalid/v1",model,profile)
	check(result.ok,"test profile valid: "+str(result.errors))
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Paths.fixture = {"providers":{"brain":{"base":"https://fixture.invalid/v1","model":"Future","key":"OPAQUE_NATIVE_ONLY","window":1000000}},"unrelated":{"keep":true}}
	check(not Store.current("https://fixture.invalid/v1","Future").enabled,"native feature opt-in without author profile")
	save({"enabled":true,"vision_input":true,"context_tokens":1000000,"max_output_tokens":131072,"timeout_seconds":1,"reasoning":"off","extra":{"seed":7}})
	check(not "OPAQUE_NATIVE_ONLY" in JSON.stringify(Paths.fixture[Store.SETTING]) and Paths.fixture.providers.brain.key == "OPAQUE_NATIVE_ONLY" and Paths.fixture.unrelated.keep,"persistent generation section contains no duplicated credentials; native sections preserved")
	check(not Store.current("https://other.invalid/v1","Future").enabled and not Store.current("https://fixture.invalid/other","Future").enabled and not Store.current("https://fixture.invalid/v1","future").enabled,"profiles exact base path and case-sensitive model")
	var native := ["https://fixture.invalid/v1/chat/completions",PackedStringArray(["Authorization: opaque-fixture"]),{"model":"Future","max_tokens":8000,"messages":[{"role":"user","content":"exact"}]}]
	var before: Array = native.duplicate(true)
	var result: Dictionary = Store.apply_query(native,Store.current("https://fixture.invalid/v1","Future"),4096)
	check(result.ok and result.query[2].max_tokens == 4096 and result.query[2].reasoning_effort == "off" and result.query[2].seed == 7,"service reservation bounds manual 131072 with apply-last exact effort/extra")
	check(not result.query[2].has("vision_input") and Store.current("https://fixture.invalid/v1","Future").vision_input,"native policy exposes image capability through profile without sending a generation flag to API")
	check(native == before and Store.current("https://fixture.invalid/v1","Future").max_output_tokens == 131072,"query and saved profile immutable")
	check(Store.timeout(Store.current("https://fixture.invalid/v1","Future"),150) == 1,"manual timeout 1 second never 30-second-clamped")
	check(Store.timeout({},0) == 0 and Store.timeout({},300) == 300,"zero auto timeout retains exact native local/report fallback")
	var provider := ProviderFixture.new(); root.add_child(provider)
	var builder: RefCounted = Builder.new(provider); provider.builder = builder
	var destination := HTTPRequest.new(); provider.add_child(destination)
	provider.http_results = HTTPRequest.new(); provider.add_child(provider.http_results)
	provider.http_argument = HTTPRequest.new(); provider.add_child(provider.http_argument)
	check(provider.generation_request_timeout(provider.http_results) == 1 and provider.generation_request_timeout(provider.http_argument) == 1,"actual native timeout helper respects manual1 for reports and arguments")
	# Real patched native dispatch enters its real guard queue, with actual budget reserved before fit.
	check(builder.dispatch(destination,"JSON","full exact input",0.2,1200,"exact dossier"),"native dispatch accepted into guard queue")
	check(provider.queue.size() == 9 and provider.queue[5] == 131072 and provider.queue[8] and provider.queue[1].begins_with("JSON") and provider.queue[2] == "full exact input","actual RequestBuilder queue reserves manual output before fit with full input intact")
	save({"enabled":true,"context_tokens":1000000,"max_output_tokens":500000,"timeout_seconds":1})
	builder._send_now.callv(provider.queue)
	check(Dependencies.sent.size() == 1 and Dependencies.sent.back().body.max_tokens == 131072 and destination.timeout == 1,"late profile increase never exceeds native prefit reservation; exact timeout applies at dispatch")
	save({"enabled":true,"context_tokens":2000,"max_output_tokens":500000})
	Dependencies.sent.clear(); builder._send_now.callv(provider.queue); await process_frame
	check(Dependencies.sent.is_empty() and provider.failures.back().code == "context_length_exceeded","late context decrease rechecks original queued input and refuses before API")
	# Full-input reservation remains guarded if its profile is disabled while queued.
	save({"enabled":true,"context_tokens":1000000,"max_output_tokens":500000})
	builder.dispatch(destination,"JSON","q".repeat(100000),0.2,1200)
	var pending_manual: Array = provider.queue.duplicate()
	Paths.fixture.providers.brain.window = 16384
	save({"enabled":false})
	Dependencies.sent.clear(); builder._send_now.callv(provider.queue); await process_frame
	check(Dependencies.sent.is_empty() and provider.failures.back().code == "context_length_exceeded","enabled to disabled queued input cannot bypass current native context window")
	# A second request may reuse the same HTTPRequest; its mutable metadata must not
	# overwrite the older packet's admission snapshot.
	builder.dispatch(destination,"JSON","second baseline input",0.2,1200)
	check(not provider.queue[8],"second disabled request retains legacy admission independently")
	Dependencies.sent.clear(); builder._send_now.callv(pending_manual); await process_frame
	check(Dependencies.sent.is_empty() and provider.failures.back().code == "context_length_exceeded","same-destination second dispatch cannot erase queued manual full-input guard")
	provider.model = "Another model"
	Dependencies.sent.clear(); builder._send_now.callv(pending_manual); await process_frame
	check(Dependencies.sent.is_empty() and provider.failures.back().code == "context_length_exceeded","queued full input is checked against different model's actual smaller context")
	provider.model = "Future"
	Paths.fixture.providers.brain.window = 1000000
	save({"enabled":true,"context_tokens":1000000,"max_output_tokens":500000})
	var callback: Array = []
	builder.execute_for_other({"с":"JSON","п":"service input","pr":1200,"к":"service"},func(code: int, value: String): callback.append([code,value]))
	check(Dependencies.sent.size() == 1 and Dependencies.sent.back().body.max_tokens == 1200,"actual native execute_for_other service limit never grows to full manual profile")
	Dependencies.sent.clear(); callback.clear()
	var package := {"с":"JSON","п":"x".repeat(10000),"pr":1200,"к":"service"}
	var package_before: Dictionary = package.duplicate(true)
	save({"enabled":true,"context_tokens":2000,"max_output_tokens":500000})
	builder.execute_for_other(package,func(code: int, value: String): callback.append([code,value]))
	check(Dependencies.sent.is_empty() and callback.size() == 1 and callback[0][0] == 400 and JSON.parse_string(callback[0][1]).error.code == "context_length_exceeded" and package == package_before,"service full input guard refuses before API exactly once without mutating caller packet")
	save({"enabled":true,"context_tokens":1000000,"max_output_tokens":500000})
	provider.channel = "mod_service"; provider._channels[provider.channel] = {}
	builder.dispatch(destination,"JSON","child exact",0.2,4096)
	check(provider.queue[5] == 4096,"registered dynamic channel retains caller-owned child reservation")
	provider.channel = "assistant"
	save({"enabled":true,"context_tokens":1000000,"max_output_tokens":500000,"timeout_seconds":0})
	builder._send_now.callv(provider.queue)
	check(destination.timeout == 150,"manual timeout reset to auto restores original native timeout even before settings mtime reload")
	check(provider.generation_request_timeout(provider.http_results) == 300 and provider.generation_request_timeout(provider.http_argument) == 60,"actual native timeout helper restores auto report multiplier and argument timeout")
	var foreign: Array = []
	provider.via_network = func(_destination: HTTPRequest, packet: Dictionary): foreign.append(packet)
	Dependencies.sent.clear(); builder.dispatch(destination,"JSON","foreign route",0.2,1200)
	check(foreign.size() == 1 and foreign[0].pr == 500000 and foreign[0]["п"] == "foreign route" and Dependencies.sent.is_empty(),"existing via_network retains route ownership and receives preguarded manual budget and intact input")
	provider.via_network = Callable()
	Dependencies.sent.clear(); save({"enabled":true,"context_tokens":1000000,"verbosity":"high"})
	provider.base_url = "https://api.anthropic.com/v1"
	Store.update(Paths.fixture,provider.base_url,provider.model,{"enabled":true,"context_tokens":1000000,"verbosity":"high"})
	builder._send_now(destination,"JSON","input","",0.2,1200,"assistant",false); await process_frame
	check(Dependencies.sent.is_empty() and provider.failures.back().status == 400 and provider.failures.back().message.contains("verbosity"),"unsupported manual Messages setting becomes concrete native HTTP400, never silently omitted")
	provider.base_url = "https://fixture.invalid/v1"
	Store.update(Paths.fixture,provider.base_url,provider.model,{},true)
	var automatic: Array = builder.build_request("JSON","exact","",0.2,1200,"assistant",false)
	check(automatic[2].max_tokens == 4200 and not automatic[2].has("seed") and Paths.fixture.providers.brain.window == 1000000,"auto-disabled native thinking reserve and global window preserved")
	provider.queue_free(); await process_frame
	print("NATIVE_GENERATION_TESTS: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
