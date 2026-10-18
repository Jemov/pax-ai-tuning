# AI fine tuning for a game fork

One panel in the launcher's AI section and inside the existing **Settings → AI → Advanced → Fine tuning** form in a game. Profiles belong to an API endpoint and model; credentials remain in the normal connection settings.

Controls include context, output limit, timeout, reasoning effort, verbosity, temperature, top-p, image-input permission for Harness and extra generation JSON. Automatic values preserve normal game settings. Explicit settings are not silently removed when an API rejects them.

## Integrate with a 0.31.2 fork

1. Add the the files and the `locales` folder from [`src/ai/tuning/`](src/ai/tuning/) to the matching source directory.
2. Apply [`native-ai-tuning-0.31.2.diff`](native-ai-tuning-0.31.2.diff). It attaches the panel in `LauncherCloudAi` and `SettingsScreen`, and generation profiles in `Provider`, `RequestBuilder` and `RequestGuard`.
3. Merge the corresponding methods when working with a different game version.

Profiles use a separate `ai_tuning_profiles` section in native settings. Output is reserved before the context check and stays within that request's allowance even if its profile changes while queued.

Standard Chat Completions, Responses, Messages and Gemini generation fields are mapped. Ollama-specific generation options need separate mapping; context and automatic settings remain available.

This directory belongs in a fork's source tree. The installable mod is the separate **`ai_tuning-2.3.1.zip`** asset in Releases.

[По-русски](README-RU.md)

RU / EN: язык панели следует языку игры; профили и введённые значения сохраняются. / The panel follows the game language; profiles and entered values are preserved.
