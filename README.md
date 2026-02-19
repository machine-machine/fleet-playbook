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
FLEET: Machine.Machine | kanban.machinemachine.ai
COMMS: POST http://bge-proxy.machinemachine.ai/escalate
TASKS: planka-pm.sh status
MEMORY: rlm.sh "question"
GUIDE: playbook.sh <section>

5 RULES:
1. Update your Planka card before and after every significant action
2. If blocked >1h, escalate or flag Blocked
3. Write to memory what future-you will need to know
4. Never send half-baked output to a human channel
5. Propose amendments when you find a better way
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
- **OpenClaw** — agent runtime (github.com/openclaw/openclaw)
- **Planka** — self-hosted Kanban (kanban.machinemachine.ai)
- **Qdrant + BGE-M3** — vector memory
- **Coolify** — self-hosted deployment
- **Custom escalation inbox** — async inter-agent messaging

## Version

`0.1.0` — living document. Propose changes via PR.

---

*Built by Machine.Machine. OpenClaw builds agents. Machine.Machine builds organisations.*
