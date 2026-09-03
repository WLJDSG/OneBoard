# Findings & Decisions

## Requirements
- Manage multiple ChatGPT/Codex macOS desktop App accounts; Codex CLI is explicitly out of scope.
- Add, rename, delete, and select account profiles.
- Account/password/MFA input happens only in the official browser login flow.
- OneBoard does not store passwords or verification codes; it stores the resulting auth cache/token.
- Clicking an account automatically closes Codex, waits for the relevant processes to exit, atomically switches credentials, and relaunches Codex.
- Keep all business code in `OneBoardKit`; the executable target remains minimal.
- Stored inactive auth caches must use macOS Keychain and must never appear in logs, plaintext profile metadata, or source files.

## Research Findings
- On 2026-09-02, a read-only shallow clone of `jlcodes99/cockpit-tools` showed a Tauri/Rust implementation with dedicated Codex account, OAuth, process-switch progress, instance-isolation, and local-access modules; no repository code was executed.
- The reference project explicitly treats `~/.codex/auth.json` as the official current Codex login and exposes `switch_codex_account`, OAuth-start/completion, cancellation, and progress UI commands.
- Its Codex account provider models OAuth refresh-token rotation and per-instance `CODEX_HOME` isolation, which is broader than OneBoard's desktop-only cached-file switch.
- The reference does not implement switching as a blind file copy: it projects an account into the configured official credential store (`auth.json`, macOS Keychain, or auto with fallback), performs atomic writes, and treats official storage as the authority for refresh-token rotation.
- The main switch command is in `src-tauri/src/commands/codex_account_commands.rs`; projection and authority reconciliation are split into dedicated Rust modules. This confirms OneBoard's current hard-coded file-only assumption is the main compatibility gap to investigate.
- Cockpit's switch is transactional: acquire a profile mutation lease, validate/refresh the target, snapshot the previous credential, stop the current default runtime before commit, write credentials, synchronize settings, and optionally relaunch. The user explicitly chose this close/relaunch behavior for OneBoard on 2026-09-02.
- On macOS Cockpit first asks the app to quit by activating it and sending Command-Q, waits briefly, then falls back to closing remaining PIDs and verifies they are gone. It snapshots direct app-server descendants before the Electron parent exits so an old process cannot rewrite refreshed credentials after the new account is committed.
- The reference supports the official macOS Keychain service `Codex Auth` and derives a keychain account from the Codex home. OneBoard currently protects its own inactive snapshots in a separate Keychain service but always materializes the active credential as `~/.codex/auth.json`.
- Exact official-Keychain compatibility details from the reference: service `Codex Auth`; account `cli|` plus the first 16 lowercase hex characters of SHA-256 over the canonicalized Codex-home path. `config.toml` key `cli_auth_credentials_store` selects `file`, `keyring`, or `auto`.
- In `keyring` mode the reference writes the official Keychain item and removes the file fallback; in `auto` it tries Keychain first and falls back to `auth.json`; reads prefer the configured authority but retain a file fallback. These semantics can be added beneath OneBoard's existing `CodexAuthCacheFileHandling` seam without changing the account UI or switch state machine.
- OneBoard now implements that official-store compatibility through Security.framework and keeps inactive account snapshots in its separate `com.oneboard.mac.codex-auth-cache` vault.
- OneBoard's automatic switch validates the target before process control, captures direct Codex app-server children, requests normal app termination, falls back to SIGTERM after a two-second grace period, verifies exit before commit, and relaunches through LaunchServices.
- Focused Codex coverage has 19 tests passing, including close-before-commit ordering, invalid-target preflight, failure boundaries, storage modes, and app-server parsing. The full suite passes 107/107.
- CodeGraph confirmed the OneBoard change can stay confined to the Codex account storage seam and tests; executable-target wiring and existing UI entry points need no structural change.
- Repository memory confirms the SwiftPM root is `OneBoard/` and release acceptance uses the packaged DMG.
- Official OpenAI documentation says local Codex clients support ChatGPT browser sign-in and API-key sign-in. ChatGPT sign-in opens a browser and returns credentials to Codex.
- Official CLI commands include `codex login`, `codex login --device-auth`, `codex login --with-api-key`, `codex login status`, and `codex logout`.
- Official credential storage can be file, keyring, or auto. File storage is `auth.json` under `CODEX_HOME`; separate `CODEX_HOME` directories can therefore isolate CLI profiles.
- The installed binary is `/Applications/ChatGPT.app/Contents/Resources/codex`, and current read-only status reports ChatGPT authentication.
- OneBoard already has a settings sidebar, CRUD-sheet precedent in `GatewaySettingsView`, a menu-bar entry point, and a process-runner pattern.
- No Keychain wrapper exists in the current project. Existing recognition API-key fields use `AppStorage`/`UserDefaults`, which must not be copied for Codex credentials.
- The app entitlement file permits network access and does not declare App Sandbox; launching the Codex CLI matches the existing process pattern.
- There is no documented OpenAI API for a third-party macOS app to select a ChatGPT desktop account, submit a ChatGPT password, or submit an MFA/email verification code.
- `--device-auth` exposes a device authorization flow. OneBoard can show the device code and open the official page, but that code is not the user's MFA/email OTP.
- Final approved scope supersedes earlier password/OTP automation notes: the official browser owns both, and OneBoard stores only the resulting auth cache.
- The installed desktop application bundle identifier is `com.openai.codex`, executable/name `ChatGPT`.
- OneBoard already detects running applications through `NSWorkspace.shared.runningApplications`, so process monitoring can be injected and tested without shell process inspection.
- Existing UI precedent is `GatewaySettingsView`: grouped Form, status summary, inline CRUD buttons, and add/edit sheets.
- Existing metadata persistence precedent is `GatewayProfileStore`: Codable profiles encoded to UserDefaults with injectable defaults/key.
- No existing Security/Keychain wrapper exists; a narrow `CodexAuthCacheVault` abstraction is required so production uses Keychain and tests use an in-memory double.
- The real auth cache must never be read in unit tests; the cache file path, running-state provider, and vault must all be injectable.
- Superseding switch state machine: preload and validate the target; record it as pending; close Codex and wait for process exit; save the active account's refreshed cache; atomically restore the target; persist the active ID; then relaunch Codex. A close failure must occur before credential commit.
- If an unmanaged current `auth.json` exists and no active saved profile is known, switching must fail with a prompt to save the current login first; never overwrite an unknown login cache.
- Inactive account caches will be stored as generic-password Data in macOS Keychain under a OneBoard-specific service. Only the currently active cache is materialized at `~/.codex/auth.json` because the desktop app requires it.
- Account metadata can remain Codable UserDefaults data; it contains only user-supplied display name and timestamps, never token contents.
- A menu-bar Codex account submenu is the appropriate quick-switch entry; the settings tab provides full CRUD and current-cache capture.

## 2026-09-03 Superseding OAuth Requirement
- The user explicitly rejected the manual "save current login" onboarding and superseded it with Cockpit Tools-style browser OAuth account creation.
- The supplied screenshots establish the intended sequence: enter the OpenAI email, open the generated Codex authorization URL, finish the official browser flow, then manage the resulting account card.
- The full reference repository was cloned to `/Users/wenlanjun/办公/workspace/cockpit-tools` at commit `1e2af3df`.
- The reference uses client ID `app_EMoamEEZ73f0CkXaXp7hrann`, authorization endpoint `https://auth.openai.com/oauth/authorize`, token endpoint `https://auth.openai.com/oauth/token`, PKCE S256, state validation, localhost callback, and the hosted wrapper `https://chatgpt.com/codex/desktop-auth`.
- OneBoard now follows that OAuth flow while intentionally excluding Cockpit's password and 2FA-secret note fields. Passwords and verification codes remain browser-only.
- The resulting credential is projected into the official Codex `type`, `tokens`, `account_id`, and `last_refresh` JSON shape, then stored only in OneBoard's Keychain vault until the user switches to it.
- Superseding first-switch behavior: a user-selected managed OAuth account may replace an unmanaged current credential after Codex fully exits. The removed save-current primary UI would otherwise make the first managed switch impossible.

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Recommended v1 targets Codex CLI profiles | Supported isolation through `CODEX_HOME`; it does not mutate or copy raw OpenAI session files |
| ChatGPT accounts store name/email metadata only | Browser OAuth owns passwords and MFA; OneBoard should never collect them |
| API keys use macOS Keychain | The official CLI accepts an API key through stdin, enabling secret-safe process integration |
| Verification UI displays device authorization status/code only | MFA and email verification must remain on the official OpenAI/browser surface |
| Superseding scope: desktop auth cache only | The user explicitly excluded CLI and all password/verification automation |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
| Requested password/OTP automation conflicts with the official OAuth flow | Redesign the UI around browser authorization or device authorization instead of password storage |
| GitHub page fetch failed with a connection error | Used a shallow read-only clone under `/tmp` and inspected source text only |
| The repository directory was externally renamed while the task was active | Moved the same dirty worktree back to the environment-authorized original path; no repository copy was created |
| The first OAuth integration test rejected the mocked token request because URLProtocol exposes uploaded bodies as a stream | Kept production form encoding unchanged and asserted the endpoint, method, and content type in the transport mock |

## Resources
-
