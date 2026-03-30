# Сжатие контекста в AI-агентах: исследование и решения OpenClaw

## Проблема

Когда диалог растёт, модель теряет фокус — это называется **context rot**. Чем больше токенов, тем хуже recall. Это не баг — это архитектурное ограничение трансформеров (n² pairwise relationships). Результат: "просевший интеллект" в длинных сессиях.

---

## Что уже есть в OpenClaw (готовые решения)

### 1. Auto-compaction (включено по умолчанию)
Когда сессия приближается к лимиту контекстного окна, OpenClaw автоматически:
- Суммаризирует старую историю в компактную запись
- Сохраняет последние сообщения дословно
- Персистит summary в JSONL-транскрипте

**Конфиг:** `agents.defaults.compaction` в `openclaw.json`

### 2. Memory flush перед compaction
Перед сжатием OpenClaw запускает **тихий** agentic-ход, который записывает важный контекст на диск (`memory/YYYY-MM-DD.md`). Это страховка — даже если compaction потеряет детали, они сохранены в файлах.

**Конфиг:** `agents.defaults.compaction.memoryFlush` (включено по умолчанию)

### 3. Session pruning
Отдельный механизм: обрезает старые **tool results** в памяти (не в файле). Работает параллельно с compaction.

### 4. Ручная compaction
Команда `/compact` с опциональными инструкциями:
```
/compact Сфокусируйся на решениях и открытых вопросах
```

### 5. Настраиваемые параметры compaction

| Параметр | Что делает | По умолчанию |
|----------|-----------|-------------|
| `mode` | `default` или `safeguard` (строже хранит контекст) | `default` |
| `reserveTokens` | Запас токенов для ответа после compaction | 16384 |
| `keepRecentTokens` | Сколько последних токенов хранить дословно | 20000 |
| `reserveTokensFloor` | Минимальный floor для reserve | 20000 |
| `maxHistoryShare` | Доля контекста для истории (0.1-0.9) | — |
| `recentTurnsPreserve` | Сколько последних ходов хранить дословно | 3 |
| `model` | Отдельная модель для суммаризации | основная модель |
| `customInstructions` | Свои инструкции для суммаризации | — |
| `qualityGuard` | Аудит качества summary + retry | отключен |

### 6. Модель для compaction
Можно использовать **другую модель** для суммаризации — дешевле и быстрее:
```json
{
  "agents": {
    "defaults": {
      "compaction": {
        "model": "openrouter/anthropic/claude-sonnet-4-5"
      }
    }
  }
}
```

---

## Лучшие практики из индустрии (2025-2026)

### Anthropic: Context Engineering (официальная рекомендация)
Источник: [anthropic.com/engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

- Контекст — конечный ресурс с **убывающей отдачей**
- Цель: **минимальный набор высокосигнальных токенов**
- Системный промпт: не жёсткий if-else, не расплывчатый — баланс конкретики и гибкости
- Anthropic Claude SDK имеет встроенный `compaction_control` параметр

### Factory.ai: Anchored Iterative Summarization
Источник: [factory.ai/news/evaluating-compression](https://factory.ai/news/evaluating-compression)

Тестировали 3 подхода на реальных сессиях (отладка, code review, фичи):

| Подход | Плюсы | Минусы |
|--------|-------|--------|
| **Factory (structured summary)** | Лучшее сохранение контекста, sections-чеклист | Чуть больше токенов |
| **OpenAI /responses/compact** | Рекордное сжатие 99.3% | Непрозрачный, нечитаемый output |
| **Anthropic SDK** | Хорошие structured summaries 7-12k | Полный пересчёт каждый раз |

**Ключевой инсайт:** правильная метрика — не "токены на запрос", а **"токены на задачу"**. Агрессивное сжатие экономит на запросе, но тратит больше на повторное изучение файлов.

### Google ADK: Context Compaction
- Автоматическое сжатие старых событий workflow
- Суммаризация только старой части, недавнее остаётся

### Microsoft Agent Framework
- Три стратегии: remove, collapse, summarize
- Рекомендуют комбинировать

### Академия: Acon (Agent Context Optimization)
Источник: [arxiv.org/html/2510.00615](https://arxiv.org/html/2510.00615v1)
- Оптимальное сжатие histories + observations в concise summaries
- Снижает peak tokens и memory

### Свежее (март 2026): PoC — Performance-oriented Compression
Источник: [arxiv.org/html/2603.19733](https://arxiv.org/html/2603.19733)
- Адаптивный budget сжатия на уровне каждого sample
- Сегменты контекста получают разный compression ratio по informativeness

---

## Рекомендации для знакомого

### Быстрые шаги (5 минут)
1. **Проверить что compaction включен:**
   ```
   /status
   ```
   Должно показывать compaction count

2. **Поднять keepRecentTokens** если "забывает" недавнее:
   ```json
   "compaction": { "keepRecentTokens": 30000 }
   ```

3. **Включить mode: "safeguard"** для более бережного сжатия:
   ```json
   "compaction": { "mode": "safeguard" }
   ```

4. **Использовать `/compact` вручную** с инструкциями перед сложной работой

### Средние шаги (30 минут)
5. **Настроить SOUL.md** с секцией Compaction — инструкции что сохранять при сжатии
6. **Включить memoryFlush** — запись важного на диск перед compaction
7. **Поставить отдельную модель для compaction** (дешевле + быстрее)

### Продвинутые шаги
8. **customInstructions** — свои правила суммаризации:
   ```json
   "compaction": {
     "customInstructions": "Обязательно сохраняй: пути файлов, решения, текущий статус задачи, имена функций"
   }
   ```
9. **qualityGuard** — аудит качества summary с retry
10. **Уменьшить системный промпт** — `/context detail` покажет что жрёт токены

---

## Ссылки

- [OpenClaw: Compaction docs](https://docs.openclaw.ai/concepts/compaction)
- [Anthropic: Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Factory.ai: Evaluating Compression](https://factory.ai/news/evaluating-compression)
- [Factory.ai: Compressing Context](https://factory.ai/news/compressing-context)
- [Anthropic: compaction_control cookbook](https://platform.claude.com/cookbook/tool-use-automatic-context-compaction)
- [Google ADK: Context Compaction](https://google.github.io/adk-docs/context/compaction/)
- [Microsoft: Compaction](https://learn.microsoft.com/en-us/agent-framework/agents/conversations/compaction)
- [Getmaxim: Context Window Management](https://www.getmaxim.ai/articles/context-window-management-strategies-for-long-context-ai-agents-and-chatbots/)
- [Jason Liu: Experiments on Compaction](https://jxnl.co/writing/2025/08/30/context-engineering-compaction/)
