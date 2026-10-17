extends SceneTree
const Policy = preload("res://src/ai/tuning/ProfilePolicy.gd")
var errors: Array = []
func check(value: bool, message: String) -> void:
	if not value: errors.append(message)
func profile(extra: Dictionary = {}) -> Dictionary:
	var result := {"enabled":true}; result.merge(extra)
	return result
func query(protocol: String = "chat") -> Array:
	var body := {"model":"unlisted-future-model","messages":[{"role":"system","content":"Exact system"},{"role":"user","content":[{"type":"image_url","image_url":{"url":"opaque-image"}},{"type":"text","text":"Exact input"}]}],"max_tokens":2400,"native_future":{"preserve":[1,2]},"stream":true,"tools":[{"type":"function","function":{"name":"native"}}]}
	var suffix := "/chat/completions"
	if protocol == "responses":
		suffix = "/responses"; body.erase("messages"); body.erase("max_tokens"); body.input = "Exact Responses input"; body.max_output_tokens = 2400; body.text = {"format":{"type":"json_object"}}
	elif protocol == "messages": suffix = "/messages"; body.system = "Exact Messages system"
	elif protocol == "gemini":
		suffix = "/models/example:generateContent?key=opaque-fixture"
		body.erase("messages"); body.erase("max_tokens"); body.contents = [{"role":"user","parts":[{"text":"Exact Gemini input"}]}]; body.generationConfig = {"maxOutputTokens":2400,"candidateCount":1}
	return ["https://arbitrary.example/custom/v1"+suffix,PackedStringArray(["Authorization: opaque-fixture-only","X-Native: preserve"]),body]
func _initialize() -> void:
	var defaults: Dictionary = Policy.validate({})
	check(defaults.ok and not defaults.profile.enabled and defaults.profile.max_output_tokens == 0 and defaults.profile.temperature == null,"safe opt-in defaults and automatic controls")
	var large := profile({"context_tokens":10000000,"max_output_tokens":2000000})
	check(Policy.validate(large).ok and Policy.output_budget(large,2400) == 2000000,"explicit output exceeds old 8000 cap without clamping")
	check(Policy.validate(profile({"context_tokens":4096,"max_output_tokens":16000})).ok,"context/output relationship remains an explicit request-budget guard responsibility")
	check(defaults.profile.timeout_seconds == 0 and Policy.validate(profile({"timeout_seconds":1})).ok and Policy.validate(profile({"timeout_seconds":3600})).ok,"timeout defaults auto and accepts exact manual transport seconds")
	for invalid: Variant in [-1,3601,1.5,INF,NAN,true,"90",null]: check(not Policy.validate(profile({"timeout_seconds":invalid})).ok,"timeout finite integral 0..3600 metadata only")
	var timeout_query: Dictionary = Policy.apply(query(),profile({"timeout_seconds":600}))
	check(timeout_query.ok and timeout_query.query == query() and not timeout_query.query[2].has("timeout_seconds"),"timeout never injected into API payload")
	check(Policy.output_budget({},12345) == 12345 and Policy.output_budget(profile(),8192) == 8192,"disabled/auto budgets retain exact caller fallback")
	for invalid: Variant in [-1,10000001,1.25,INF,NAN,true,"20000",null]:
		for field: String in ["context_tokens","max_output_tokens"]:
			check(not Policy.validate(profile({field:invalid})).ok,"invalid bounded integer rejected: "+field)
	for temperature: Variant in [-0.1,2.1,NAN,INF,true,"0.2"]: check(not Policy.validate(profile({"temperature":temperature})).ok,"invalid temperature rejected")
	for top_p: Variant in [-0.1,1.1,INF,true,"0.5"]: check(not Policy.validate(profile({"top_p":top_p})).ok,"invalid top_p rejected")
	check(not Policy.validate({"enabled":1}).ok and not Policy.validate(profile({"token_field":"custom"})).ok and not Policy.validate(profile({"reasoning_field":"thinking"})).ok,"control selectors strictly typed")
	check(not Policy.validate(profile({"api_key":"PRIVATE_MUST_NOT_ECHO"})).ok,"covert profile credentials/unknown fields rejected")
	check(not "PRIVATE_MUST_NOT_ECHO" in JSON.stringify(Policy.validate(profile({"api_key":"PRIVATE_MUST_NOT_ECHO"}))),"credential values never appear in validation errors/profile")
	for level: String in ["off","none","minimal","low","medium","high","xhigh","max","future-supported-level"]:
		var p: Dictionary = profile({"reasoning":level})
		var output: Dictionary = Policy.apply(query(),p)
		check(output.ok and output.query[2].reasoning_effort == level,"exact selected effort forwarded with no model/level whitelist: "+level)
	var q: Array = query(); var before: Array = q.duplicate(true)
	var p: Dictionary = profile({"context_tokens":1000000,"max_output_tokens":64000,"reasoning":"off","verbosity":"high","temperature":0.0,"top_p":1.0,"extra":{"native_future":{"added":true},"stop":["END"]}})
	var p_before: Dictionary = p.duplicate(true)
	var output: Dictionary = Policy.apply(q,p)
	check(output.ok and output.query[2].max_tokens == 64000 and output.query[2].reasoning_effort == "off" and output.query[2].verbosity == "high","Chat semantic controls use generic known shape")
	check(output.query[2].temperature == 0.0 and output.query[2].top_p == 1.0 and not output.query[2].has("context_tokens"),"zero sampling values retained and context never injected into API body")
	check(output.query[2].native_future == {"preserve":[1,2],"added":true} and output.query[2].stop == ["END"],"extra recursively merges after semantic settings and retains unknown native options")
	check(output.query[0] == q[0] and output.query[1] == q[1] and output.query[2].messages == q[2].messages and output.query[2].tools == q[2].tools and output.query[2].stream == q[2].stream,"route, headers, prompt/image/tool parts and transport untouched")
	check(q == before and p == p_before,"apply never mutates original query/profile")
	output.query[1][0] = "changed"; output.query[2].native_future.preserve.append(3)
	check(q == before,"returned query deep ownership independent")
	var disabled := Policy.apply(q,{"enabled":false,"max_output_tokens":64000})
	check(disabled.ok and disabled.query == q,"disabled valid profile does not alter query")
	for token: String in ["max_tokens","max_completion_tokens","max_output_tokens"]:
		var native: Array = query(); native[2].erase("max_tokens"); native[2][token] = 2400
		var applied: Dictionary = Policy.apply(native,profile({"max_output_tokens":32000}))
		check(applied.ok and applied.query[2][token] == 32000 and Policy._existing(applied.query[2],Policy.BUDGET_PATHS).size() == 1,"Chat auto preserves actual existing token field: "+token)
	var renamed: Dictionary = Policy.apply(query(),profile({"token_field":"max_completion_tokens","max_output_tokens":128000}))
	check(renamed.ok and renamed.query[2].max_completion_tokens == 128000 and not renamed.query[2].has("max_tokens"),"explicit token field maps budget without duplicated aliases")
	var absent: Array = query(); absent[2].erase("max_tokens")
	check(Policy.apply(absent,profile({"max_output_tokens":16000})).query[2].max_tokens == 16000,"Chat without native token field uses standard max_tokens")
	var response: Dictionary = Policy.apply(query("responses"),profile({"max_output_tokens":64000,"reasoning":"off","verbosity":"low","temperature":0.2,"top_p":0.9}))
	check(response.ok and response.query[2].max_output_tokens == 64000 and response.query[2].reasoning.effort == "off" and response.query[2].text.verbosity == "low" and response.query[2].text.format == {"type":"json_object"},"Responses uses native nested reasoning/text and preserves existing format")
	var messages: Dictionary = Policy.apply(query("messages"),profile({"max_output_tokens":64000,"reasoning":"none","temperature":0.3,"top_p":0.8}))
	check(messages.ok and messages.query[2].max_tokens == 64000 and messages.query[2].output_config.effort == "none","Messages explicit effort uses standardized output_config.effort with exact value")
	check(not Policy.apply(query("messages"),profile({"verbosity":"high"})).ok,"unsupported Messages verbosity is visible, never silently removed")
	var gemini: Dictionary = Policy.apply(query("gemini"),profile({"max_output_tokens":64000,"temperature":0.4,"top_p":0.7}))
	check(gemini.ok and gemini.query[2].generationConfig == {"maxOutputTokens":64000,"candidateCount":1,"temperature":0.4,"topP":0.7},"Gemini known native generationConfig mapped without losing native values")
	check(not Policy.apply(query("gemini"),profile({"reasoning":"off"})).ok and not Policy.apply(query("gemini"),profile({"verbosity":"low"})).ok,"unknown Gemini effort/verbosity not guessed")
	check(not Policy.apply(query("responses"),profile({"token_field":"max_tokens","max_output_tokens":16000})).ok and not Policy.apply(query("messages"),profile({"reasoning":"low","reasoning_field":"reasoning_effort"})).ok,"incompatible explicit protocol field selection rejected")
	var unknown: Array = query(); unknown[0] = "https://arbitrary.example/unknown"
	check(not Policy.apply(unknown,profile({"temperature":0.2})).ok and Policy.apply(unknown,profile()).ok,"unknown API never pretends a manual preference was applied")
	check(not Policy.apply([],profile()).ok,"malformed query reports error")
	test_extra()
	test_vision()
	print("AI_TUNING_POLICY_TESTS: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)

func test_vision() -> void:
	var original := {"enabled":true,"vision_input":true}
	var before: Dictionary = original.duplicate(true)
	var checked: Dictionary = Policy.validate(original)
	check(Policy.validate({}).profile.get("vision_input") == false,"image-input capability is explicitly opt-in for legacy/empty profiles")
	check(checked.ok and checked.profile.get("vision_input") == true and original == before,"manual image-input boolean validates without mutating the source profile")
	for invalid: Variant in [0,1,"true",null,[],{}]:
		check(not Policy.validate({"vision_input":invalid}).ok,"image-input capability requires an actual boolean")
	for protocol: String in ["chat","responses","messages","gemini"]:
		var native: Array = query(protocol)
		var native_before: Array = native.duplicate(true)
		var applied: Dictionary = Policy.apply(native,original)
		check(applied.ok and applied.query == native_before and native == native_before,"image-input preference never enters the wire body or modifies existing content: "+protocol)
	check(Policy.output_budget(original,8192) == 8192 and Policy.protected_generation_fields(original).is_empty(),"image-input metadata changes neither generation budget nor protected API fields")
	var inactive: Dictionary = Policy.apply(query(),{"enabled":false,"vision_input":true})
	check(inactive.ok and inactive.query == query(),"inactive saved image-input preference never changes native text transport")
	check(not Policy.validate(profile({"extra":{"vision_input":true}})).ok,"image-input preference cannot be injected as an API generation field through extra JSON")

func test_extra() -> void:
	for key: String in ["model","messages","system","input","contents","prompt","tools","stream","stream_options","Authorization","api-key","apiKey","headers","base_url","url","endpoint","password","systemInstruction"]:
		for extra: Dictionary in [{key:"PRIVATE_VALUE"},{"native_future":{key:"PRIVATE_VALUE"}}]:
			var failed: Dictionary = Policy.validate(profile({"extra":extra}))
			check(not failed.ok and not "PRIVATE_VALUE" in JSON.stringify(failed),"extra protects route/prompt/auth even nested: "+key)
	var extra_budget := profile({"extra":{"max_completion_tokens":64000}})
	check(Policy.validate(extra_budget).ok and Policy.output_budget(extra_budget,2400) == 64000,"extra-only explicit generation budget reserved before context guard")
	var extra_gemini := profile({"extra":{"generationConfig":{"maxOutputTokens":128000}}})
	check(Policy.output_budget(extra_gemini,2400) == 128000,"native Gemini extra budget included in reservation")
	for extra: Dictionary in [{"max_tokens":16000,"max_completion_tokens":16000},{"max_tokens":0},{"max_output_tokens":10000001},{"reasoning_effort":"low","reasoning":{"effort":"high"}},{"temperature":3},{"top_p":2},{"future":INF}]:
		check(not Policy.validate(profile({"extra":extra})).ok,"extra generation conflicts/invalid values rejected")
	check(not Policy.validate(profile({"max_output_tokens":64000,"extra":{"max_tokens":32000}})).ok,"typed output budget and different extra budget conflict explicitly")
	check(not Policy.apply(query(),profile({"temperature":0.2,"extra":{"temperature":0.3}})).ok,"extra cannot silently overwrite explicit sampling preference")
	check(not Policy.apply(query("responses"),profile({"reasoning":"low","extra":{"reasoning":{"effort":"high"}}})).ok,"extra cannot silently overwrite explicit nested effort")
	var native_default: Array = query(); native_default[2].max_tokens = 8192; native_default[2].reasoning_effort = "none"; native_default[2].verbosity = "low"; native_default[2].temperature = 0.2; native_default[2].top_p = 0.9
	var native_before: Array = native_default.duplicate(true)
	var manual_extra: Dictionary = profile({"extra":{"max_completion_tokens":131072,"reasoning":{"effort":"high"},"text":{"verbosity":"high"},"generationConfig":{"temperature":0.6,"topP":0.8}}})
	var manual_before: Dictionary = manual_extra.duplicate(true)
	var replaced: Dictionary = Policy.apply(native_default,manual_extra)
	check(replaced.ok and replaced.query[2].max_completion_tokens == 131072 and not replaced.query[2].has("max_tokens"),"extra-only budget replaces native default field without duplicates or old 8000 cap")
	check(replaced.ok and replaced.query[2].reasoning.effort == "high" and not replaced.query[2].has("reasoning_effort") and replaced.query[2].text.verbosity == "high" and not replaced.query[2].has("verbosity"),"extra-only effort and verbosity replace alternative native generated fields")
	check(replaced.ok and replaced.query[2].generationConfig == {"temperature":0.6,"topP":0.8} and not replaced.query[2].has("temperature") and not replaced.query[2].has("top_p"),"extra-only sampling aliases replace alternative native defaults")
	check(native_default == native_before and manual_extra == manual_before and Policy.output_budget(manual_extra,8192) == 131072,"extra replacement leaves both source inputs unchanged and reserves exact budget")
	for conflict: Dictionary in [{"max_output_tokens":131072,"extra":{"max_completion_tokens":131072}},{"reasoning":"high","extra":{"reasoning":{"effort":"high"}}},{"verbosity":"high","extra":{"text":{"verbosity":"high"}}},{"temperature":0.6,"extra":{"generationConfig":{"temperature":0.6}}},{"top_p":0.8,"extra":{"generationConfig":{"topP":0.8}}}]:
		check(not Policy.apply(query(),profile(conflict)).ok,"alternate extra field never overrides explicit semantic field even with equal value")
	check(Policy.apply(query(),profile({"token_field":"max_completion_tokens","max_output_tokens":131072,"extra":{"max_completion_tokens":131072}})).ok,"same explicit field and equal budget agree")
	var selected_extra: Dictionary = Policy.apply(query(),profile({"token_field":"max_completion_tokens","extra":{"max_completion_tokens":131072}}))
	check(selected_extra.ok and selected_extra.query[2].max_completion_tokens == 131072 and not selected_extra.query[2].has("max_tokens"),"explicit token selector agrees with extra-only budget without imposing auto native budget")
	var empty_native: Array = query(); empty_native[2].erase("max_tokens")
	check(not Policy.apply(empty_native,profile({"token_field":"max_tokens","extra":{"max_completion_tokens":131072}})).ok,"explicit token field conflict rejected even with no native budget")
	var nested_native: Array = query(); nested_native[2].reasoning = {"effort":"none","native_sibling":true}; nested_native[2].text = {"verbosity":"low","format":{"type":"json_schema"}}
	var flattened: Dictionary = Policy.apply(nested_native,profile({"extra":{"reasoning_effort":"high","verbosity":"high"}}))
	check(flattened.ok and flattened.query[2].reasoning == {"native_sibling":true} and flattened.query[2].text == {"format":{"type":"json_schema"}} and flattened.query[2].reasoning_effort == "high" and flattened.query[2].verbosity == "high","replacing nested native aliases preserves all unrelated native object fields")
	var protections: Array = Policy.protected_generation_fields(manual_extra)
	for path: String in ["max_tokens","max_completion_tokens","max_output_tokens","reasoning_effort","reasoning","reasoning.effort","output_config","output_config.effort","verbosity","text","text.verbosity","temperature","top_p","generationConfig","generationConfig.temperature","generationConfig.topP"]:
		check(protections.has(path),"manual controls protect alias and ancestor from silent recovery: "+path)
	check(Policy.protected_generation_fields({}).is_empty() and Policy.protected_generation_fields(profile({"timeout_seconds":90,"context_tokens":50000})).is_empty(),"disabled and metadata-only profiles do not protect API fields")
	check(Policy.protected_generation_fields(profile({"extra":{"response_format":{"type":"json_schema"},"native_future":{"value":1}}})).has("response_format"),"arbitrary explicit custom generation roots protected")
	var failure_input: Array = query(); var failure_copy: Array = failure_input.duplicate(true)
	var failed_merge: Dictionary = Policy.apply(failure_input,profile({"reasoning":"low","extra":{"reasoning":false}}))
	check(not failed_merge.ok and failure_input == failure_copy and failed_merge.query == failure_copy,"invalid extra cannot replace a native generation object and failed apply is atomic")
	var field_only: Dictionary = Policy.apply(query(),profile({"token_field":"max_completion_tokens"}))
	check(field_only.ok and field_only.query[2].max_completion_tokens == 2400 and not field_only.query[2].has("max_tokens"),"field-only selector migrates exact existing budget without increase")
	var existing_effort: Array = query(); existing_effort[2].reasoning = {"effort":"low","native_option":true}
	var nested_effort: Dictionary = Policy.apply(existing_effort,profile({"reasoning":"off"}))
	check(nested_effort.ok and nested_effort.query[2].reasoning == {"effort":"off","native_option":true} and not nested_effort.query[2].has("reasoning_effort"),"auto Chat effort respects actual existing nested field and preserves native siblings")
	var no_budget: Array = query(); no_budget[2].erase("max_tokens")
	check(Policy.apply(no_budget,profile({"extra":{"max_completion_tokens":64000}})).ok,"single extra-only budget accepted when not conflicting with native alias")
	var both: Array = query(); both[2].max_completion_tokens = 2400
	check(not Policy.apply(both,profile({"max_output_tokens":64000})).ok,"conflicting preexisting token aliases are not silently repaired")
	var shallow := {"leaf":true}; var nested: Dictionary = shallow
	for i: int in 10: nested = {"nested":nested}
	check(not Policy.validate(profile({"extra":nested})).ok,"extra nesting bounded")
	check(not Policy.validate(profile({"extra":{"native_future":"x".repeat(Policy.MAX_EXTRA_BYTES+1)}})).ok,"extra serialized size bounded")
	var original := profile({"extra":{"native_future":{"values":[1,2]}}})
	var checked: Dictionary = Policy.validate(original); checked.profile.extra.native_future.values.append(3)
	check(original.extra.native_future.values == [1,2],"validated profile deeply detached")
