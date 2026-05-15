# User ASK

## Goal

Add a lightweight failure classification contract for ai-orchestrator so agent/tool failures can be labeled consistently before Claude is asked to diagnose or replan. The immediate goal is diagnostic clarity, not automatic fallback.

In particular, distinguish OpenRouter/platform rate limits from upstream provider failures:

- OpenRouter/platform quota or HTTP 429 should classify as `rate_limit`.
- Provider route/upstream failures such as "provider returned error", model unavailable, or route/provider mismatch should classify as `provider_error`.

## Affected files (your best guess - planner will verify)

- `scripts/ai_loop_auto.ps1`
- `scripts/ai_loop_task_first.ps1`
- `scripts/ai_loop_plan.ps1`
- `scripts/run_scout_pass.ps1`
- `templates/failure_triage_prompt.md` (if the failure triage task has been implemented)
- `tests/test_orchestrator_validation.py`
- `docs/workflow.md`
- `.ai-loop/project_summary.md`

## Out-of-scope (explicit boundaries)

- `docs/archive/**`
- `.ai-loop/_debug/**` except as optional read-only evidence when explicitly requested by a triage workflow
- `ai_loop.py`
- Automatic provider/model fallback
- Changing model selection
- Retrying failed LLM calls
- Hiding quality changes behind silent fallback

## Proposed approach (optional)

Introduce a small, explicit failure kind taxonomy and use it in failure triage / runtime diagnostics.

Suggested enum:

```text
rate_limit
provider_error
tool_error
planner_output_malformed
reviewer_output_malformed
no_diff
test_failed
quality_failed
git_error
environment_error
unknown
```

The implementation can be minimal. The planner should choose the simplest approach, for example:

1. Add a PowerShell helper that classifies error text:

   ```powershell
   Get-FailureKindFromText -Text $rawOutput
   ```

2. Match high-signal patterns:

   - `429`, `rate limit`, `quota`, `insufficient credits`, `too many requests` -> `rate_limit`
   - `provider returned error`, `upstream`, `ProviderModelNotFoundError`, `model not found`, `route`, `provider not found` -> `provider_error`
   - PowerShell/native invocation errors, missing executable, permission denied, execution policy -> `tool_error` or `environment_error`
   - planner first-line sanity failure -> `planner_output_malformed`
   - reviewer strict-output failure -> `reviewer_output_malformed`
   - no implementation side effects -> `no_diff`
   - pytest/test command failure -> `test_failed`
   - Codex `FIX_REQUIRED` / quality gate failure -> `quality_failed`
   - git commit/staging/push failures -> `git_error`

3. Emit classification in a durable runtime artifact, for example:

   ```text
   .ai-loop/failure_classification.json
   ```

   Example:

   ```json
   {
     "kind": "provider_error",
     "source": "opencode",
     "confidence": "high",
     "evidence": ["ProviderModelNotFoundError"],
     "fallback_used": false
   }
   ```

4. Update future/related failure triage prompt so Cursor must include:

   ```md
   ## Failure kind
   `provider_error`

   ## Failure source
   `opencode`
   ```

5. Keep fallback out of scope. If fallback is added later, it must be explicit and logged.

## Constraints / context the planner may not know

- This should be a diagnostic aid, not a new retry/fallback subsystem.
- Classification must be transparent and evidence-backed; do not silently convert one kind into another.
- Prefer small helper logic and tests over a broad abstraction.
- If there is no implemented `triage_failure.ps1` yet, make this task either:
  - a standalone classifier used by existing failure paths; or
  - a follow-up dependency note for the failure triage task.
- The classifier must not read huge logs by default. It should classify from bounded captured output already available to the calling script.
- Unknown or ambiguous cases should classify as `unknown` with low confidence rather than guessing.
- Fallback provider/model behavior is explicitly out of scope because it can silently reduce implementation quality.
