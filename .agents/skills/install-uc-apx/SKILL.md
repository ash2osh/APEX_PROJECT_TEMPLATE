---
name: install-uc-apx
description: Conditionally install or verify the optional uc-apx CLI and synchronize its project-local coding-agent skills when INSTALL_UC_APX=true in the repository .env file. Use when setting up optional uc-apx tooling or when the opt-in variable is enabled.
---

# Install and synchronize uc-apx

This template does not bundle `uc-apx` or its skills. Treat both as optional,
user-controlled tooling.

## Gate

1. From the repository root, require `.env` to exist.
2. Read it with `. scripts/load_env.sh .env` on Bash or
   `scripts/load_env.ps1 -EnvFile .env` on PowerShell. Never `source`, `eval`,
   or execute `.env` directly.
3. If `INSTALL_UC_APX` is not exactly `true`, stop successfully without
   installing or synchronizing anything.

## CLI installation

Run `uc-apx version`. If it succeeds, do not reinstall it. If it is absent:

- Explain that the optional binary is published by United Codes at
  <https://github.com/United-Codes/uc-apx>.
- Ask the user for approval before downloading or installing anything.
- Follow the upstream release instructions for the user's platform; install
  into a user-controlled location on `PATH`, never into this repository.
- Run `uc-apx version` and stop on failure.

Do not invent package-manager commands or silently select a release asset.

## Project-local skills

Use `UC_APX_SKILLS_AGENT` from `.env`; the template default is `universal`.
Preview, then synchronize from the repository root:

```bash
uc-apx skills sync --agent "$UC_APX_SKILLS_AGENT" --dry-run
uc-apx skills sync --agent "$UC_APX_SKILLS_AGENT"
```

Do not add `--global`. The generated `uc-apx` skill payload is optional local
state and is ignored by this template. Preserve all unrelated skill content.

Finally, confirm `uc-apx version`, report the generated paths, and run
`python3 scripts/check_local_links.py .` when Python is available. Do not
commit generated skills unless the user explicitly asks.
