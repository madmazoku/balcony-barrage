# Реестр инструментов
Сначала искать уже существующее средство. Не создавать вторую утилиту для той же операции.

| Средство | Назначение |
|---|---|
| G:/Git/Godot/Godot_v4.7.2-stable_win64_console.exe | Импорт, проверка скриптов, запуск и экспорт Godot |
| tools/validate_foundation.gd | Проверяет загрузку текущего конфига и контракта пакета |
| gh и git | Работа с репозиторием по локальному навыку add-to-master |
| media_mcp image_generate, media_get_models, media_get_loras | Штатный путь генерации и инспекции, фаза 4 и далее |
| media_mcp video_generate | Проба фоновой анимации в фазе 5 после чтения video-scenario |

## Уже найдено в G:/Git/Gemini
scripts/a1111_generator.py и scripts/comfyui_generator.py, а также одноимённый comfyui_generator.py в корне. Это существующие генераторы, сначала читать назначение и интерфейс, не плодить новые обёртки.
scripts/scenario_video_pipeline.py, scripts/video_extender.py, scripts/verify_overlap.py и scripts/test_stitch.py — существующие утилиты видео. Основной путь остаётся media_mcp.
scripts/inspect_*.py, scripts/check_*.py, scripts/debug_*.py — диагностика генерации и окружения. Перед новой диагностикой искать здесь.
Это инвентаризация имён, работоспособность перечисленных внешних скриптов в этой фазе не проверялась.
Утилиты вне проекта могут выполняться в G:/Git/Gemini, но воспроизводимая сборка и проверки самой игры должны входить в репозиторий игры. Новую утилиту записать сюда с назначением и примером вызова.

## Добавлено в фазе 2
- tools/test_round.gd — проверка механики и обычного ввода сцены. Вызов: Godot --headless --path <project> --script res://tools/test_round.gd. Переиспользовать при изменении боя.

## Добавлено в фазе 3
- tools/test_controls.gd — проверка геймпадных, сенсорных и мышиных событий через игровую сцену. Запуск Godot --headless --path <project> --script res://tools/test_controls.gd. Без --headless также выводит имена реально обнаруженных геймпадов. Существующий test_round.gd остаётся проверкой боя.

## Добавлено в фазе 4
- G:/Git/Gemini/scripts/sprite_assets.py — подготовка масок img2img (mask, несколько --rect), зелёного ключа (cutout), тестовое выделение металла (metal-layer), сборка слоёв (stack), обзоры (preview/board). Pillow 11.3.0. Вызов python scripts/sprite_assets.py --help из Gemini. Использовать повторно. metal-layer — эвристика, после неё обязательно смотреть контуры, не считать автоматическую вырезку готовым игровым ресурсом.
- Возможность рисовать объектный референс арбалета удалена по требованию владельца. Финальные изображения оружия и брони получают через генерацию. Допускается только детерминированная подготовка масок, alpha и композиция уже сгенерированных пикселей.

## Проверки и сборка статичного пакета
- sprite_assets.py build-pack --manifest art/build-static-pack.json запускается из корня игры, использует сохранённые source PNG, пишет все PNG и pack.tres. Все операции подготовки расширяют существующую утилиту.
- tools/test_asset_pack.gd проверяет обязательные слоты, alpha, ошибочные пакеты и одинаковый seed-бой при смене оформления через реальную сцену.
- tools/capture_pack.gd сохраняет кадр обычной сцены: Godot --path <project> --script res://tools/capture_pack.gd -- --capture=<PNG> --scenario=mixed --pose=up --armor=3 --stage=0. Нужен графический запуск. Это QA-инструмент, не элемент меню.

Дополнения sprite_assets.py: crop — точная вырезка; paste-edit — размещение сгенерированного фрагмента; apply-edit — строгое сохранение пикселей вне маски. build-pack читает balcony_preparation и собирает одинаково привязанные состояния балкона из исходного настила, сгенерированной обшивки и сломанных подпорок. Новых дублирующих утилит не создано.

Для tools/capture_pack.gd добавлен --fall-time=<секунды>: воспроизводит настоящее последнее обрушение и снимает боссa через указанное время падения. Например --scenario=boss --fall-time=0.5 показывает босса в воздухе без экрана победы.

## Web и GitHub Pages (AI-5)
- export_presets.cfg / Web — штатный однопоточный экспорт в builds/web/index.html; подробная команда и установка шаблонов в README.
- .github/workflows/web-pages.yml — проверка PR и публикация только master после успешных проверок. Официальные редактор/шаблоны 4.7.2 скачиваются с godotengine/godot-builds, сверяются SHA512 и кешируются.
- python -m http.server 8765 --bind 127.0.0.1 --directory builds/web — существующий стандартный сервер для локального теста. Не писать дополнительный сервер или оболочку экспорта. Для проверки публичной версии использовать сайт и commit.txt/version.txt.
- Visual Studio Community 2026 обнаружен. Android-каталог доступных компонентов присутствует, но установленный набор не содержит Android/JDK; SDK не найден по стандартным путям/реестру. Не считать наличие Visual C++ готовностью экспорта APK.

sprite_assets.py build-pack читает weapon_transforms.right/up из art/build-static-pack.json. Исправлять привязки оружия здесь, не вводить смещения в боевом коде и не возвращать старые координаты в утилиту.

Поле balloon_rope_anchor манифеста переносится build-pack в ресурс пакета и описывает нормализованное крепление верёвки к хвостику шарика; не сдвигать ради этого игровые центры в round_model.gd.

## Первая группа анимаций (AI-7)
- scripts/config/feedback_config.gd / assets/packs/rescue_rangers/feedback.tres — визуальные параметры; исходные значения в feedback манифеста подготовки.
- scripts/game/round_feedback.gd — только временное состояние/траектории, без боевого RNG и коллизий.
- tools/test_feedback.gd — проверка событий попадания, правильной детали при краже, кулдауна, паузы/возобновления/очистки и независимости боя от выключенных эффектов. Запуск как прочие проверки; добавлена в CI.
- sprite_assets.py build-pack расширен опциональными feedback, pop_sheet и sources.balloon_pop. Принятые статичные PNG не меняются; выход 63 PNG при включённой первой группе. Обрезка ячеек, уменьшение и HSV-варианты детерминированы. Не создавать отдельную утилиту анимационных ресурсов.
- capture_pack.gd расширен --feedback, --feedback-time, --frames, --step; команды и приёмка в README. Дёргает реальные события боя, затем пошагово снимает представление. Для монтажа GIF использован существующий E:/Git/ffmpeg/bin/ffmpeg.exe (crop/scale/hstack/palettegen/paletteuse), отдельного скрипта не добавлено.

## Принятая группа 2 (AI-8, 0.8.0)
sprite_assets.py build-pack расширен опциональным actor_actions в прежнем манифесте. Сохраняет полный холст действий, производные палитры и явные shared-слоты; обновляет source-index.json и checksums.json. Итог 75 PNG; прежние 63 сохраняются побайтно.
capture_pack.gd: --feedback=windup|capture, --simulate=true, --role=normal|tank|thrower, --side=-1|1. При simulate=true кадры продвигаются настоящим _physics_process, поэтому работают замах/гайка/побег; без него прежний изолированный предпросмотр эффектов сохраняется. Пример: --scenario=boss --feedback=capture --role=tank --side=-1 --armor=2 --simulate=true --frames=40 --step=0.04. Монтаж снова выполнен существующим FFmpeg, без новой утилиты.

## Принятая группа 3 (AI-9, 0.9.0)
- scripts/config/motion_config.gd / motion.tres — дистанция цикла и величина подпрыгивания, без игровых скоростей.
- scripts/game/round_motion.gd — состояние пройденного расстояния и выбор кадра; использует фактические позиции, не предсказывает и не меняет бой.
- tools/test_motion.gd — реальная сцена: движение, край экрана, остановка, пауза, сброс, все роли/направления/побег и одинаковый бой с включённым/отключённым бегом. Включён в CI шестой проверкой.
- sprite_assets.py build-pack расширен опциональным locomotion, читает фиксированную верхнюю полосу игрока и явные последовательности. Повторно используется прежняя утилита, не создавать отдельный генератор кадров.
- capture_pack.gd: --feedback=run --role=player|normal|tank|thrower --side=-1|1 --simulate=true --focus=actor --frames=32 --step=0.04. --pose=up реально стреляет вверх при готовом кулдауне; --state=escape --part=2 показывает побег с деталью. focus=actor — увеличиваемая вырезка только для QA, обычный игровой рендер не изменён. GIF собран прежним FFmpeg.

## Доработка группы 3 и поражения
- sprite_assets.py build-pack: enemy_sources.extra_sources/sequence, boss как один вариант палитры. Гаечка использует прежний путь подготовки без изменений.
- tools/test_defeat.gd: проверка фактических событий урона, визуального носителя, оружия, направления вылета, остановки боя, P/R и выключенных эффектов. Включён седьмой проверкой CI. Вызывать Godot --headless --path <project> --script res://tools/test_defeat.gd --quit-after 600.
- capture_pack.gd: --feedback=run --role=boss; --feedback=defeat --cause=capture|nut|furniture --role=normal|tank|thrower --side=-1|1 --pose=right|left|up --simulate=true --frames=90 --step=0.04. Захват/попадание вызывают реальные процедуры модели, кадры после lose продвигают только визуальную реакцию. Предпросмотр/монтаж выполнены прежним FFmpeg.

## Принятая группа 4 (AI-10, 0.10.0)
- Существующий sprite_assets.py build-pack читает опциональный boss_actions.entries (source → полный кадр), props (отдельные предметы), settings (BossActionConfig), сохраняет регистрацию, provenance и checksums. Не создавать второй генератор.
- scripts/game/boss_actions.gd — только состояние представления и выбор позы; scripts/config/boss_action_config.gd — визуальные параметры пакета.
- tools/test_boss_actions.gd — реальные события выпусков/мебели/попадания и приземления, приоритет обрушения, целостность пакета, пауза/сброс и неизменность полного боя/RNG. Команда как у остальных проверок, --script res://tools/test_boss_actions.gd --quit-after 600; ожидается BOSS_ACTION_TESTS_OK. Восьмая проверка CI.
- capture_pack.gd расширен --feedback=boss_release|boss_throw|boss_jump --scenario=boss --simulate=true --role=boss --frames=55 --step=0.04. Для окончательного падения прежний --fall-time=0 --feedback=none, затем simulate=true. Это QA-сценарии, не отдельный игровой режим. Монтаж — прежний FFmpeg/Pillow.

Доработка бега босса: текущий build-pack уже поддерживает нужные extra_sources/sequence, новый генератор не создавался. Восемь исходных фаз и gait-recipe.json хранятся в boss_gait_fix. MotionConfig.bob_cycles и BossActionConfig.walking_split_fraction сериализуются прежним механизмом settings. Сравнение нативных серий — capture_pack.gd --feedback=run --role=boss --side=1/-1 --focus=actor --simulate=true --frames=64 --step=0.04.

## Принятая группа 5: фон (AI-11, 0.11.0)
- Прежний G:/Git/Gemini/scripts/sprite_assets.py build-pack расширен опциональным ambient: восстановление стены по clean_mask из clean_source, выделение оригинальных листьев по сохранённым alpha-маскам, crop, сериализация AmbientConfig. Зелёный цвет листьев НЕ удалять через green_cutout. Все маски/исходники в art/sources/rescue_rangers/ambient, параметры в art/build-static-pack.json. Внешняя утилита остаётся одна; SHA256 текущей версии C749E7A2E1ADDE200256D5279DB7E69A21ED4B3609BAC5857906452E79165FD2.
- scripts/config/ambient_config.gd и scripts/game/round_ambient.gd — опциональная конфигурация пакета и чистое визуальное состояние. Не добавлять к ним изменения модели/RNG.
- tools/test_ambient.gd — девятая проверка: маски/полнота пакета, движение и неподвижные концы, границы амплитуды, шов цикла, пауза/сброс/исход, static/prototype и одинаковый полный бой. Запуск прежним Godot --headless --script res://tools/test_ambient.gd; ожидается AMBIENT_TESTS_OK.
- Прежний capture_pack.gd расширен --feedback=ambient --scenario=boss --frames=120 --step=0.1 --capture=<absolute PNG>. Без simulate=true движется только фон, серия содержит цикл 12 секунд. GIF собран Pillow из настоящих кадров игры; не отдельный генератор изображений. Для полного боя оставить обычный запуск.

## Принятая фаза 6, группа 1 (AI-12, 0.12.0)
- scenes/app.tscn, scripts/game/game_shell.gd — обычная точка входа и меню с существующим раундом. scenes/main.tscn по-прежнему используется в прежних проверках и для F6 QA.
- GameProfile (scripts/game/game_profile.gd) — ConfigFile в user://profile.cfg, безопасная запись через .tmp, предпочтения и рекорд побед по ключу GameplayConfig. Тесты используют отдельные qa-profile/qa-shell файлы и удаляют только собственные файлы, не трогая реальный профиль.
- tools/test_profile.gd и test_shell.gd — сохранение/повторная загрузка, неверные данные, изоляция рекордов и реальная сцена с событиями клавиатуры/геймпада, меню, паузой/фокусом и последовательностью финалов. Ожидается PROFILE_TESTS_OK и SHELL_TESTS_OK. Теперь в CI 11 проверок.
- Прежний capture_pack.gd расширен --shell=home|pause|help|settings|result|playing, сцену меню не дублировать. Без --shell остаётся прежний захват main.tscn.
- Прежний sprite_assets.py build-pack сериализует путь shell_style как ui.shell_style. SHA256 версии после расширения: 3896262f21f88ee1d377da5ce564822ced79d425f871d1c59144908254f618df. Внешняя утилита остаётся одна, все 122 PNG сохранены.
