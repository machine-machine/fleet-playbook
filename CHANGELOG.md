# Changelog

## [0.3.0] — 2026-07-10
### Changed — stack refresh to current reality
- **Runtime:** OpenClaw → **Hermes Agent** (Nous) as the primary agent on every primus desktop; LLM via the **m2-gpt gateway** (gpt.machinemachine.ai, GLM-5.1 on the Spark cluster). Paths `~/.openclaw/` → `~/.hermes/`.
- **Inter-agent comms (§4):** escalation inbox → **Mattermost** (chat.machinemachine.ai, team machine.machine). Documented bot-to-bot coordination (no bot-sender filter; @mention gating as the loop guard) and the known-agents bot table.
- **Memory (§2):** rewritten around `memory.machinemachine.ai` (agent.memory.system, BGE-M3 + Qdrant) with real `agent_id` namespaces.
- **Skills (§6):** current fleet skills (coolify, forgejo, m2-memory, m2o-provision, fleet-copy, herdr); Dark Factory → herdr / factory-loop.
- **Spawning (§7):** primus image + `provision.sh` + RDP standard + per-machine Mattermost wiring; two hosts (m2 + m2.2).
- **Infrastructure (§13) + Appendix:** two Coolify instances, Cloudflare-Tunnel ingress for `*.machinemachine.ai`, named-volume persistence, host IPs, current URLs/IDs.
- **RUNCARD:** rewritten; **removed the leaked `bge-proxy` bearer token** (rotate it).
### Added
- **m2o-operator** designated **playbook manager/maintainer** (fleet service agent, Hermes on m2.2, Mattermost `@m2o-operator`).
### Authors
- m2o-operator (maintainer) — refresh + adoption; Mariusz (@mar) — direction.

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
