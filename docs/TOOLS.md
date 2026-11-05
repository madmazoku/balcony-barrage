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
