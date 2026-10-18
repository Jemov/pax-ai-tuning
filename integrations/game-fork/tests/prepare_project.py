"""Build an offline fixture project from a developer's already-integrated source tree.

No installation, settings access, sockets, API calls or PCK manipulation.
Usage: python prepare_project.py --source-root <game-source> --project <empty-test-dir>
"""
import argparse
from pathlib import Path
import re
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-root", required=True, type=Path)
parser.add_argument("--project", required=True, type=Path)
args = parser.parse_args()
source, project = args.source_root.resolve(), args.project.resolve()
if project == source or source in project.parents or project in source.parents:
    parser.error("Fixture project must be outside and must not contain the source tree.")
marker = project / ".native-ai-tuning-fixtures"
if project.exists() and any(project.iterdir()) and (not marker.is_file() or marker.read_text(encoding="utf-8") != "Native AI tuning offline fixtures\n"):
    parser.error("Refusing nonempty directory not owned by these offline fixtures.")
project.mkdir(parents=True, exist_ok=True)
marker.write_text("Native AI tuning offline fixtures\n", encoding="utf-8")
(project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Native AI tuning offline fixtures"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
for entry in (source / "src/ai/tuning").glob("*.gd"):
    target = project / "src/ai/tuning" / entry.name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(entry, target)
locales = source / "src/ai/tuning/locales"
if locales.is_dir(): shutil.copytree(locales,project / "src/ai/tuning/locales",dirs_exist_ok=True)
tests = Path(__file__).resolve().parent
for entry in tests.glob("*.gd"):
    target = project / (entry.name if entry.name.endswith("_tests.gd") else "tests/"+entry.name)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(entry, target)
paths = project / "src/save/Paths.gd"
paths.parent.mkdir(parents=True, exist_ok=True)
paths.write_text('extends RefCounted\nstatic var fixture: Dictionary = {}\nstatic func settings() -> Dictionary: return fixture.duplicate(true)\nstatic func agent() -> String: return "native-fixture"\n', encoding="utf-8")
builder = (source / "src/ai/provider/RequestBuilder.gd").read_text(encoding="utf-8")
builder = re.sub(r'preload\("res://src/(?!ai/tuning/|save/Paths\.gd)[^\"]+"\)', 'preload("res://tests/NativeDependencies.gd")', builder)
(project / "NativeRequestBuilder.gd").write_text(builder, encoding="utf-8")
shutil.copyfile(source / "src/ai/provider/RequestGuard.gd", project / "NativeRequestGuard.gd")
provider = (source / "src/ai/Provider.gd").read_text(encoding="utf-8")
actual_timeout = re.search(r'func generation_request_timeout\([^\n]+\n(?:\t[^\n]*\n)+', provider)
if actual_timeout is None:
    parser.error("Source tree does not contain the native generation timeout integration.")
fixture = project / "tests/NativeProviderFixture.gd"
fixture.write_text(re.sub(r'func generation_request_timeout\([^\n]+\n', actual_timeout.group(0), fixture.read_text(encoding="utf-8")), encoding="utf-8")
launcher = project / "src/launcher/LauncherAi.gd"
launcher.parent.mkdir(parents=True, exist_ok=True)
launcher.write_text('extends RefCounted\nconst RussianProvidersScript = preload("res://tests/NativeDependencies.gd")\nstatic var query_count := 0\nstatic func check_request(base: String, _key: String, model: String) -> Array:\n\tquery_count += 1\n\treturn [base.rstrip("/")+"/chat/completions",PackedStringArray(["Authorization: opaque-fixture"]),{"model":model,"messages":[]}]\nstatic func write_settings(settings: Dictionary) -> void:\n\tpreload("res://src/save/Paths.gd").fixture = settings.duplicate(true)\n', encoding="utf-8")
(project / "src/ai/PaxAi.gd").write_text('extends RefCounted\nstatic func real_key(value: String) -> String: return value\n', encoding="utf-8")
print("Offline fixture project prepared. Native I/O dependencies are stubbed.")
