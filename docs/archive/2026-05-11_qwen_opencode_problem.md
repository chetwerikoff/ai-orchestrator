# Claude Review Task: Diagnose OpenCode + Local Qwen Tool Execution Problem

## Goal

Please review the architecture documents in:

```text
C:\Users\che\Documents\Projects\ai-git-orchestrator\docs
```

especially:

```text
C:\Users\che\Documents\Projects\ai-git-orchestrator\docs\architecture.md
C:\Users\che\Documents\Projects\ai-git-orchestrator\docs\decisions.md
C:\Users\che\Documents\Projects\ai-git-orchestrator\docs\safety.md
C:\Users\che\Documents\Projects\ai-git-orchestrator\docs\workflow.md
```

Then analyze the current Phase 0 issue with the planned OpenCode + local Qwen integration.

The purpose is not to implement anything yet. The purpose is to diagnose why local Qwen does not currently work as a reliable OpenCode agent backend, despite working as a plain local LLM API.

---

## Target Architecture Context

The target architecture is an asymmetric multi-model coding-agent factory:

```text
Claude Sonnet planner
    -> task.md
OpenCode + local Qwen coder
    -> code diff in branch
deterministic guards
    -> forbidden paths, tests, domain_check
Codex technical review
    -> codex_review.md
Claude business review
    -> claude_business_review.md
```

The architecture assumes that the local coder is driven through:

```text
OpenCode + local Qwen
via llama.cpp llama-server
OpenAI-compatible endpoint
```

The intended local backend is:

```text
llama.cpp llama-server
http://127.0.0.1:8080/v1 or another local port
```

The Phase 0 acceptance criterion is not merely “Qwen answers prompts.” The important criterion is:

```text
OpenCode must be able to use local Qwen as an agent backend and produce a real file edit / git diff.
```

---

## Current Machine / Environment

Hardware:

```text
CPU: Intel Core i7-14700K
RAM: 96 GB DDR5
GPU: NVIDIA RTX 4060 Ti 16GB
OS: Windows 11
```

Existing llama.cpp CUDA installation:

```text
C:\Tools\llama.cpp-cuda
```

Working target project used for tests:

```text
C:\Users\che\Documents\Projects\H2N_parser\h2n-range-extractor
```

OpenCode version observed in logs:

```text
OpenCode 1.14.48
```

---

## What Was Installed and Confirmed Working

### 1. llama.cpp CUDA server works

Model installed:

```text
C:\AI\models\qwen2.5-coder-14b\Qwen2.5-Coder-14B-Instruct-Q5_K_M.gguf
```

Server started with approximately:

```powershell
cd C:\Tools\llama.cpp-cuda

.\llama-server.exe `
  -m C:\AI\models\qwen2.5-coder-14b\Qwen2.5-Coder-14B-Instruct-Q5_K_M.gguf `
  --host 127.0.0.1 `
  --port 8080 `
  -ngl 999 `
  -c 32768 `
  --flash-attn on `
  --cache-type-k q8_0 `
  --cache-type-v q8_0
```

Health check works:

```powershell
Invoke-RestMethod http://127.0.0.1:8080/health
```

Result:

```json
{"status":"ok"}
```

### 2. Plain OpenAI-compatible chat completions work

PowerShell request to:

```text
http://127.0.0.1:8080/v1/chat/completions
```

works.

Example prompt:

```text
You are a coding assistant.
Create a Python function parse_int_safe(value) that:
- returns int(value) when conversion is possible
- returns None when value is empty, None, or invalid
Return only Python code.
```

Qwen responded with valid Python code.

So the model itself is installed correctly and can generate code via plain chat completions.

---

## OpenCode Configuration Used

Project-level config:

```text
C:\Users\che\Documents\Projects\H2N_parser\h2n-range-extractor\opencode.json
```

Current intended minimal config:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "local-qwen/qwen2.5-coder-14b",
  "small_model": "local-qwen/qwen2.5-coder-14b",
  "provider": {
    "local-qwen": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local Qwen via llama.cpp",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1"
      },
      "models": {
        "qwen2.5-coder-14b": {
          "name": "Qwen2.5-Coder-14B Local"
        }
      }
    }
  },
  "permission": {
    "read": "allow",
    "edit": "allow",
    "glob": "allow",
    "grep": "allow",
    "bash": "allow"
  }
}
```

A deprecated `tools` block was also tried temporarily, but it did not fix the problem:

```json
"tools": {
  "read": true,
  "write": true,
  "edit": true,
  "bash": true
}
```

The current assumption is that `permission` is the correct modern mechanism and `tools` should not be relied on.

---

## What Works in OpenCode

### 1. OpenCode sees and selects the local Qwen model

In the OpenCode TUI model selector, the model appears as:

```text
Local Qwen via llama.cpp
Qwen2.5-Coder-14B Local
```

### 2. Simple non-tool answer works

Prompt:

```text
Say exactly: local qwen works
```

Output:

```text
local qwen works
```

So OpenCode is successfully talking to the local llama.cpp endpoint.

### 3. OpenCode logs confirm local provider is loaded

Logs show:

```text
service=config path=C:\Users\che\Documents\Projects\H2N_parser\h2n-range-extractor\opencode.json loading
service=provider providerID=local-qwen found
```

and local model calls happen.

---

## The Failure

When asking local Qwen through OpenCode to read or write files, it appears to output a tool-call-like JSON block as plain text instead of OpenCode executing the tool.

Example prompt:

```text
Create a file named qwen_test.txt in the repository root with exactly this text:
local qwen write test

Do not change any other files.
```

OpenCode TUI displays something like:

```json
{
  "name": "write",
  "arguments": {
    "content": "local qwen write test",
    "filePath": "C:\\Users\\che\\Documents\\Projects\\H2N_parser\\h2n-range-extractor\\qwen_test.txt"
  }
}
```

or for bash:

```json
{
  "name": "bash",
  "arguments": {
    "command": "Set-Content -Path .\\qwen_test.txt -Value 'local qwen write test'",
    "description": "Creates a file with test content in the repository root."
  }
}
```

But the file is not created.

PowerShell checks:

```powershell
Test-Path .\qwen_test.txt
Get-Content .\qwen_test.txt
git status
```

show no file.

So local Qwen is producing what visually resembles a tool call, but OpenCode is apparently not treating it as an executable structured tool call.

---

## Control Test With Cloud Model

A control test was performed by switching OpenCode to a cloud/free model from the OpenCode Zen provider:

```text
Big Pickle
```

Prompt:

```text
Create a file named cloud_tool_test.txt in the repository root with exactly this text:
cloud tool test

Do not change any other files.
```

Result:

```text
cloud_tool_test.txt was actually created.
```

Therefore:

```text
OpenCode tools work.
Windows permissions are not the main problem.
The project directory is writable.
The permission config is probably sufficient.
```

The failure appears specific to:

```text
local Qwen2.5-Coder-14B GGUF
+ llama.cpp OpenAI-compatible endpoint
+ OpenCode tool-calling expectations
```

---

## Current Diagnosis Hypothesis

The likely issue is not that Qwen cannot generate code.

The likely issue is:

```text
Qwen2.5-Coder-14B through llama.cpp returns tool-call JSON as ordinary assistant text,
not as structured tool_calls in the OpenAI-compatible API response schema.
```

OpenCode seems to require structured tool calls / native tool-call protocol from the model/provider. If the model only prints JSON in its message content, OpenCode displays it but does not execute it.

This would explain:

```text
plain text answer works
read/write/bash JSON appears visually
but no file change happens
cloud model works with same OpenCode
```

---

## Things Already Tried

1. Confirmed llama-server health.
2. Confirmed plain `/v1/chat/completions` works.
3. Confirmed OpenCode model selection works.
4. Confirmed simple OpenCode text output works.
5. Tried `permission.edit = allow`.
6. Tried `permission.bash = allow`.
7. Tried deprecated `tools` block.
8. Created missing OpenCode state file after an earlier warning:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.local\state\opencode"
"{}" | Set-Content "$env:USERPROFILE\.local\state\opencode\kv.json" -Encoding UTF8
```

9. Tested cloud model Big Pickle and confirmed it can create a file.

---

## Questions for Claude

Please analyze the architecture and the evidence above and answer:

### 1. Is the diagnosis likely correct?

Is the most likely root cause that llama.cpp/Qwen is not returning real structured `tool_calls`, but only printing JSON-like text?

### 2. Is this model-specific or backend-specific?

Could this be caused by:

- Qwen2.5-Coder-14B-Instruct not being trained/tuned for OpenAI-style tool calling?
- GGUF conversion / chat template missing tool-call metadata?
- llama.cpp OpenAI-compatible server not advertising or parsing tools in a way OpenCode expects?
- OpenCode’s `@ai-sdk/openai-compatible` provider not passing tool schemas to llama.cpp?
- wrong chat template for Qwen?
- wrong config key in OpenCode provider options?
- using TUI instead of non-interactive mode?
- using `/v1/chat/completions` instead of some other endpoint?

### 3. What is the next best experiment?

Please propose the smallest next experiments, ranked by diagnostic value.

Examples:

- Inspect raw HTTP response from llama.cpp when OpenCode sends tools.
- Run OpenCode in debug mode and verify whether OpenCode passes tool schemas to the provider.
- Test non-interactive OpenCode mode instead of TUI.
- Test Qwen3-Coder-30B-A3B Q3_K_M.
- Test a model known to support tool calling locally.
- Test llama.cpp server flags related to chat template/tool calling.
- Use LiteLLM proxy between OpenCode and llama.cpp.
- Use a different local backend that better supports tool calls.
- Change the OpenCode provider config.
- Use OpenCode only with cloud models and use local Qwen as a plain patch generator.

### 4. Does this invalidate the architecture?

The architecture assumes:

```text
OpenCode + local Qwen -> real diff in branch
```

If local Qwen cannot do OpenCode tools reliably, should the architecture be changed to one of these?

#### Option A: Keep OpenCode, switch local model

Try Qwen3-Coder-30B-A3B, Qwen3.6-27B, or another local tool-capable model.

#### Option B: Keep Qwen, change backend

Use a backend/proxy that can produce tool-call-compatible responses.

#### Option C: Keep Qwen, remove OpenCode from local path

Use Qwen as plain code/patch generator:

```text
Claude task.md
local Qwen generates unified diff or file contents
Python orchestrator applies patch
pytest/domain_check
Codex review
Claude business review
```

#### Option D: Keep OpenCode only for cloud models

Use OpenCode with cloud models and local Qwen only for cheaper summarization/code suggestions outside the critical agent path.

### 5. What should Phase 0 acceptance criteria become?

Current intended acceptance:

```text
OpenCode + local Qwen produces a real code diff in target repo.
```

Should we keep this strict criterion?

Or split it into:

```text
P0a: local Qwen plain code generation works
P0b: OpenCode structured tool execution works
P0c: real diff generation works
```

### 6. What exact files/configs should be inspected?

Please list concrete files/logs/commands to inspect, for example:

```text
C:\Users\che\Documents\Projects\H2N_parser\h2n-range-extractor\opencode.json
C:\Users\che\.local\share\opencode\log\*.log
C:\Users\che\.local\state\opencode\kv.json
C:\AI\scripts\start-qwen14b.ps1
llama.cpp startup log
raw OpenAI-compatible API response
```

### 7. Please produce a recommended decision

Please return:

```text
LIKELY_ROOT_CAUSE:
EVIDENCE:
COUNTEREVIDENCE:
NEXT_EXPERIMENTS:
ARCHITECTURE_IMPACT:
RECOMMENDED_DECISION:
```

Use the architecture documents as the main reference. Do not implement anything. This is a diagnostic / architecture review task.
