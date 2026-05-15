# User ASK

## Goal

Найденные проблемы:

  1. run_codex_reviewer.ps1: $exitCode не инициализирован перед try
  run_claude_planner.ps1 инициализирует $exitCode = 1 до try {. В run_codex_reviewer.ps1 этого
  нет — если до & codex @codexArgs произойдёт исключение, exit $exitCode получит $null (т.е. exit
   0 вместо exit 1). Низкий риск, но расхождение с установленным паттерном.

  2. Encoding: ? вместо em dash — в шаблонах и строках ps1
  В reviewer_prompt.md, planner_prompt.md и в embedded строках $revisionInstructions em-дефисы
  превратились в ?. Это результат потери UTF-8 при сохранении. На тесты не влияет, но LLM получит
   "you are advisory only ? the architect" вместо "— the architect".

   Так же я хочу сократить количество вызовов ревьювера при создании задачи до 1

## Affected files (your best guess ? planner will verify)


## Out-of-scope (explicit boundaries)


## Proposed approach (optional)


## Constraints / context the planner may not know
