# Security Policy

## Supported version

Security fixes target the latest released 0.1.x line and the active v0.2.0 development
branch. v0.2.0 Desktop end-to-end acceptance is pending; automated tests do not establish
provider-side security, availability or configuration consumption.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/styayur/codex-mode-switcher/security/advisories/new).
Do not post exploitable details or credentials publicly. Include a synthetic reproduction,
version and PowerShell version. If private reporting is unavailable, ask for a private
contact in an issue without disclosing the vulnerability.

Never attach auth.json, tokens, API keys, .env, raw diagnostics, logs, databases, or
unredacted config/state/backups. Revoke any exposed credential with its issuer; removing
a commit alone does not revoke access.

## Data and process boundaries

- The controller reads user config.toml and its own provider/GPT state and transaction files.
  It writes those files, verified backups, journals, temporary siblings and a tool lock.
- It never reads, copies, deletes or rewrites credential stores, session files or databases.
  It makes no Codex CLI login/doctor calls. Optional profile installation separately reads,
  backs up and changes the explicitly selected PowerShell profile.
- Windows discovery inspects package/Start-menu metadata, uninstall registration and process
  executable identity. It does not collect process command lines. Win32 validation checks
  Authenticode identity and the GUI PE subsystem before launch.
- Desktop is activated only with explicit Launch. No forced exit, task cancellation,
  process injection or undocumented application API. Only the controller-owned hidden
  read-only inventory probe can be terminated after its own timeout.
- Keys belong in environment-backed configuration or credential management. Literal secrets
  already embedded in config are necessarily copied into private backups/provider fragments.
  Environment key values are not extracted or printed. Child applications receive their
  normal environment; this tool cannot guarantee their behavior or environment consumption.
- Results use allowlisted fields and sanitized errors; suspicious model/provider labels are
  redacted. Diagnostics contain local paths and IDs. Redact them before sharing; arbitrary
  mislabelled secret strings cannot be classified perfectly by a pattern filter.

## Filesystem and concurrency assumptions

Keep CODEX_HOME, backups and profile files private and out of shared folders. State is
trusted local input subject to schema checks; do not accept state/journals from strangers.
Backups are not encrypted and inherit filesystem permissions. Linked/reparse managed paths
are refused. Ignore patterns are not a substitute for diff and secret review.

Atomic replacement is per-file. A durable Committed journal marks the transaction boundary.
Before commit, restoration requires matching recorded hashes; conflicts retain newer files
and demand recovery. After commit, startup failure never reverts config automatically.
The lock serializes this tool only. Hash checks cannot eliminate races with external editors
at the final check/write or launch boundary; close editors and Desktop before switching.

The conservative TOML editor is not a general parser. Start from valid supported syntax.
A user-level profile can block launch; other override sources are not exhaustively inspected.
No claim is made that a launched process loaded the desired provider or finished prior tasks.
