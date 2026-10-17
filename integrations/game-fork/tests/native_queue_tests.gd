extends SceneTree
const Store = preload("res://src/ai/tuning/GenerationProfile.gd")
const Paths = preload("res://src/save/Paths.gd")
const Builder = preload("res://NativeRequestBuilder.gd")
const Guard = preload("res://NativeRequestGuard.gd")
const ProviderFixture = preload("res://tests/NativeProviderFixture.gd")
const Dependencies = preload("res://tests/NativeDependencies.gd")
var errors: Array = []
func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Paths.fixture = {"providers":{"brain":{"window":16384}}}
	var provider := ProviderFixture.new(); root.add_child(provider)
	var builder: RefCounted = Builder.new(provider); provider.builder = builder
	var guard: RefCounted = Guard.new(provider)
	var destination := HTTPRequest.new(); provider.add_child(destination)
	Store.update(Paths.fixture,provider.base_url,provider.model,{"enabled":true,"context_tokens":1000000,"max_output_tokens":10000})
	builder.dispatch(destination,"JSON","q".repeat(100000),0.2,1200)
	var manual: Array = provider.queue.duplicate()
	Store.update(Paths.fixture,provider.base_url,provider.model,{"enabled":false})
	builder.dispatch(destination,"JSON","second native input",0.2,1200)
	await guard.defer(manual,0.1); await process_frame
	check(Dependencies.sent.is_empty() and provider.failures.size() == 1 and provider.failures.back().code == "context_length_exceeded","actual native guard deferred forwarding preserves immutable marker after same-destination metadata reset")
	var legacy := [destination,"JSON","legacy input","",0.2,1200,"assistant",false]
	Dependencies.sent.clear(); await guard.defer(legacy,0.1)
	check(Dependencies.sent.size() == 1 and Dependencies.sent.back().body.max_tokens == 4200,"actual native guard still forwards legacy8-argument deferred packets")
	Dependencies.sent.clear()
	guard._queue.append(manual)
	await guard._poll(); await process_frame
	check(Dependencies.sent.is_empty() and provider.failures.size() == 2,"actual native RPM queue forwards9-argument manual packet with its full-input guard")
	builder._local_queue.append(manual)
	await builder._local_poll(); await process_frame
	check(Dependencies.sent.is_empty() and provider.failures.size() == 3,"actual native local queue preserves request-local manual marker")
	builder._local_queue.append(legacy)
	await builder._local_poll()
	check(Dependencies.sent.size() == 1,"actual native local queue retains legacy8-argument forwarding")
	Dependencies.sent.clear()
	# Native HTTP400 is already non-retryable. No change to native retry policy is
	# necessary, even when the local manual-preference error has retry metadata.
	destination.set_meta("retry_args",manual.slice(1))
	check(not guard.retry_if_silent(destination,400) and not destination.has_meta("retrying"),"unchanged native guard never silently retries a manual or remote400")
	# Exercise actual retry forwarding, not a copied implementation. These calls
	# wait only the original native3-second backoff and use the stub dispatcher.
	await guard._resend(destination,manual.slice(1)); await process_frame
	check(Dependencies.sent.is_empty() and provider.failures.size() == 4,"actual native retry retains manual admission snapshot")
	await guard._resend(destination,legacy.slice(1))
	check(Dependencies.sent.size() == 1 and Dependencies.sent.back().body.max_tokens == 4200,"actual native retry retains compatibility with legacy7-argument retry metadata")
	provider.queue_free(); await process_frame
	print("NATIVE_QUEUE_TESTS: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
