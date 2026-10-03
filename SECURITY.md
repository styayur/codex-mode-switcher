# Security Policy

## Supported version

Security fixes target the latest `0.1.x` release. This is a local configuration tool;
the project's regression suite does not establish provider-side security or availability.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/styayur/codex-mode-switcher/security/advisories/new).
Do not open a public issue with exploitable details or credentials. Include a minimal,
synthetic reproduction, script version and PowerShell version. If private reporting is
unavailable, open an issue asking for a private contact without disclosing the vulnerability.

Never attach auth.json, tokens, API keys, .env files, raw Codex diagnostics, session logs,
databases, or unredacted config/state/backups. If a credential was exposed, revoke it
with its issuer and remove the public disclosure; deleting a commit alone is insufficient.

## Local data boundaries

- The script reads user-level config.toml and its own saved provider state.
- It writes configuration, provider state, config/state backups and a local lock file.
- It does not access the credential store, session files or databases itself. Optional
  Codex login/doctor commands may access Codex data as part of their own operation.
- Keys should be supplied through env_key or environment-backed headers. Literal secrets
  already embedded in config will be copied into local backups and provider fragments.
- Backups and state inherit filesystem access rules. They are not encrypted by this tool.
  Keep CODEX_HOME private and out of shared/public folders; do not use an untrusted state file.
- The lock serializes this script's writers. Close Codex tasks and other editors before
  switching; external applications can race writes and may hold earlier config in memory.

The repository ignore rules provide defense against common accidental file additions;
review every diff because secrets can appear under arbitrary names or inside source files.
