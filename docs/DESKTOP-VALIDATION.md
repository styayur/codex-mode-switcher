# v0.2.0 audit and acceptance record

Review date: **2026-10-11**. Base: stable main **23ce137**. Branch:
`feat/desktop-controller-v0.2.0`. This is a development/PR record, not release certification.
Historical v0.1.0 evidence remains in [VALIDATION.md](VALIDATION.md) and the changelog.

## Baseline audit

The original entry script, all 40 tests, README, Chinese guide, configuration/state handling,
CI/lint rules, security policy and Git history were reviewed before implementation. Baseline:
40 tests passed. The upgrade retains all 40 scenarios. Eight CLI-side-effect expectations
were migrated to verify absence of those calls under the explicitly Desktop-only design.

Findings addressed:

- GPT previously cleared native model selection. A separate validated GPT snapshot now
  restores model and reasoning fields through a custom-provider round trip.
- Provider state and config were separate writes without a shared commit/rollback record.
  Both now participate in a journaled transaction with verified prior-byte backups.
- External edits and partial failures needed explicit boundaries. Hash checks guard each
  stage and conditional recovery; launch failure is separated from config commit.
- Implicit CLI login/doctor could open a browser or use network access. The Desktop
  controller makes no CLI calls; legacy flags remain accepted no-ops.
- PowerShell case-insensitive matching could remove case-distinct TOML keys. Managed key
  matching is now case-sensitive, with a preservation regression test.

## Actual Windows observations: read-only

The development host has a registered **OpenAI.Codex** MSIX package, version
**26.1002.7124.0**, family **OpenAI.Codex_2p2nqsd0c76g0**. The manifest/Start-menu intersection
identified application **App**, AUMID **OpenAI.Codex_2p2nqsd0c76g0!App**, executable
**app/ChatGPT.exe**. A command-runner manifest entry was excluded. These are observed
package identities, not fixed installation directories or universal product naming promises.

GUI processes matched that installed package path. A separate codex.exe backend was not
classified as the GUI by name. An unrelated ChatGPT Classic installation was also present.
The new read-only Diagnose command identified Installed/MSIX and Running with reliable
path evidence. No supported Win32 Codex uninstall registration was found on this host.
No personal installation paths, process IDs, config contents or credentials are published.

A repeat on the busy host took 21.3 seconds for native inventory. The original 15-second
probe safely returned Unknown; its bounded deadline was increased to 45 seconds. Managed
config/provider/GPT-state hashes were unchanged by the read-only check.
After that adjustment, the controller again reported Installed/MSIX and Running with a
reliable registered-manifest identity. ProviderLoaded correctly remained NotVerified.

**Not performed:** changing the host's real config, stopping tasks, closing Desktop,
activating Desktop, or making a new provider inference request. This engineering session
itself runs in Desktop; disrupting it would not be a safe acceptance test.

## Evidence and conservative decisions

- OpenAI's [Desktop provider configuration guide](https://learn.chatgpt.com/docs/enterprise/connect-to-a-gateway)
  describes Windows user configuration and restarting the app after changes. It requires
  credentials to be available to the app. This supports restart-based selection; it does
  not establish hot reload, CLI --profile support or private App Server control.
- Microsoft documents [finding an AUMID](https://learn.microsoft.com/en-us/windows/configuration/store/find-aumid)
  and [IApplicationActivationManager::ActivateApplication](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iapplicationactivationmanager-activateapplication).
  The COM binding uses that public API. An activation HRESULT/process ID does not establish
  config consumption or successful inference.
- Shell-only CODEX_HOME inheritance through MSIX activation has not been verified. The
  controller refuses custom-home MSIX launch. Win32 environment passing is implemented,
  but actual app consumption remains a manual acceptance item.
- There is no verified public task-completion signal in this implementation. TaskActivity
  stays Unknown, and launch requires user attestation. ProviderLoaded stays NotVerified.

## Automated verification

Run `pwsh -NoProfile -File ./scripts/Test-Project.ps1` on Windows with Pester 5.7.1 and
PSScriptAnalyzer 1.25.0. The command parses all PS1/PSM1/PSD1 sources, enforces lint, and
runs the original configuration suite plus Desktop controller and discovery suites.

Every mutation test uses an isolated TestDrive CODEX_HOME. Launch tests use synthetic
identities and mocked activation, never real Desktop or real configuration. Discovery tests
mock package/registry/process inventory. The COM test compiles the binding without invoking it.

Coverage includes native/custom round trips and repeated selections; absent/ready/running/
unknown Desktop; cancellation and bounded exit waits; missing config and damaged state;
write failure, concurrent edits before/after commit, rollback conflict and journal recovery;
failed/timed-out activation; dry-run side effects; secret-bearing config/error redaction;
legacy flags and no CLI calls; profile conflicts/uninstall; MSIX identity mapping, Win32
validation, path escape and CLI separation. Mock success is not real Desktop E2E success.

Architecture verification checks source anchors and local links, then renders light/dark
Mermaid with a repeatability check. These development dependencies are not runtime dependencies.
The PR's Actions runs are the authoritative CI record for its exact commit.

Local checks on 2026-10-11: the full syntax/lint run passed with **88/88 Pester tests**
(zero failures/skips). A subsequently added quoted-profile regression passed separately,
bringing the current suite to **89 scenarios**. Updated source/test lint passed. The final
discovery suite was also rerun after its final changes. The PR runs the complete Windows CI.
Mermaid light/dark rendering and deterministic repeat passed, as did checks of 8 source files
and 29 local documentation references. TruffleHog 3.97.9 reported zero findings for the
publishable-file snapshot and existing Git history with credential verification disabled.
Personal-path/credential-pattern checks passed; ignored original material was not exported.

## Required manual acceptance before release

Perform these from a separate terminal after this engineering session is safely finished.
Keep private backups local; publish only sanitized pass/fail observations.

- [ ] Installed MSIX: finish/stop tasks, normal exit, GPT -Launch, confirm new task uses the
  intended native model and ChatGPT authentication.
- [ ] MSIX: normal exit, saved custom -Launch, confirm a new task uses the intended provider
  and valid protocol/credentials; normal exit and return to GPT, retaining native selection.
- [ ] Verify Windows activation and environment behavior after logon with supported credential
  configuration. Keep custom-home MSIX launch blocked until its behavior is established.
- [ ] A supported signed Win32 installation: discovery, normal exit, startup, CODEX_HOME
  consumption and both new-task provider directions.
- [ ] Real interactive cancellation/timeout and a Desktop that remains open: confirm no config
  mutation, no process termination and no task cancellation.
- [ ] Inspect surviving old sessions without assuming migration; document their observed limits.
- [ ] Test interrupted transaction recovery on a disposable home, then verify diagnostics and
  byte restoration. Do not crash or corrupt the real Desktop home to test recovery.

v0.2.0 must not be released merely because mocked tests or CI pass. PR merge and release
remain separate decisions after this acceptance record is completed.
