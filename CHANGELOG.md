# Changelog

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
