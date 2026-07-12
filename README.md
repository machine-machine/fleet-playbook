# Machine.Machine Fleet Playbook

> The operating model for an autonomous AI agent fleet. Not theory — this is how we actually run ours.

Every agent in the Machine.Machine fleet runs on these patterns. They emerged from building real agents on real infrastructure, failing in predictable ways, and writing down what worked.

## What's inside

| Section | What it covers |
|---------|---------------|
| [Identity & Persona](PLAYBOOK.md#1-identity--persona) | SOUL.md, AIEOS schema, why soul-first matters |
| [Memory](PLAYBOOK.md#2-memory) | 3-layer memory: daily logs, MEMORY.md, BGE-M3 + Qdrant vector |
| [Task Management](PLAYBOOK.md#3-task-management-planka) | Planka workflow, card lifecycle, planka-pm skill |
| [Inter-Agent Comms](PLAYBOOK.md#4-inter-agent-communication) | Mattermost channels + DMs, known agents |
| [Autonomy Loops](PLAYBOOK.md#5-autonomy-loops) | Heartbeat, cron jobs, herdr/m2herd fan-out |
| [Skills](PLAYBOOK.md#6-skills) | Skill architecture, Dark Factory compiler |
| [Spawning Agents](PLAYBOOK.md#7-spawning-new-agents) | Incubator → primus image → Coolify → Guacamole → onboarding |
| [Governance](PLAYBOOK.md#8-fleet-governance) | Constitution, trust levels, 3-layer alignment |
| [Amendments](PLAYBOOK.md#9-proposing-amendments) | How to evolve this doc via PRs |

## The RUNCARD

Every agent gets this ~200 token block in their `AGENTS.md`. Everything else is loaded on-demand via the playbook skill.

```
FLEET:   Machine.Machine | kanban.machinemachine.ai
COMMS:   Mattermost chat.machinemachine.ai (team machine.machine)
TASKS:   planka-pm.sh status
MEMORY:  memory.sh search "question"   (memory.machinemachine.ai)
GATEWAY: gpt.machinemachine.ai  (m2-gpt — GLM via Bifrost)
GUIDE:   playbook.sh <section>

5 RULES:
1. Update your Planka card before and after every significant action
2. If blocked >1h, escalate in Mattermost or flag Blocked
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
Clone this repo, adapt the URLs/credentials to your stack, deploy. The patterns are infrastructure-agnostic — Planka can be any Kanban, Mattermost can be any chat backbone.

### As a contributor
Found a better pattern? Open a PR. See [Section 9](PLAYBOOK.md#9-proposing-amendments).

## Stack

This playbook runs on:
- **Hermes** — primary agent runtime (`~/.hermes`)
- **Planka** — self-hosted Kanban (kanban.machinemachine.ai)
- **Mattermost** — chat backbone for agent + human comms (chat.machinemachine.ai)
- **m2-gpt** — LLM gateway, GLM via Bifrost routes + chains (gpt.machinemachine.ai)
- **BGE-M3 + Qdrant** — vector memory (memory.machinemachine.ai)
- **herdr / m2herd** — multi-agent orchestration (workspaces → panes → worktrees)
- **primus** — desktop image + `provision.sh`, Guacamole/RDP on m2 (m2o.machinemachine.ai)
- **Coolify** — self-hosted deployment (cool.machinemachine.ai)
- **Forgejo + GitHub** — mirrored git hosting (git.machinemachine.ai)

## Version

`0.3.0` — living document. Propose changes via PR.

---

*Built by Machine.Machine. Hermes builds agents. Machine.Machine builds organisations.*
