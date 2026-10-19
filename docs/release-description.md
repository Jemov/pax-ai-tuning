# Тонкая настройка ИИ

Добавляет подробные настройки подключённой модели в штатную форму **«Тонкая настройка»**. Для каждого адреса API и модели сохраняется отдельный профиль.

**Где открыть:** загрузите или начните партию → **меню игры → Настройки → Нейросеть → Дополнительно → Тонкая настройка**. Включите **«Использовать профиль»**, задайте параметры и нажмите **«Применить»**.

- Поддержка изображений определяется автоматически: сведения API или короткая проверка картинки при первом использовании; результат сохраняется для API и модели. Ручные «Включено» и «Выключено» доступны в тонкой настройке.
- Окно контекста и максимальная длина ответа.
- Время ожидания ответа.
- Уровень рассуждений, включая отключение, если модель это поддерживает.
- Подробность ответа, температура и top-p.
- Разрешение на изображения во входных сообщениях.
- Дополнительные параметры генерации через JSON.
- Обновление сведений о возможностях модели и выбор формата параметров API.
- Сохранение, применение и сброс профиля выбранного подключения.

Пустые значения и автоматический режим оставляют соответствующие параметры игре. Допустимые значения зависят от API и модели; включение изображений не добавляет зрение текстовой модели. Адрес, модель и ключ остаются в подключении игры, ключи в профили не копируются.

Работает самостоятельно и вместе с Harness. В обычной игре настройки доступны после загрузки партии. В репозитории есть отдельная часть для лаунчера: она работает только после встраивания в форк игры.

Полный русский и английский интерфейс следуют языку игры. Для других языков используется английский. Для **Pax Universe 0.31.6**.

## English

# AI Fine Tuning

Adds detailed model controls to the game's existing **Advanced settings** form. Each API endpoint and model has its own saved profile.

**Open:** load or start a campaign → **Game menu → Settings → AI → Additional → Advanced settings**. Enable **Use profile**, set the parameters and click **Apply**.

- Automatic image support detection: API metadata or a short image check on first use, cached per API/model. Advanced settings offer Enabled and Disabled overrides.
- Context window and maximum response length.
- Response timeout.
- Reasoning effort, including disabling reasoning when supported.
- Response verbosity, temperature and top-p.
- Permission to include images in model input.
- Additional generation parameters as JSON.
- Refresh model capability information and select API parameter formats.
- Save, apply and reset the current connection's profile.

Empty values and automatic mode leave the corresponding parameters to the game. Supported values depend on the API and model; enabling image input does not give a text-only model vision. The endpoint, model and key stay in the game's connection settings. Keys are not copied into profiles.

Works independently and alongside Harness. In the standard game, settings are available after loading a campaign. The repository also contains a launcher component, which works only when integrated into a game fork.

Full Russian and English follow the game language. Other languages fall back to English. For **Pax Universe 0.31.6**.
