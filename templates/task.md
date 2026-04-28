# Task: <specific slice>

## Source Issue

GitHub issue: <issue title or URL>

## Target Module

modules/<name>

Optional remote:

<owner/repo>

## Task

<one concrete implementation or review task>

## Context

- <important existing files>
- <design constraints>
- <relevant prior PRs or issues>

## Scope

Allowed files/directories:

- `modules/<name>/<path>`
- `modules/<name>/<path>`

Do not change:

- `<path or behavior>`
- public API outside this task
- unrelated formatting or refactors
- submodule pointers unless explicitly requested

## Definition of Done

- <behavior completed>
- <tests added or updated>
- <docs/example updated if needed>
- <validation commands pass or failure is explained>

## Validation

Run:

```sh
<command>
```

If a command cannot run, explain why and provide the closest available
validation.

## Output

Create a draft PR or reviewable patch.

PR body must include:

1. Summary
2. Tests run
3. Risks
4. Follow-up tasks
