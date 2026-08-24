# Changelog

## [Unreleased] — 2026-08-24
### Added
- Section 12b: m2o Desktop Provisioning (RDP + cross-host Guacamole + console/ttyd) — captures the m2/m2.2 topology, path/DNS gotchas, first-boot `unhealthy` wait, expected WARNs on m2.2, the socat-relay pattern for wiring m2.2 desktops into m2's Guacamole, and the console-auth magic-link flow (single real console-auth on m2, m2.2 bridges via socat).
- `scripts/launch-m2o-desktop.sh` — idempotent one-command wrapper around `provision.sh` + relay + Guacamole upsert + perm grant. Installed on m2 (`~/m2o/desktop/launch-desktop.sh`) and m2.2 (`~/machinemachine-core/m2o/desktop/launch-desktop.sh`).

### Fixed
- `desktop/provision.sh` (both hosts) — Traefik router `Host()` was hardcoded to `m2o.machinemachine.ai`, breaking `/console/<name>` for every m2.2-hosted desktop (m2o.machinemachine.ai points at m2, not m2.2). Now reads `CONSOLE_PUBLIC_HOST` from `console-auth/secrets.env` (m2.2 has it set to `console.m-2.cc`; m2 defaults to `m2o.machinemachine.ai`). Also patched the existing `console-euroclean.yaml` in place.
- `scripts/launch-m2o-desktop.sh` — removed the `docker restart guacamole-full` step from step 5. Guacamole picks up DB changes on next login/session; the restart invalidated every active user's session cookie and made connections briefly appear to "disappear" from the UI.

### Deployed (side-effects of this session)
- **m2o-console-link Guacamole extension** — the `Console ↗` button on each Guacamole home-screen connection row (source: `~/m2o/guacamole-ext/console-link/` on m2). Extension was already fully written; wasn't installed. Built + deployed via `install-console-link.sh`.
- **`CONSOLE_HOST_OVERRIDES` env in console-auth** — new optional env, JSON `{slug: host}`. `_host_for(desktop)` returns the override or falls back to `PUBLIC_HOST`. Needed so `/issue` and `/issue-web` return `console.m-2.cc` URLs for m2.2 desktops. Patched into `~/m2o/console-auth/app.py` on m2; container rebuilt + redeployed. `launch-desktop.sh` now auto-updates this map when provisioning a new m2.2 desktop.

### Authors
- Mariusz (operator) — hit the pain, asked for the doc + script
- Fable — end-to-end euroclean provisioning + doc/script extraction

## [0.2.0] — 2026-02-19
### Added
- Section 10: Orchestrator Pattern — conductor/player separation, structured spawn handoff, when to break the rule
- Section 11: Agent Pool & Skill Evolution — 3-tier model (Skills/Ephemeral/Persistent), promotion criteria, SEAL principle, deprecation
- Section 12: Meta-Agent Layer — fleet monitor role, fleet-health.json schema, compounding effect mechanism
- RUNCARD Rule 6: "You are the conductor. Decompose and dispatch. Do not play the instrument yourself."
### Changed
- Version bump 0.1.0 → 0.2.0

### Authors
- Mariusz (operator) — identified the missing orchestrator/evolution architecture
- m2 (orchestrator) — Tree of Thoughts elicitation + section drafting

## [0.1.0] — 2026-02-19
### Added
- Initial 9-section playbook: Identity, Memory, Tasks, Comms, Autonomy, Skills, Spawning, Governance, Amendments
- RUNCARD pattern (~200 tokens per agent)
- Playbook skill (`playbook.sh`) for section-by-section context access
- Amendment process via GitHub PRs
- Auto-ingest pipeline via GitHub Actions + Qdrant

### Authors
- m2 (orchestrator) — initial draft from operational experience
