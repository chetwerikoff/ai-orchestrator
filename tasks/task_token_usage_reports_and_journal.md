# User ASK

## Goal

Добавить подробный отчёт по расходу токенов после каждого вызова ключевых скриптов проекта: создания задачи с ревью и выполнения AI Loop.

После каждого запуска пользователь должен видеть понятный отчёт: сколько токенов потратила каждая модель, сколько ушло на каждую итерацию, и какой это процент от доступных лимитов по текущему тарифному плану: суточного, недельного и месячного, если такие лимиты существуют и могут быть определены.

Также нужно вести подробный журнал расхода токенов и сохранять эту информацию для последующего анализа.

## Affected files (your best guess ? planner will verify)

-

## Out-of-scope (explicit boundaries)

-

## Proposed approach (optional)

Нужно изучить текущие скрипты запуска и точки вызова моделей в проекте, особенно сценарии:

- создание задачи с ревью;
- выполнение AI Loop / task-first loop;
- итерационные вызовы coding/review/planner агентов;
- сохранение итоговых статусов и логов в `.ai-loop`.

Требуемое поведение:

1. После каждого запуска скрипта должен выводиться итоговый отчёт в терминал.

   Пример структуры отчёта:

   ```text
   ==============================
   TOKEN USAGE REPORT
   Task: 003_add_order_queue_support
   Script: ai_loop_task_first.ps1
   ==============================

   Total:
   - Input tokens: ...
   - Output tokens: ...
   - Total tokens: ...

   By model:
   - Claude Sonnet: ...
   - GPT / Codex: ...
   - Qwen local: ...
   - Other: ...

   By iteration:
   - Iteration 1:
     - Model: ...
     - Input tokens: ...
     - Output tokens: ...
     - Total tokens: ...
   - Iteration 2:
     ...

   Limits:
   - Daily: ... used / ... limit / ...%
   - Weekly: ... used / ... limit / ...%
   - Monthly: ... used / ... limit / ...%
   ```

2. Если лимиты тарифа неизвестны или не применимы, отчёт должен явно писать это, а не выдумывать значения.

   Пример:

   ```text
   Daily limit: unknown for current provider/plan
   Weekly limit: not applicable
   Monthly limit: unknown
   ```

3. Для локальных моделей лимиты тарифа обычно не применяются.

   Для локального inference нужно отдельно показывать:

   - модель;
   - примерное количество prompt/eval tokens, если доступно из логов;
   - время обработки;
   - tokens/sec, если доступно;
   - что billing/subscription limit не применяется.

4. Нужно сохранять подробный журнал в файл/файлы.

   Возможные варианты:

   ```text
   .ai-loop/token_usage.jsonl
   .ai-loop/token_usage_summary.md
   .ai-loop/reports/token_usage_<timestamp>.md
   ```

   Точный формат должен определить planner, но важно:

   - журнал должен быть append-only или безопасно версионироваться;
   - каждая запись должна содержать task name / task id;
   - script name;
   - timestamp;
   - iteration number;
   - provider;
   - model;
   - input tokens;
   - output tokens;
   - total tokens;
   - estimated cost, если возможно;
   - лимиты и проценты, если возможно;
   - источник данных: API response, CLI log, llama.cpp log, estimate, unknown.

5. Нужно предусмотреть разные источники данных.

   Возможные источники:

   - API responses, где usage возвращается явно;
   - CLI logs, где usage печатается в stdout/stderr;
   - локальные llama.cpp / llama-server логи;
   - fallback estimate, если точных usage-данных нет;
   - unknown, если невозможно корректно оценить.

6. Важно отличать точные данные от оценок.

   В отчёте и журнале должно быть явно видно:

   - `exact`;
   - `estimated`;
   - `unknown`.

7. Нужно подумать, где хранить информацию о тарифных лимитах.

   Возможный вариант:

   ```text
   config/token_limits.yaml
   ```

   или секция в существующем конфиге проекта.

   Конфиг может содержать:

   ```yaml
   providers:
     anthropic:
       plan: pro
       daily_limit_tokens: null
       weekly_limit_tokens: null
       monthly_limit_tokens: null
     openai:
       plan: plus_or_api
       daily_limit_tokens: null
       weekly_limit_tokens: null
       monthly_limit_tokens: null
     local:
       plan: local
       daily_limit_tokens: null
       weekly_limit_tokens: null
       monthly_limit_tokens: null
   ```

   Planner должен критически оценить, есть ли смысл хранить лимиты именно в токенах, потому что многие подписки имеют лимиты не в токенах, а в сообщениях, compute units, rate limits или rolling windows.

8. Нужно не ломать текущие сценарии запуска.

   Если сбор usage невозможен, скрипт не должен падать. Он должен завершаться успешно и писать, что usage не найден.

9. Желательно добавить тесты на:

   - парсинг usage из типовых логов;
   - агрегацию usage по итерациям;
   - генерацию итогового отчёта;
   - fallback при unknown usage;
   - сохранение JSONL/MD журнала;
   - отсутствие падения при неполных данных.

## Constraints / context the planner may not know

- Пользователю нужен отчёт после каждого вызова скрипта, а не только по завершении большого workflow.
- Особенно важны скрипты: создание задачи с ревью и выполнение петли.
- Отчёт должен быть подробным: по моделям, по итерациям, total, лимиты и проценты.
- Нельзя выдумывать лимиты тарифов, если они неизвестны или провайдер не даёт точные данные.
- У разных провайдеров лимиты могут быть не токенными: сообщения, usage pool, rate limit, rolling window, compute units.
- Нужно явно помечать точность данных: exact / estimated / unknown.
- Для локальных моделей billing-лимиты не применяются, но токены, время и скорость всё равно полезно сохранять.
- Нужно вести постоянный журнал, чтобы потом анализировать стоимость, эффективность моделей и расход по задачам.
- Изменение не должно ломать существующий AI Loop.
- Если нет понимания, какие конкретно файлы менять, planner должен сначала изучить текущую архитектуру проекта, scripts, docs и существующий формат `.ai-loop` артефактов.
