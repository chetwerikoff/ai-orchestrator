---
report_type: architecture_review
source_document: task.md
source_document_version: 2026-05-11
reviewer_role: senior_architect / AI-agent workflow reviewer
reviewer_model: claude-opus-4.7
review_date: 2026-05-11
target_system: ai-git-orchestrator
target_project_example: H2N_parser/h2n-range-extractor
language: ru
machine_readable: true
verdict_schema: PASS | FIX | ESCALATE
finding_severity_schema: critical | high | medium | low | info
recommendation_priority_schema: P0 | P1 | P2 | P3
---

# Architecture Review Report

> Этот документ — структурированный отчёт по результатам ревью `task.md`.
> Формат рассчитан на машинный разбор следующим LLM-агентом и на использование
> в качестве input'а для пере-планирования архитектуры. Каждый блок имеет
> уникальный ID. Парсер должен опираться на ID, а не на порядок секций.

---

## 0. Metadata

```yaml
report_id: AR-2026-05-11-001
overall_verdict: FIX
overall_verdict_summary: >
  Концепция верна, но реализация перегружена примерно в 2-3 раза
  по числу LLM-вызовов и состояний. MVP должен быть радикально упрощён
  до 8 стадий вместо 18. Custom orchestrator сохранить, готовые фабрики
  (Composio AO и пр.) не интегрировать.
critical_findings_count: 4
high_findings_count: 6
medium_findings_count: 5
recommendations_count: 17
p0_recommendations: 6
estimated_mvp_effort_weeks: 1-2
```

---

## 1. Scope of Review

```yaml
in_scope:
  - role_split: Qwen / Codex / Claude
  - end_to_end_flow: 18 stages described in task.md section 4
  - cli_contracts: between agents and orchestrator
  - orchestrator_choice: custom vs Composio AO vs Claude Squad vs Vibe Kanban vs OpenHands
  - mvp_definition
  - failure_modes
  - guardrails

out_of_scope:
  - specific_prompts_design
  - hardware_sizing_for_local_qwen
  - cost_modeling_in_usd
  - actual_code_implementation
```

---

## 2. Findings

Каждый finding имеет уникальный `id`, `severity`, ссылку на источник в `task.md`
(`source_stage`), доказательство и рекомендуемое действие. Парсер должен брать
finding'и как массив объектов.

---

### F-01 — Cheap LLM summarizers as information loss layers

```yaml
id: F-01
severity: high
source_stages: [stage_2, stage_10, stage_14]
category: architecture
```

**Observation.** В `task.md` присутствуют три отдельные стадии «cheap summarizer»
на локальном Qwen: context summarizer (Stage 2), iteration summarizer (Stage 10),
business summary (Stage 14). Каждая стадия принимает «сырьё» (логи, дифф,
context) и отдаёт сжатое markdown-резюме для более сильной модели (Claude или
Codex).

**Problem.** Маленькая модель удаляет именно те детали (имена файлов, точные
ошибки тестов, конкретные строки stacktrace), на которые опирается сильная
модель downstream. Это noise-amplifying layer: дешёвая модель добавляет
галлюцинации и теряет факты, а потом дорогая модель принимает решение по
искажённой картине.

**Evidence.**

- Claude Sonnet 4.5 поддерживает ~200k токенов контекста — типичный
  `context_raw.md` для одной задачи (git status + diff + pytest --collect-only +
  rg для домена) укладывается в 10-30k токенов и не требует сжатия.
- Codex при escalation review нужен **точный** stacktrace + точный diff, а не
  Qwen-нарратив о них.
- Сжатие 10 итераций маленькой моделью маскирует pattern repeated failures, по
  которому Codex обычно находит root cause.

**Recommendation.** Удалить все три summarizer-стадии в MVP. Заменить
детерминированными скриптами: `git diff`, `git log`, head/tail по логам.

**Related recommendations:** R-01, R-04, R-07.

---

### F-02 — Self-review collusion between Qwen Coder and Qwen Reviewer

```yaml
id: F-02
severity: critical
source_stages: [stage_8, stage_9]
category: review_signal_quality
```

**Observation.** В Stage 8 Qwen Reviewer описан как отдельный OpenCode-агент,
но на той же модели (local Qwen). В Stage 9 описан loop Qwen Coder ↔ Qwen
Reviewer до 10 итераций.

**Problem.** Reviewer и Coder одной модели имеют **одинаковые слепые пятна**.
Они одинаково неверно понимают неоднозначную часть `task.md`, одинаково
пропускают edge cases, одинаково оценивают «достаточно ли тестов». Это не
независимое ревью — это иллюзия ревью.

**Evidence.**

- Классический паттерн «judge same family as actor» хорошо документирован в
  multi-agent literature (см. self-consistency, LLM-as-judge biases).
- В `task.md` сам автор отмечает Stage 8 как primary review gate перед Codex,
  что переносит критический путь на коллизионный сигнал.

**Recommendation.** В MVP убрать Qwen Reviewer с критического пути. Primary
gate — pytest + smoke (объективный сигнал). Secondary gate — Codex (другая
семья моделей, независимый сигнал). Qwen Reviewer возможен только как v2
оптимизация и только на **другой** модели (например DeepSeek-Coder), не на
том же Qwen.

**Related recommendations:** R-02, R-05.

---

### F-03 — Retry loop with 10 iterations creates expanding diff

```yaml
id: F-03
severity: high
source_stages: [stage_9]
category: control_flow
```

**Observation.** Stage 9 описывает retry loop до 10 итераций между Qwen Coder
и Qwen Reviewer.

**Problem.** Эмпирический паттерн в LLM coding agents: после 3 неудачных
итераций диагноз почти всегда один из двух — (a) `task.md` неверно
сформулирован, либо (b) задача за пределами способностей модели. В обоих
случаях дополнительные итерации не помогают, а **наращивают diff** (модель
пробует разные подходы и забывает откатить предыдущие). Это даёт неминимальный
PR и затрудняет финальное ревью.

**Evidence.**

- В Stage 9 автор сам перечисляет early-escalation triggers («same test fails
  3 times», «diff keeps growing»). Эти тригеры показывают, что автор уже
  понимает: после 3 неудач сигнал стабилизируется.

**Recommendation.** Жёсткий cap = 3 итерации. После cap → STOP → требовать
human review. Не пытаться автоматизировать диагностику почему цикл застрял —
это самая хрупкая часть схемы.

**Related recommendations:** R-03.

---

### F-04 — Verdict state space too large for LLM discipline

```yaml
id: F-04
severity: high
source_stages: [stage_8, stage_11, stage_13, stage_15]
category: parsing_robustness
```

**Observation.** Across stages введено 13+ verdict-состояний: `APPROVED`,
`NEEDS_FIX`, `NEEDS_ESCALATION`, `FIXABLE_BY_QWEN`, `TASK_TOO_BROAD`,
`NEEDS_REPLAN_BY_CLAUDE`, `NEEDS_HUMAN_DECISION`, `ABANDON_AND_REPLAN`,
`APPROVED_TECHNICAL`, `NEEDS_REPLAN`, `APPROVED_BUSINESS_LOGIC`,
`NEEDS_BUSINESS_FIX`, `CREATE_FOLLOWUP_TASK`.

**Problem.** LLM плохо держит дисциплину enum'ов из 5+ значений. Будут
варианты вида `APPROVED_TECHNICAL_WITH_MINOR_CONCERNS`, и парсер оркестратора
либо упадёт, либо ошибочно приведёт это к `APPROVED`, что критично для
безопасности.

**Recommendation.** На любом gate — три значения: `PASS | FIX | ESCALATE`.
Дополнительные нюансы — свободный текст внутри отчёта, не enum.
Машинно-читаемый trailer формата:

```
---
VERDICT: PASS | FIX | ESCALATE
SUMMARY: <one line>
---
```

Fallback: если parser не нашёл VERDICT — auto FIX, никогда не PASS.

**Related recommendations:** R-06.

---

### F-05 — Codex appears twice without proven ROI from first invocation

```yaml
id: F-05
severity: medium
source_stages: [stage_11, stage_13]
category: cost_efficiency
```

**Observation.** Codex вызывается дважды: как escalation reviewer после
неудачного Qwen loop'а (Stage 11) и как final technical gate (Stage 13).

**Problem.** Escalation Review — это попытка автоматизировать «диагностику
застрявшего loop'а». На практике эта диагностика часто сводится к «task.md
сформулирован неоднозначно, нужен human или Claude replan». Платить Codex
токенами за этот вердикт — отрицательный ROI, пока не доказано иначе.

**Recommendation.** В MVP — один Codex вызов: final technical gate. Escalation
заменить правилом «3 strikes → human / Claude replan». Через 2-3 месяца
эксплуатации замерить: какой процент Codex Escalation review'ев приводит к
полезному `codex_fix_task.md`. Если < 50% — стадия лишняя; если >= 50% —
вернуть.

**Related recommendations:** R-03, R-08.

---

### F-06 — Forbidden changes contract not enforced deterministically

```yaml
id: F-06
severity: critical
source_stages: [stage_3, stage_8, stage_13]
category: security / cheating_prevention
```

**Observation.** В Stage 3 описано, что `task.md` содержит `Forbidden changes`.
Проверка их соблюдения возложена на Qwen Reviewer (Stage 8) и Codex
(Stage 13).

**Problem.** Это **самый частый и самый опасный** failure mode в LLM coding
agents: модель тихо меняет fixtures / golden outputs / expected snapshots,
чтобы тесты прошли. Если проверка возложена на другую LLM, она с заметной
вероятностью пропустит факт изменения forbidden пути.

**Recommendation.** Forbidden paths должны enforce'иться **детерминированно
оркестратором**, не LLM. Алгоритм:

1. `task.md` декларирует `Allowed paths` (whitelist) и `Forbidden paths`
   (blacklist).
2. После Coder-итерации: `git diff --name-only` фильтруется через whitelist.
3. Если затронут запрещённый путь — automatic FIX verdict, итерация
   считается неудачной, LLM в принятии решения не участвует.

Codex и Claude остаются как secondary check «было ли изменение легитимным
для тех файлов, что были разрешены».

**Related recommendations:** R-09, R-15.

---

### F-07 — Fake-pass via fixture manipulation not architecturally prevented

```yaml
id: F-07
severity: critical
source_stages: [stage_6, stage_7, stage_8]
category: security / cheating_prevention
```

**Observation.** Smoke test и unit tests описаны как primary objective signal,
но fixture-файлы (входы) находятся в репозитории и теоретически
модифицируемы Qwen Coder'ом.

**Problem.** Qwen может (а) изменить expected output fixture'ы, (б) поменять
input fixture на тривиальный кейс. Тесты пройдут, задача не решена.

**Recommendation.** В дополнение к F-06:

- Smoke test работает на **отдельной** input fixture, путь к которой
  отсутствует в `task.md` и которую Qwen не видит как «smoke test input».
- Snapshot/golden output files указаны в Forbidden paths.
- Codex final review **явно** проверяет: «изменены ли expected values /
  golden files — и было ли это легитимно по `task.md`».

**Related recommendations:** R-09, R-10.

---

### F-08 — Composio Agent Orchestrator vendor risk underestimated

```yaml
id: F-08
severity: medium
source_stages: [section_10_option_B, section_11_path_2]
category: dependency_risk
```

**Observation.** В `task.md` Composio AO позиционируется как сильнейший
кандидат на control plane.

**Problem.**

1. Composio AO — относительно молодой проект; breaking changes вероятны.
2. Их runtime-модель агента предполагает их формат task description, их
   способ управлять worktree'ами, их sequencing. Это противоречит
   уникальной ценности системы пользователя: строгая asymmetric цепочка
   `Qwen → Codex tech gate → Claude business gate`.
3. Адаптер для force'инга этой цепочки через Composio API окажется сложнее,
   чем нативная реализация (~500-800 строк Python).

**Recommendation.** Не интегрировать AO как control plane. Взять идеи
(worktree management, PR lifecycle) для собственного оркестратора.

**Related recommendations:** R-11.

---

### F-09 — Stacked PR introduced too early

```yaml
id: F-09
severity: medium
source_stages: [stage_18]
category: scope_management
```

**Observation.** Stage 18 предлагает stacked PR flow с branch-1 → branch-2
→ branch-3.

**Problem.** Stacked PR операционно сложен (rebase chains, merge conflicts
при изменении базовой ветки), и в первые 2-3 месяца эксплуатации почти
никогда не нужен. Введение его в MVP — преждевременная оптимизация.

**Recommendation.** Defer до milestone 4+. Один task = одна ветка = один
PR в MVP.

**Related recommendations:** R-12.

---

### F-10 — Git worktree introduced before parallelism is needed

```yaml
id: F-10
severity: low
source_stages: [stage_4]
category: scope_management
```

**Observation.** Stage 4 предлагает worktree-per-task с самого начала.

**Problem.** Worktree даёт ценность только когда есть параллельные задачи.
В MVP, где валидируется единичная цепочка end-to-end, простая
`git checkout -b ai/<slug>` проще и меньше движущихся частей.

**Recommendation.** Простой branch в MVP. Worktree-per-task в milestone 2,
когда захочется 2+ параллельных задач.

**Related recommendations:** R-13.

---

### F-11 — Three Qwen "personas" are one model with three prompts

```yaml
id: F-11
severity: low
source_stages: [stage_2, stage_8, stage_10, stage_14]
category: nomenclature_complexity
```

**Observation.** В `task.md` фигурируют `qwen-local-context`,
`qwen-local-coder`, `qwen-local-reviewer`, `qwen-local-summarizer` как
будто разные модели.

**Problem.** Это **одна модель** с разными промптами, и плодить «model
identities» создаёт ложное впечатление асимметрии review.

**Recommendation.** В терминологии и в CLI — одна модель `qwen-coder`,
разные роли через промпты в `prompts/`. Не претендовать на «специализацию»
там, где её нет.

---

### F-12 — Smoke test contract is loose

```yaml
id: F-12
severity: medium
source_stages: [stage_7]
category: signal_quality
```

**Observation.** Smoke test описан как «CLI starts, input is readable,
output is created». Это слишком слабая планка — Qwen может пройти такой
smoke, ничего не сделав по существу задачи.

**Problem.** Если smoke просто запускает `--help` или checks
non-emptiness — он не различает «корректное решение» и «отсутствие краха».

**Recommendation.** Smoke test должен проверять конкретный **бизнес-инвариант**
текущей задачи (для H2N: «парсер на эталонном input выдал N stat'ов в
expected секциях с правильной группировкой»). Claude Planner в `task.md`
обязан явно описать какие инварианты должен проверять smoke.

**Related recommendations:** R-14.

---

### F-13 — Cost tracking absent from architecture

```yaml
id: F-13
severity: medium
source_stages: [all]
category: operations
```

**Observation.** `task.md` подробно описывает где использовать дорогие модели
(Codex, Sonnet), но не описывает измерение фактической стоимости.

**Problem.** Через 4-6 недель эксплуатации без логирования стоимости
пользователь обнаружит, что Codex+Sonnet съели больше, чем стоит вся
локальная инфраструктура. Без данных нельзя оптимизировать.

**Recommendation.** Per-task логирование токенов в `.ai-loop/cost.jsonl`
с первого дня. Daily/weekly cap — оркестратор отказывается стартовать новые
задачи, если бюджет исчерпан.

**Related recommendations:** R-16.

---

### F-14 — Secret leakage not addressed in commit/PR stage

```yaml
id: F-14
severity: high
source_stages: [stage_16, stage_17]
category: security
```

**Observation.** Stage 16-17 описывают `git commit` и `gh pr create` без
secret-scanning.

**Problem.** Local Qwen может непреднамеренно скопировать значения из `.env`
или закешированных секретов в код или fixtures. Без проверки эти секреты
уйдут в PR.

**Recommendation.** Pre-commit hook через `gitleaks` или `detect-secrets`.
Оркестратор отказывается коммитить если detect fail.

**Related recommendations:** R-17.

---

### F-15 — No timeout/health-check contract for local Qwen

```yaml
id: F-15
severity: medium
source_stages: [stage_5, stage_8, stage_12]
category: reliability
```

**Observation.** Все OpenCode + local Qwen вызовы описаны без timeout'ов и
без health check'а перед стартом loop'а.

**Problem.** Local inference сервер (llama.cpp / Ollama / LM Studio) может
зависнуть, переполнить VRAM, отдать частичный ответ. Без timeout'а
оркестратор зависнет навсегда.

**Recommendation.** Subprocess timeout per call (suggested 10 min). Health
check перед стартом: `opencode --version` + ping endpoint. На timeout —
итерация = FAIL, идём дальше или escalate.

**Related recommendations:** R-15.

---

## 3. Recommendations

Каждая рекомендация — отдельный объект с приоритетом, оценкой усилий и
зависимостями. Парсер должен использовать как backlog для дальнейшего
планирования.

```yaml
priority_legend:
  P0: "blocker for MVP, do first"
  P1: "should be in MVP"
  P2: "milestone 2+"
  P3: "nice to have / experiment"
```

---

### R-01 — Remove all three Qwen summarizer stages from MVP

```yaml
id: R-01
priority: P0
addresses: [F-01]
effort: small
depends_on: []
```

Удалить Stage 2 (context summarizer), Stage 10 (iteration summarizer),
Stage 14 (business summary). Заменить детерминированными CLI-скриптами
сбора артефактов: `git diff`, `git log`, head/tail по логам, `pytest
--collect-only`, `rg`. Передавать сырьё напрямую Claude и Codex.

---

### R-02 — Remove Qwen Reviewer from critical path in MVP

```yaml
id: R-02
priority: P0
addresses: [F-02]
effort: small
depends_on: []
```

В MVP критический путь = `Qwen Coder → pytest+smoke → Codex tech gate →
Claude business gate`. Qwen Reviewer возвращается только в v2, и только на
другой семье моделей (DeepSeek-Coder / Codex-mini / Qwen другого размера),
для оптимизации частоты вызовов Codex.

---

### R-03 — Cap retry loop at 3 iterations

```yaml
id: R-03
priority: P0
addresses: [F-03, F-05]
effort: small
depends_on: []
```

Hard cap = 3. После cap → STOP → дамп всех артефактов → требовать human
review. Не пытаться автоматизировать диагностику застрявшего loop'а в MVP.

---

### R-04 — Use Sonnet/Codex with raw artifacts, not pre-summarized

```yaml
id: R-04
priority: P0
addresses: [F-01]
effort: small
depends_on: [R-01]
```

Both Codex и Claude получают `task.md` + raw `diff.patch` +
`test_output.txt` + `smoke_output.txt`. Без промежуточного Qwen-резюме.
Это противоинтуитивно для бюджета, но качество вердикта решает.

---

### R-05 — Tests are primary review, LLM is secondary

```yaml
id: R-05
priority: P0
addresses: [F-02]
effort: small
depends_on: []
```

В архитектуре MVP объективный pass/fail signal приходит от pytest + smoke,
а не от LLM Reviewer'а. Loop exit condition = `tests_green AND smoke_green`,
не `reviewer_verdict == APPROVED`. LLM gate (Codex+Claude) выполняется
**после** того, как тесты уже зелёные.

---

### R-06 — Reduce verdict state space to PASS | FIX | ESCALATE

```yaml
id: R-06
priority: P0
addresses: [F-04]
effort: small
depends_on: []
```

На любом LLM gate — три verdict'а. Парсинг через trailing block с regex.
Fallback: VERDICT не найден → FIX (никогда не PASS). Дополнительные нюансы
— prose внутри отчёта, не enum.

---

### R-07 — Run two gates (Codex + Claude) only on critical path exit

```yaml
id: R-07
priority: P1
addresses: [F-05]
effort: small
depends_on: [R-03]
```

После того как retry loop exit'нулся успехом, последовательно: Codex tech
gate → Claude business gate. Если Codex = FIX → одна попытка fix через Qwen
+ rerun loop → если опять FIX → ESCALATE. Никаких отдельных «Codex
Escalation Review» стадий в MVP.

---

### R-08 — Measure value of Codex final gate empirically before adding more Codex calls

```yaml
id: R-08
priority: P1
addresses: [F-05]
effort: small (measurement only)
depends_on: [R-07]
```

После 20+ задач сравнить вердикты Codex tech gate и Claude business gate.
Если совпадают в > 90% случаев — одна из ступеней лишняя; решение «какая»
зависит от того, чьи catch'и оказались более ценными.

---

### R-09 — Enforce Forbidden paths deterministically in orchestrator

```yaml
id: R-09
priority: P0
addresses: [F-06, F-07]
effort: small
depends_on: []
```

`task.md` декларирует `allowed_paths` и `forbidden_paths`. Orchestrator
после каждой Coder-итерации делает `git diff --name-only` и сравнивает с
whitelist. Затронутый запрещённый путь → automatic FIX, без LLM в решении.

---

### R-10 — Smoke test runs on hidden fixture not referenced in task.md

```yaml
id: R-10
priority: P1
addresses: [F-07, F-12]
effort: medium
depends_on: []
```

Smoke test использует input fixture, путь к которой не упоминается в
`task.md`, чтобы Qwen не мог подстроить решение под конкретный smoke input.
Хранить в `.ai-loop/smoke/hidden/` или аналогичной директории.

---

### R-11 — Keep custom ai-git-orchestrator, do not integrate Composio AO

```yaml
id: R-11
priority: P0
addresses: [F-08]
effort: n/a (decision)
depends_on: []
```

Сохранить собственный оркестратор. Из Composio AO, OpenHands, SWE-agent,
Claude Squad, Vibe Kanban брать **идеи** (state machine, worktree
lifecycle, PR lifecycle, UI для мониторинга), не код и не runtime.

---

### R-12 — Defer stacked PR until milestone 4+

```yaml
id: R-12
priority: P2
addresses: [F-09]
effort: n/a (defer)
depends_on: []
```

MVP: один task = одна ветка = один PR. Stacked PR — только когда реально
понадобится разделение epic'а; обычно не нужно в первые месяцы.

---

### R-13 — Use simple git branch in MVP, worktree in milestone 2

```yaml
id: R-13
priority: P1
addresses: [F-10]
effort: small
depends_on: []
```

В MVP `git checkout -b ai/<slug>`. Worktree-per-task появляется в
milestone 2 вместе с параллельными задачами.

---

### R-14 — Make smoke invariants a mandatory section in task.md

```yaml
id: R-14
priority: P1
addresses: [F-12]
effort: small
depends_on: []
```

Claude Planner обязан в `task.md` явно перечислить бизнес-инварианты,
которые проверяет smoke (не просто «output создан», а «output содержит N
stat'ов в секции X с группировкой Y»). Без этой секции — `task.md` считается
невалидным.

---

### R-15 — Add timeouts and health-checks for all subprocess LLM calls

```yaml
id: R-15
priority: P1
addresses: [F-15, F-06]
effort: small
depends_on: []
```

Subprocess timeout per LLM call (suggested 10 min для Qwen Coder, 5 min для
Codex/Claude). Health check перед стартом loop'а. На timeout — итерация
помечается FAIL, считается в cap'е 3 итераций.

---

### R-16 — Cost logging from day 1

```yaml
id: R-16
priority: P1
addresses: [F-13]
effort: small
depends_on: []
```

Per-task запись `tokens_in`, `tokens_out`, `model`, `stage`, `wall_time` в
`.ai-loop/cost.jsonl`. Weekly budget cap → оркестратор отказывается
запускать новые задачи.

---

### R-17 — Secret scan gate before commit

```yaml
id: R-17
priority: P1
addresses: [F-14]
effort: small
depends_on: []
```

Pre-commit step через `gitleaks` или `detect-secrets`. Detect fail →
commit отвергается → итерация FIX.

---

## 4. Recommended Target Architecture (Post-Review)

```yaml
architecture_id: A-2026-05-11-001
stage_count: 8
expected_llm_calls_per_task:
  claude_sonnet: 2  # planner + business gate
  codex: 1           # tech gate
  local_qwen_coder: 1..3  # up to retry cap
deterministic_steps:
  - context_collection
  - test_execution
  - smoke_execution
  - forbidden_paths_enforcement
  - secret_scan
  - git_branch_create
  - git_commit
  - gh_pr_create
```

### Stage flow

```text
S0  user idea (idea.md)
      ↓
S1  deterministic context collector (no LLM)  → context.md
      ↓
S2  Claude Sonnet planner                     → task.md
      ↓
S3  git checkout -b ai/<slug>
      ↓
S4  retry loop (max 3):
      S4.1  OpenCode + local Qwen Coder       → diff in branch
      S4.2  forbidden_paths check (deterministic)
      S4.3  pytest                            → test_output.txt
      S4.4  smoke test on hidden fixture      → smoke_output.txt
      exit if: all green AND no forbidden paths touched
      else: feed raw failures back as fix_instructions.md
      ↓
S5  Codex tech gate                           → codex_review.md
      ↓ (PASS)
S6  Claude Sonnet business gate               → claude_business_review.md
      ↓ (PASS)
S7  secret scan (gitleaks)
      ↓ (clean)
S8  git commit (manual in MVP, automated in milestone 2)
```

---

## 5. Recommended Model Role Table

```yaml
roles:
  - role: planner
    model: claude-sonnet-4.5
    invocations_per_task: 1
    unique_signal: "scope discipline, acceptance criteria, forbidden paths"
    input: [idea.md, context.md]
    output: task.md

  - role: coder
    model: local Qwen2.5-Coder (32B preferred, 14B acceptable)
    invocations_per_task: 1..3
    unique_signal: "cheap mass code generation"
    input: [task.md, previous_iteration_failures]
    output: code_changes + coder_summary.md

  - role: test_runner
    model: none (deterministic)
    invocations_per_task: 1..3
    unique_signal: "objective pass/fail"
    output: [test_output.txt, smoke_output.txt]

  - role: tech_gate
    model: codex (gpt-5-codex CLI or equivalent)
    invocations_per_task: 1
    unique_signal: "diff safety, hardcode detection, fixture cheating detection"
    input: [task.md, diff.patch, test_output.txt, smoke_output.txt]
    output: codex_review.md

  - role: business_gate
    model: claude-sonnet-4.5
    invocations_per_task: 1
    unique_signal: "did this actually solve the business problem"
    input: [task.md, codex_review.md, diff.patch]
    output: claude_business_review.md

excluded_from_mvp:
  - qwen_context_summarizer
  - qwen_iteration_summarizer
  - qwen_business_summarizer
  - qwen_reviewer
  - codex_escalation_review
```

---

## 6. Recommended File / CLI Contracts

```yaml
contract_id: C-2026-05-11-001
filesystem_root: .ai-loop/
```

### Artifact tree

```text
.ai-loop/
  idea.md
  context.md
  task.md
  iterations/
    01/
      coder_summary.md
      diff.patch
      test_output.txt
      smoke_output.txt
      fix_instructions.md
    02/...
    03/...
  codex_review.md
  claude_business_review.md
  final_status.json
  cost.jsonl
```

### Verdict trailer (mandatory in all LLM gate outputs)

```
---
VERDICT: PASS | FIX | ESCALATE
SUMMARY: <one-line summary>
---
```

### Inter-agent contracts

```yaml
contracts:
  - from: planner
    to: coder
    medium: file
    payload: task.md
    rule: "coder reads only task.md; nothing else from planner"

  - from: coder
    to: tests
    medium: git working tree
    payload: code diff
    rule: "coder does not declare success; tests do"

  - from: tests
    to: tech_gate
    medium: files
    payload: [task.md, diff.patch, test_output.txt, smoke_output.txt]
    rule: "raw outputs, not summarized"

  - from: tech_gate
    to: business_gate
    medium: files
    payload: [task.md, codex_review.md, diff.patch]
    rule: "business gate sees codex raw verdict, not paraphrased"

  - from: business_gate
    to: orchestrator
    medium: file + parsed trailer
    payload: claude_business_review.md
    rule: "trailer drives state machine; prose for humans"
```

### Hard rules for orchestrator

```yaml
hard_rules:
  - id: HR-01
    rule: "Git and pytest can only be invoked by orchestrator, never by LLM agent"
  - id: HR-02
    rule: "Any LLM subprocess call is idempotent and restartable"
  - id: HR-03
    rule: "Forbidden paths enforced deterministically, never delegated to LLM"
  - id: HR-04
    rule: "VERDICT parsing fallback is FIX, never PASS"
  - id: HR-05
    rule: "Retry cap is hard; no auto-extension under any condition"
  - id: HR-06
    rule: "Secret scan blocks commit unconditionally"
  - id: HR-07
    rule: "Cost cap blocks new tasks unconditionally"
```

---

## 7. Orchestrator Choice Decision

```yaml
decision_id: D-2026-05-11-001
decision: keep_custom_orchestrator
rejected_alternatives:
  - composio_agent_orchestrator
  - openhands
  - swe_agent
  - claude_squad_as_control_plane
  - vibe_kanban_as_control_plane
```

### Rationale matrix

| Option | Worktree mgmt | PR lifecycle | Strict model gate sequencing | Lock-in risk | Verdict |
|---|---|---|---|---|---|
| Custom `ai-git-orchestrator` | manual (small effort) | manual (small effort) | full control | none | **KEEP** |
| Composio AO | built-in | built-in | requires adapter, fights framework | high | REJECT |
| OpenHands | n/a (single-agent runtime) | n/a | n/a | medium | REJECT (use ideas) |
| SWE-agent | n/a | n/a | n/a | n/a | REJECT (research-grade) |
| Claude Squad | n/a (session manager) | n/a | n/a | low | OPTIONAL UI layer |
| Vibe Kanban | n/a (UI) | partial | n/a | medium | OPTIONAL UI layer |

### Reasoning

1. Уникальная ценность системы — **model routing** (когда звать Qwen, когда
   Codex, когда Claude), а не workflow engine. Workflow engine — это ~500-800
   строк Python (subprocess + retry + file IO).
2. Все CLI-tools (OpenCode, Codex, Claude, gh, git, pytest) уже самостоятельны.
   Generic orchestrator поверх них — тонкий слой, который проще написать, чем
   адаптировать чужой.
3. Жёсткая asymmetric цепочка `Qwen → Codex → Claude` уникальна и не
   поддерживается готовыми оркестраторами нативно.

---

## 8. MVP Implementation Plan

```yaml
mvp_id: MVP-2026-05-11-001
estimated_effort: 1-2 weeks
acceptance_criterion: >
  5 real H2N tasks complete end-to-end through the orchestrator. Of these,
  at least 3 require no human intervention inside the loop (only at final
  manual commit).
```

### Milestone 1 — Single-task end-to-end (1-2 weeks)

```yaml
milestone_id: M1
deliverables:
  - cli_command: "orchestrator run --idea .ai-loop/idea.md"
  - deterministic_context_collector: bash/powershell script
  - claude_planner_invocation: produces task.md with required sections
  - retry_loop: max 3 iterations
  - forbidden_paths_enforcement: deterministic
  - codex_tech_gate: single invocation
  - claude_business_gate: single invocation
  - verdict_parser: PASS/FIX/ESCALATE trailer
  - cost_logging: .ai-loop/cost.jsonl
  - manual_commit_at_end: human runs git commit
excluded_from_m1:
  - worktree
  - gh pr create
  - stacked PR
  - qwen_reviewer
  - codex_escalation
  - any_qwen_summarizer
```

### Milestone 2 — Automation completeness

```yaml
milestone_id: M2
trigger: M1 has produced 5+ successful end-to-end runs
deliverables:
  - git_worktree_per_task
  - automatic_git_commit_after_business_gate_pass
  - secret_scan_gate (gitleaks/detect-secrets)
  - budget_cap_enforcement
  - parallel_task_queue (2-3 simultaneous worktrees)
```

### Milestone 3 — PR automation

```yaml
milestone_id: M3
deliverables:
  - gh_pr_create_with_templated_body
  - bot_account_for_review_comments
  - ci_failure_auto_fix_loop (optional)
```

### Milestone 4 — Optional optimizations

```yaml
milestone_id: M4
gated_by: empirical measurement results
candidates:
  - qwen_reviewer_on_different_model_family
  - codex_escalation_review (if M1-M3 data justifies it)
  - stacked_PR_support
  - monitoring_ui (claude_squad or vibe_kanban as wrapper)
```

### Do NOT do in first 3 months

```yaml
deferred:
  - any cheap_summarizer LLM stage
  - codex_escalation as separate stage
  - verdict enums beyond PASS/FIX/ESCALATE
  - composio_AO integration
  - stacked_PR
  - parallel_tasks (until M2 lands)
```

---

## 9. Failure Modes (ranked by probability × impact)

```yaml
ranked_failure_modes:
  - id: FM-01
    rank: 1
    name: "Fixture/golden output manipulation"
    probability: high
    impact: critical
    related_finding: F-07
    mitigation_recommendation: R-09, R-10

  - id: FM-02
    rank: 2
    name: "Scope drift / unrelated refactor"
    probability: high
    impact: high
    related_finding: F-06
    mitigation_recommendation: R-09

  - id: FM-03
    rank: 3
    name: "Self-review collusion (Qwen ↔ Qwen)"
    probability: certain (if not mitigated)
    impact: high
    related_finding: F-02
    mitigation_recommendation: R-02

  - id: FM-04
    rank: 4
    name: "Verdict parsing failure"
    probability: medium
    impact: high (silent PASS)
    related_finding: F-04
    mitigation_recommendation: R-06

  - id: FM-05
    rank: 5
    name: "Expanding diff over retry loop"
    probability: medium
    impact: medium
    related_finding: F-03
    mitigation_recommendation: R-03

  - id: FM-06
    rank: 6
    name: "Cost runaway"
    probability: medium
    impact: high
    related_finding: F-13
    mitigation_recommendation: R-16

  - id: FM-07
    rank: 7
    name: "Local Qwen hang/OOM"
    probability: medium
    impact: medium
    related_finding: F-15
    mitigation_recommendation: R-15

  - id: FM-08
    rank: 8
    name: "Secret leakage in PR"
    probability: low
    impact: critical
    related_finding: F-14
    mitigation_recommendation: R-17

  - id: FM-09
    rank: 9
    name: "Weak smoke test passes empty implementation"
    probability: medium
    impact: high
    related_finding: F-12
    mitigation_recommendation: R-14

  - id: FM-10
    rank: 10
    name: "Composio AO breaking changes"
    probability: medium (if integrated)
    impact: medium
    related_finding: F-08
    mitigation_recommendation: R-11 (do not integrate)
```

---

## 10. Open Questions for Next Agent / Human Owner

```yaml
open_questions:
  - id: Q-01
    question: >
      Какой именно local Qwen model size планируется? 32B-Coder vs 14B-Coder
      существенно меняет latency и качество, и влияет на cap итераций.
    needed_for: R-15, hardware sizing

  - id: Q-02
    question: >
      Какой именно Codex CLI: gpt-5-codex, gpt-5.5-codex, или другой?
      Влияет на политику routing и стоимость.
    needed_for: cost estimation

  - id: Q-03
    question: >
      Есть ли уже у H2N парсера набор golden output fixtures, которые
      можно пометить как Forbidden paths? Если нет — нужно сначала их
      зафиксировать.
    needed_for: R-09 implementation

  - id: Q-04
    question: >
      Какой бюджет в долларах/токенах в месяц на Codex+Claude приемлем?
      Без числа невозможно настроить R-16.
    needed_for: R-16 calibration

  - id: Q-05
    question: >
      Достаточно ли владельцу single-machine local Qwen, или планируется
      параллелизация через несколько GPU / нескольких физических машин?
      Влияет на приоритет M2 и worktree-per-task.
    needed_for: M2 planning

  - id: Q-06
    question: >
      Должен ли оркестратор работать unattended (cron / daemon),
      или всегда запускается человеком? Влияет на дизайн state recovery.
    needed_for: M2 design
```

---

## 11. Glossary

```yaml
glossary:
  retry_loop: "S4 в target architecture; max 3 итерации Coder→Tests"
  tech_gate: "Codex final review, единственный Codex invocation в MVP"
  business_gate: "Claude Sonnet final review, единственный Claude review invocation"
  forbidden_paths: "whitelist путей, изменение которых auto-fail без LLM решения"
  hidden_fixture: "smoke test input, путь к которому отсутствует в task.md"
  verdict_trailer: "machine-parseable VERDICT: PASS|FIX|ESCALATE блок в конце LLM отчёта"
  asymmetric_review: "review двумя разными семьями моделей для независимого сигнала"
  cheap_summarizer_anti_pattern: "LLM-сжатие данных перед более сильной LLM (см. F-01)"
```

---

## 12. Cross-Reference Index

```yaml
findings_to_recommendations:
  F-01: [R-01, R-04]
  F-02: [R-02, R-05]
  F-03: [R-03]
  F-04: [R-06]
  F-05: [R-07, R-08]
  F-06: [R-09, R-15]
  F-07: [R-09, R-10]
  F-08: [R-11]
  F-09: [R-12]
  F-10: [R-13]
  F-11: (terminology only, no separate recommendation)
  F-12: [R-14]
  F-13: [R-16]
  F-14: [R-17]
  F-15: [R-15]

recommendations_to_milestones:
  M1: [R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-09, R-11, R-13, R-14, R-15, R-16]
  M2: [R-10, R-13 (worktree), R-17]
  M3: [R-12-related PR work]
  M4: [R-02 (reviewer revisit), R-08]
```

---

## 13. Machine-Readable Summary

```yaml
summary_for_next_agent:
  verdict: FIX
  one_line: >
    Architecture concept is sound but implementation is 2-3x too complex;
    simplify to 8 stages, keep custom orchestrator, defer 60% of stages
    to v2+, enforce forbidden paths deterministically not via LLM.
  top_5_actions:
    - R-01: remove Qwen summarizers
    - R-02: remove Qwen Reviewer from critical path
    - R-03: cap retry at 3
    - R-06: collapse verdict states to PASS|FIX|ESCALATE
    - R-09: enforce forbidden paths in orchestrator code, not LLM
  keep_decisions:
    - claude_as_planner_and_business_gate
    - codex_as_tech_gate
    - local_qwen_via_opencode_as_coder
    - file_based_inter_agent_contracts
    - pytest_plus_smoke_as_primary_objective_signal
    - custom_orchestrator
  reject_decisions:
    - composio_AO_as_control_plane
    - stacked_PR_in_MVP
    - 10_iteration_retry_cap
    - LLM_summarizers_between_strong_models
    - LLM_enforcement_of_forbidden_paths
```

---

*End of report AR-2026-05-11-001.*
