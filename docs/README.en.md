# Advanced AI settings

Per-endpoint and per-model generation profiles for **Pax Universe 0.32.6**. Mod version: **2.4.1**.

[Русское описание](../README.md)

## How to open the settings

1. **Load or start a campaign.**
2. Open **Game menu → Settings → AI**.
3. Under **Additional**, click **Advanced settings**.
4. Enable **Use profile**, adjust the parameters and click **Apply**.

## Installation

Install **Advanced AI settings** from the launcher's official Workshop and enable it under Mods. Alternatively, close the game and place `ai_tuning-2.4.1.zip` from GitHub Releases in the game's user mods folder without extracting it. Find that folder through Launcher → Mods → Mods folder; on Windows it is normally `%APPDATA%\Pax Universe\mods`.

Enable the mod and approve code execution through the normal game prompt if requested. Keep only one installed copy. Replace an older manual installation while the game is closed; Workshop copies update through the launcher.

In the stock game, the mod is available **after loading a campaign**, inside the existing **Settings → AI → Additional → Advanced settings** form. The repository also contains [source integration for a game fork](../integrations/game-fork/). Its launcher part must be integrated into a fork; installing the ordinary mod does not enable code in the stock cold launcher.

## Profiles

Choose the endpoint and model through the game's normal connection form. Open Advanced settings, enable **Use profile**, set the desired values and Apply. Reset removes the selected model's profile. Profiles are stored separately from campaigns; connection credentials remain in the game and are not copied into profiles.

| Field | Meaning |
| --- | --- |
| Context window | Total request and response capacity, in tokens. |
| Maximum output | Maximum generated tokens for one request. |
| Response timeout | Seconds to wait for the response, including long reasoning. |
| Reasoning effort | Exact value supported by the API, such as none, low or high. Available values depend on the model. |
| Verbosity | Response verbosity when the API supports it. |
| Temperature | Sampling variation; lower values are more predictable. |
| Top-p | Probability mass used for token sampling. |
| Image input | Auto detection in Harness, with Enabled and Disabled overrides. |
| Additional JSON | Extra generation parameters, for example `{"seed":42}` when supported. |

Zero, a blank value or Automatic leaves the corresponding setting to the game. Refresh capabilities requests model metadata; providers may report only part of it. You can supply exact manual values when needed. Auto is normally appropriate for API field mapping.

Do not put endpoint URLs, authorization, model identities, messages, tools or streaming controls in additional generation JSON. They belong to the game's connection and request pipeline. Unsupported explicit parameters return an error rather than being silently deleted. Actual model/API limits still apply.

Image input defaults to Auto and does not require Use profile. [How detection works](vision-auto.md). A manual override does not give a text-only model vision. The mod works on its own and with Pax Harness 1.10.0 or later.

## Languages and source

Full Russian and English interfaces follow the game's selected language, including open profile windows. Switching language preserves drafts and profile values. API parameter identifiers remain unchanged.

Entry: `src/main.gd`; profile policy and identity handling are under `src/domain/`, UI adapters under `src/ui/`, and translations under `data/lang/`. The fork integration is separate from the installable ZIP.

The interface follows the game language: Russian for RU, English for EN and all other game languages.

Install the release ZIP. Do not copy `integrations/game-fork` into the installed mod: it targets a 0.31.2 source fork and does not apply as a ready-made patch to 0.32.6. To restore per-request timeouts with Harness, use a Harness build supporting `set_request_timeout`. Provider-specific thinking switches, such as DeepSeek's `thinking`, can be supplied through additional JSON where required.
