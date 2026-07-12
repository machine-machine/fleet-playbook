# Changelog

## [0.3.0] — 2026-07-12
### Changed — truth pass: docs now match the live fleet
- **Comms:** the old async message-passing proxy → **Mattermost** (chat.machinemachine.ai, team `machine.machine`). Removed the dead comms service and its API from §4, RUNCARD, README, and the ingest workflow.
- **Runtime:** the old agent runtime → **Hermes** (`~/.hermes` paths throughout; `hermes-gateway`, `HERMES_HOME`).
- **Desktops:** Guacamole moved off the standalone `g2` host → **Guacamole on m2** at `m2o.machinemachine.ai` (RDP-default).
- Planka unchanged (kanban.machinemachine.ai).
### Added
- **m2-gpt gateway** — `gpt.machinemachine.ai`, GLM served via Bifrost routes + chains (RUNCARD, §13, appendix).
- **memory.machinemachine.ai** — the M² agent memory system (BGE-M3 + Qdrant hybrid search, 3-tier, per-agent namespaces) named explicitly in §2/§6/§11.
- **herdr / m2herd** orchestration — fan-out to a herd of worker agents in panes + worktrees (§5, §10, §11).
- **primus** desktop image + `provision.sh` spawn path (§7, §13).
- **Forgejo + GitHub** mirrored git hosting (§9, appendix).
### Security
- Removed the live bearer token that was published on `main` in the RUNCARD and §4. Git history NOT rewritten — see `## NEEDS OPERATOR` in `.WAVE_REPORT.md`: the token must be rotated.
### Version
- Version bump 0.2.0 → 0.3.0

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
