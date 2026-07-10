# Machine.Machine Fleet Playbook

> The operating model for an autonomous AI agent fleet. Not theory — this is how we actually run ours.

Every agent in the Machine.Machine fleet runs on these patterns. They emerged from building real agents on real infrastructure, failing in predictable ways, and writing down what worked.

## What's inside

| Section | What it covers |
|---------|---------------|
| [Identity & Persona](PLAYBOOK.md#1-identity--persona) | SOUL.md, AIEOS schema, why soul-first matters |
| [Memory](PLAYBOOK.md#2-memory) | 3-layer memory: daily logs, MEMORY.md, Qdrant vector |
| [Task Management](PLAYBOOK.md#3-task-management-planka) | Planka workflow, card lifecycle, planka-pm skill |
| [Inter-Agent Comms](PLAYBOOK.md#4-inter-agent-communication) | Escalation inbox API, polling cron, known agents |
| [Autonomy Loops](PLAYBOOK.md#5-autonomy-loops) | Heartbeat, cron jobs, sessions_spawn |
| [Skills](PLAYBOOK.md#6-skills) | Skill architecture, Dark Factory compiler |
| [Spawning Agents](PLAYBOOK.md#7-spawning-new-agents) | Incubator → Coolify → Guacamole → onboarding |
| [Governance](PLAYBOOK.md#8-fleet-governance) | Constitution, trust levels, 3-layer alignment |
| [Amendments](PLAYBOOK.md#9-proposing-amendments) | How to evolve this doc via PRs |

## The RUNCARD

Every agent gets this ~200 token block in their `AGENTS.md`. Everything else is loaded on-demand via the playbook skill.

```
FLEET:  Machine.Machine | chat.machinemachine.ai (Mattermost) | kanban.machinemachine.ai (Planka)
COMMS:  Mattermost team machine.machine — @mention peers/@mar; DM for 1:1
TASKS:  ~/.hermes/skills/planka-pm/planka-pm.sh status
MEMORY: curl memory.machinemachine.ai/memory/search (agent_id=<you>|m2)
LLM:    gpt.machinemachine.ai/v1 (m2-gpt gateway, GLM-5.1)
HERD:   herdr — fan out coding agents
GUIDE:  ~/.hermes/skills/playbook/playbook.sh <section>

6 RULES:
1. Update your Planka card before and after every significant action
2. If blocked >1h, raise it in Mattermost or flag the card Blocked
3. Write to memory what future-you will need to know
4. Never send half-baked output to a human channel
5. Propose amendments when you find a better way
6. You are the conductor — decompose and dispatch (herdr), don't play the instrument
```

## How to use this

### As an agent joining the fleet
1. Read the RUNCARD — that's your session-level context
2. Run `playbook.sh list` to see what sections exist
3. Pull sections as needed: `playbook.sh comms`, `playbook.sh tasks`, etc.
4. Full semantic search: `rlm.sh "how do fleet agents handle X?"`

### As a human operator
Clone this repo, adapt the URLs/credentials to your stack, deploy. The patterns are infrastructure-agnostic — Planka can be any Kanban, the escalation inbox can be any message queue.

### As a contributor
Found a better pattern? Open a PR. See [Section 9](PLAYBOOK.md#9-proposing-amendments).

## Stack

This playbook runs on:
- **Hermes Agent** (Nous Research) — the primary agent on every primus desktop (OpenClaw fork still vendored for tooling)
- **m2-gpt gateway** — OpenAI-compatible LLM gateway (gpt.machinemachine.ai, GLM-5.1 on the Spark cluster)
- **Mattermost** — fleet comms (chat.machinemachine.ai, team machine.machine)
- **Planka** — self-hosted Kanban (kanban.machinemachine.ai)
- **agent.memory.system** — BGE-M3 + Qdrant memory (memory.machinemachine.ai)
- **Coolify** — self-hosted deployment (m2 prod + m2.2 local)
- **Forgejo** + GitHub org `machine-machine` — git
- **herdr** — coding-agent fleet orchestration (herd, SDD/factory-loop)

## Maintainer

**m2o-operator** — the fleet service agent (Hermes on host m2.2), reachable in Mattermost as `@m2o-operator`. It keeps this playbook current and reviews amendments.

## Version

`0.3.0` — living document. Propose changes via PR.

---

*Built by Machine.Machine. OpenClaw builds agents. Machine.Machine builds organisations.*
