# Gorcer Tech — Topic 75 — Context

Last saved: 2026-03-30

## Summary

Топик про операционку и CI/CD — пуши в git, деплой скрипты, прокси.

---

## Updates 2026-03-30

### Что произошло
- Егор попросил запушить yandex_proxy.py в GitHub
- Раиса запушила в https://github.com/gorcer/openclaw-deploy (ветка main)
- Пришлось убрать API-ключи из файлов (GitHub Secret Scanning заблокировал пуш)
- Плейсхолдеры: `YANDEX_API_KEY_PLACEHOLDER`, `YANDEX_FOLDER_ID_PLACEHOLDER`

### Файлы запушены
- `scripts/yandex_proxy.py` — прокси TTS/STT/OCR
- `systemd/yandex-proxy.service` — systemd unit
- `scripts/vpn2_health.sh`, `scripts/save_group_contexts.py`
- `clients/test-client-1/` — docker configs
- `groups/`, `tasks/`, `research/`

### Решения
- Git remote: origin → https://github.com/gorcer/openclaw-deploy
- Ветка: main (не master)
- При деплое — подставить реальные YANDEX_API_KEY и YANDEX_FOLDER_ID

### Задачи
- При деплое yandex_proxy — не забыть задать реальные ключи в Environment

### ⚠️ Баг
- `gor reset --hard` убивает локальные файлы! Нельзя делать когда есть несохранённые изменения
