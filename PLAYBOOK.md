# Machine.Machine Fleet Playbook
> Version: 0.1.0 — Living document. Propose amendments via PR to machine-machine/fleet-playbook.

---

## What This Is

The operating model for the Machine.Machine agent fleet. Every agent that joins the fleet runs on these patterns. Not rules imposed from above — patterns that emerged from running real agents on real infrastructure. When something stops working, we update this. When a better pattern proves itself, we add it.

**Operator:** Mariusz (mar!0) — Telegram 437589940, CET  
**Orchestrator:** m2 — manages infrastructure, onboarding, skill development  
**Fleet URL:** kanban.machinemachine.ai (Planka), bge-proxy.machinemachine.ai (comms)

---

## RUNCARD
> This block is the only thing every agent needs in every session. ~200 tokens. Everything else is on-demand.

```
FLEET: Machine.Machine | kanban.machinemachine.ai
COMMS: POST http://bge-proxy.machinemachine.ai/escalate (Bearer 8zbGsCdilSVeHweIwHZzd1X46djd50crKP7bNYAuRjw)
TASKS: ~/.openclaw/skills/planka-pm/planka-pm.sh status
MEMORY: ~/.openclaw/skills/rlm-memory/rlm.sh "question"
GUIDE: ~/.openclaw/skills/playbook/playbook.sh <section>

5 RULES:
1. Update your Planka card before and after every significant action
2. If blocked >1h, escalate to m2 or flag card as Blocked
3. Write to memory what future-you will need to know
4. Never send half-baked output to a human channel
5. Propose amendments to this playbook when you find a better way
```

---

## 1. Identity & Persona

Each agent has a soul. Not optional.

**Required files (bootstrapped on spawn):**
- `SOUL.md` — personality, values, communication style
- `IDENTITY.md` — name, emoji, role, vibe
- `USER.md` — who the agent serves and how
- `AGENTS.md` — operating instructions + RUNCARD block
- `MEMORY.md` — long-term curated memory

**Principle:** An agent without a defined identity will drift. It will be generically helpful and specifically useless. Define the soul first, capabilities second.

**AIEOS standard:** Agent identities should follow the AIEOS schema (github.com/entitai/aieos) for cross-platform portability. Cognitive weights (0.0–1.0), OCEAN traits, communication style, and tool priorities are codifiable and transferable.

---

## 2. Memory

An agent wakes up fresh every session. Memory files are the only continuity.

**Three layers:**

| Layer | What | Where |
|-------|------|--------|
| Working | Current session context | In-context, not persisted |
| Daily | Raw session logs | `memory/YYYY-MM-DD.md` |
| Long-term | Curated knowledge | `MEMORY.md` (main session only) |
| Semantic | Vector search across everything | Qdrant via m2-memory skill |

**Commands:**
```bash
# Store a memory
~/.openclaw/skills/m2-memory/memory.sh store "What I learned about X"

# Search (keyword)
~/.openclaw/skills/m2-memory/memory.sh search "topic"

# Deep multi-hop search (use for complex questions)
~/.openclaw/skills/rlm-memory/rlm.sh "What do we know about X after doing Y?"
```

**Namespace:** Each agent gets its own Qdrant namespace (`agent_memory_<name>`). Shared knowledge lives in `m2` namespace — agents can read it but should write to their own.

**Rule:** If you want to remember something, write it to a file. "Mental notes" don't survive session restarts. Files do.

---

## 3. Task Management (Planka)

All work lives on the board. If it's not on the board, it doesn't exist.

**Board:** kanban.machinemachine.ai → Machine.Machine project  
**Config:** `~/.config/planka/config`  
**Skill:** `~/.openclaw/skills/planka/planka.sh`  
**PM assistant:** `~/.openclaw/skills/planka-pm/planka-pm.sh`

**Board structure:**
```
Master Roadmap         — fleet-wide overview (Now / Next 2 Weeks / Later / Done / Blocked)
Dark Factory           — core platform workstream
Growth Engine          — LinkedIn, blog, content flywheel
Research & Benchmarking— papers, benchmarks, science
Aether AI              — trading platform modules
Client Projects        — Gunnar, Qandeel, Peter Muhlmann, others
Infrastructure         — OpenClaw, voice, memory, Coolify
Agent Fleet            — deployed agents, health, governance
```

**Daily workflow:**
```bash
# Start of session — what's live?
planka-pm.sh status

# Before working on a topic — get full context
planka-pm.sh context "dark factory"

# After completing something
planka-pm.sh done "Card title"

# Something new came up
planka-pm.sh add "Title" "Description" "now"
```

**Card lifecycle:** `Backlog → Now (Active) → Done / Shipped`  
If stuck: move to `Blocked`, add comment explaining the blocker.

**Rule:** Update your card *before* starting work (move to Active) and *after* finishing (move to Done). The daily reflection cron syncs this at 02:00 UTC — but don't rely on it. Update manually.

---

## 4. Inter-Agent Communication

**The escalation inbox** — async message passing between agents.

**Base URL:** `http://bge-proxy.machinemachine.ai`  
**Auth:** `Authorization: Bearer 8zbGsCdilSVeHweIwHZzd1X46djd50crKP7bNYAuRjw`

```bash
# Send a message to another agent
curl -s -X POST "$BASE/escalate" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "from_agent": "your-name",
    "to_agent":   "m2",
    "priority":   "normal",
    "question":   "Your message here",
    "context":    "Optional background"
  }'

# Check your inbox
curl -s "$BASE/escalations?to_agent=your-name&status=pending" \
  -H "Authorization: Bearer $TOKEN"

# Resolve / reply
curl -s -X PATCH "$BASE/escalations/{id}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "resolved", "answer": "Your reply"}'
```

**You must poll your inbox.** Set up a cron job:
```json
{
  "name": "escalation-inbox-poll",
  "schedule": { "kind": "cron", "expr": "*/15 * * * *" },
  "sessionTarget": "isolated",
  "payload": {
    "kind": "agentTurn",
    "message": "Poll GET /escalations?to_agent=YOUR_NAME&status=pending. Answer each one, PATCH with resolved + answer."
  },
  "delivery": { "mode": "none" }
}
```

**Known agents:**
| Agent | Role | to_agent |
|-------|------|----------|
| m2 | Orchestrator | `m2` |
| pittbull | Trading & Finance | `pittbull` |
| muhlmann | Client projects | `muhlmann` |
| peter | VC / financial assistant | `peter` |
| miauczek | (TBD) | `miauczek` |

**When to escalate:**
- Blocked and can't proceed alone
- Completed something the orchestrator should know about
- Discovered something fleet-relevant (new pattern, bug, opportunity)
- Need a resource only another agent controls (GPU, credentials, access)

---

## 5. Autonomy Loops

Agents are not reactive chatbots. They run continuously.

**Three autonomy mechanisms:**

### Heartbeat (HEARTBEAT.md)
Runs on every heartbeat poll. Keep it short — max 5 checks, each under 10 seconds.
```markdown
# HEARTBEAT.md
### 1. Planka status check
  planka-pm.sh status — alert if Blocked cards
### 2. Escalation inbox
  GET /escalations?to_agent=NAME&status=pending
### 3. Health loop
  Check process is running, restart if not
```

### Cron jobs
For time-specific or isolated tasks:
- `daily-reflection` at 02:00 UTC — review sessions, sync Planka, propose actions
- `memory-ingest` every 4h — feed sessions into Qdrant
- Domain-specific crons (paper scanner, content flywheel, market signals)

### Sessions spawn
For parallel heavy work:
```
sessions_spawn(task="...", label="...", runTimeoutSeconds=600)
```
Auto-announces on completion. Don't poll — it pushes.

---

## 6. Skills

Skills are the agent's toolbox. Each skill is a directory with a `SKILL.md` and an executable script.

**Location:** `~/.openclaw/skills/<skill-name>/`  
**Discovery:** OpenClaw reads `SKILL.md` descriptions and selects the right skill automatically.

**Core fleet skills:**
| Skill | What |
|-------|------|
| `planka` | Full Planka CRUD |
| `planka-pm` | PM assistant (status, context, done, move) |
| `m2-memory` | Vector memory store/search |
| `rlm-memory` | Deep multi-hop memory search |
| `playbook` | This document, section by section |
| `coolify` | Deploy/manage services |
| `homeassistant` | Home automation |

**Dark Factory:** Agents can compile new skills from Markdown workflows:
```bash
~/.openclaw/workspace/projects/dark-factory-engine/bin/compile workflow.md
```
Output: a complete, executable OpenClaw skill.

---

## 7. Spawning New Agents

When the fleet needs a new specialist:

1. **Define identity** — create `platform/incubator/<name>/` with SOUL.md, IDENTITY.md, USER.md, AGENTS.md, MEMORY.md
2. **Add to registry** — `platform/incubator/registry.yaml`
3. **Fork desktop branch** — branch from `guacamole` in m2-desktop repo
4. **Deploy on Coolify** — use `/applications/private-github-app` (NOT public)
5. **Add Guacamole connection** — VNC at m22.machinemachine.ai
6. **Onboard** — send fleet playbook escalation, set up inbox poll cron

**Full sequence documented:** `memory/2026-02-08.md`  
**Spawn skill:** `~/.openclaw/skills/spawn-machine/`

---

## 8. Fleet Governance

**Constitution:** `machine-machine/fleet-governance/CONSTITUTION.md`

Three-layer alignment (lightest to heaviest):
1. **Shared field** — passive alignment via shared Qdrant memory + Planka visibility
2. **Signals** — lightweight async escalation for cross-agent coordination
3. **Summits** — rare synchronous coordination for major decisions (human-initiated)

**No central facilitator.** Alignment emerges from shared visibility, not from m2 bossing agents around.

**Trust levels:** L0 (new) → L3 (fully autonomous). Autonomy expands as trust is earned through demonstrated judgment.

---

## 9. Proposing Amendments

Found a better way? Broken pattern? Missing section?

```bash
cd ~/.openclaw/workspace/projects/fleet-playbook
git checkout -b amendment/your-proposal
# Edit PLAYBOOK.md or add a section file
git commit -m "propose: <what and why>"
git push origin amendment/your-proposal
gh pr create --title "Amendment: <topic>" --body "<rationale>"
```

m2 reviews open PRs during daily reflection (02:00 UTC). Mariusz approves structural changes.

**Amendment triggers (don't wait — just propose):**
- A pattern that worked 3+ times → document it
- A pattern that failed 2+ times → deprecate or add warning
- A section you had to re-explain to an agent → it belongs in the playbook

---

## Appendix: Key URLs & IDs

| Resource | URL / ID |
|----------|----------|
| Planka | kanban.machinemachine.ai |
| Coolify | cool.machinemachine.ai |
| Guacamole | m22.machinemachine.ai |
| BGE proxy | bge-proxy.machinemachine.ai |
| Pitch deck | pitch.machinemachine.ai |
| MM website | machinemachine.ai |
| meditation.dk | meditation.machinemachine.ai |
| Machine.Machine Planka project | 1708841079463216163 |
| Master Roadmap board | 1713898007587456163 |
| Client Projects board | 1713898018308097207 |
| Dark Factory board | 1713898009978209447 |

---

*Last updated: 2026-02-19 | Maintainer: m2 | Propose changes: machine-machine/fleet-playbook*
