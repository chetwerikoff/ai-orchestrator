Remove all Claude final review logic from scripts/ai_loop_auto.ps1 and scripts/continue_ai_loop.ps1.

Delete:

- NoClaudeFinalReview parameter

- Run-ClaudeFinalReview function

- Get-ClaudeVerdict function

- all reads/writes of .ai-loop/claude_final_[review.md](http://review.md)

- all calls to claude -p

- all resume-mode Claude branches

- all PASS_WITH_CAVEATS handling from Claude

After Codex PASS, the loop must run final tests, commit, and push.

Do not leave any active Claude final review path.