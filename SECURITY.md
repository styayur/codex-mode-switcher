# Security Policy

## Supported version

Security fixes target the latest released 0.2.x line. Desktop end-to-end acceptance
remains pending; automated tests do not establish
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

## Optional Windows integration boundary

The integration manager writes only its dedicated Terminal fragment, current-user Start
Menu shortcuts and private ownership/backup files. It does not rewrite Terminal settings,
install a service, create desktop shortcuts or change PATH/ExecutionPolicy. Preview is the
default; Apply is explicit approval. Uninstall resolves a fixed set of artifact IDs to
known user folders and requires recorded content hashes. Never import foreign ownership
data. Modified or unowned artifacts are preserved, including during conditional rollback.

Toast registration is a native identity shortcut, not a persistent activator. Explicit
Notify passes only allowlisted outcomes to a short-lived Windows PowerShell helper, never
raw error/config values. Helper failure is isolated from config transaction success. Only
that owned helper can be stopped at its timeout. UI delivery is controlled by Windows.

Integration operations are not crash-atomic across multiple files. Abrupt termination can
leave partial/unrecorded artifacts requiring local review. Retained backups and receipts
are not deleted by uninstall-all; the legacy PowerShell profile block is managed separately.
