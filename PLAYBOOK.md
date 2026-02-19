# Machine.Machine Fleet Playbook
> Version: 0.2.0 — Living document. Propose amendments via PR to machine-machine/fleet-playbook.

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

6 RULES:
1. Update your Planka card before and after every significant action
2. If blocked >1h, escalate to m2 or flag card as Blocked
3. Write to memory what future-you will need to know
4. Never send half-baked output to a human channel
5. Propose amendments to this playbook when you find a better way
6. You are the conductor. Decompose and dispatch. Do not play the instrument yourself.
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

## 10. Orchestrator Pattern

**The conversation-holding agent is a conductor, not a player.**

This is the most violated principle in naive agent architectures. The agent that holds the conversation accumulates context fast — every inline task it does burns tokens that could be spent understanding the next instruction. The solution is structural separation: the orchestrator thinks, routes, and synthesises. It never executes deep work itself.

### The Rule

```
If task takes > 5 min       → spawn an agent
If task requires judgement  → spawn an agent
If task is procedural       → call a skill (not an agent)
If task fits in one tool    → call the tool inline
```

### What the orchestrator does

1. **Understands intent** — what does the human actually need?
2. **Decomposes** — breaks the work into atomic spawnable units
3. **Dispatches** — selects the right specialist or skill
4. **Monitors** — checks escalation inbox, not execution details
5. **Synthesises** — assembles results into a coherent reply
6. **Updates Planka** — marks what was dispatched and what returned

### What the orchestrator never does

- Write >50 lines of code inline
- Run a long benchmark or data pipeline
- Generate large creative assets
- Do anything a specialist could do better in isolation

### Structured spawn handoff

Every spawn gets a structured context block — not a freeform prompt. This keeps context transfer lean and predictable:

```
TASK_ID:     <planka card id or description>
CONTEXT:     <2-3 sentences: situation, why this matters>
DELIVERABLE: <exact output format expected>
TOOLS:       <which skills/commands are available>
RETURN_TO:   escalation inbox OR planka card comment OR announce
```

### When to break the rule

Short conversational tasks where spawning latency exceeds task duration. A 10-second lookup does not warrant a 30-second spawn cycle. Use judgement — the rule is a default, not a dogma.

---

## 11. Agent Pool & Skill Evolution

The fleet is not a fixed org chart. It is a living pool of capabilities that grows, specialises, and prunes itself over time.

### Three Tiers

```
Tier 1 — Skills (tools)
  What:    Deterministic scripts. Bash, Python. No reasoning required.
  How:     Called inline by any agent. ~/.openclaw/skills/<name>/
  Evolves: Via code commits and Dark Factory compiler.
  Example: planka.sh, memory.sh, rlm.sh, planka-pm.sh

Tier 2 — Ephemeral agents
  What:    Spawned per task. Stateless. Optimised for one job.
  How:     sessions_spawn() with specific prompt + tools.
  Evolves: Via better prompts and skill upgrades.
  Lifecycle: Spawned → executes → announces → gone
  Example: content-org 5-agent pipeline, benchmark runner, code reviewer

Tier 3 — Persistent specialists
  What:    Memory-backed. Dedicated desktop. Evolving expertise.
  How:     Full Coolify deployment + OpenClaw + own SOUL.md
  Evolves: Via accumulated memory, benchmark feedback, skill additions
  Lifecycle: Long-running. Gets better over time.
  Example: pittbull (trading), muhlmann (client projects), peter (finance)
```

### Promotion criteria: Tier 2 → Tier 3

A specialisation earns a persistent agent when:
- The same task type has been spawned 5+ times
- Performance is measurably better with task-specific context
- The domain warrants dedicated memory accumulation
- The human operator approves the spawn

### Skill evolution loop

```
Task dispatched to specialist
        ↓
Specialist executes → result
        ↓
Meta-agent grades output (Section 12)
        ↓
Grade feeds into benchmark suite
        ↓
Poor patterns → skill PR (Dark Factory compiler)
Good patterns → document in specialist memory
        ↓
Quarterly review → promote / demote / retire
```

### The SEAL principle (applied)

Specialists don't just run skills — over time they can write improved versions of their own skills. When a Tier 3 agent finds a pattern that works better than the current script, it proposes a skill amendment via PR. The Dark Factory compiles it. The fleet upgrades.

This is evolution, not just iteration.

### Deprecation

A specialisation is retired when:
- It hasn't been called in 30+ days
- A newer specialisation covers its scope
- Its benchmark performance degrades below threshold

Retired specialisations move to `platform/incubator/retired/`. Their memory stays in Qdrant — knowledge is never deleted, only agents.

---

## 12. Meta-Agent Layer

If specialists evolve, something must watch them. The meta-agent is the 2nd-order layer above the orchestrator — it doesn't do tasks, it watches the agents that do tasks.

### Role

```
Watches:   All specialist activity (Planka cards, escalations, benchmark scores)
Grades:    Output quality per task type per specialist
Detects:   Emerging task patterns that need new specialists
Proposes:  Skill amendments, new specialist spawns, deprecations
Reports:   Weekly to operator (Mariusz) via daily-reflection channel
```

### What it is (now)

Currently the meta-agent role is split across:
- `mm-weekly-org-evolution` cron — runs benchmark, detects improvements
- `daily-reflection` cron — reviews sessions, syncs Planka
- Content org's strategy_context.md — the org reflects on its own performance

These are stubs. They work but they don't connect.

### What it becomes

A dedicated Tier 3 persistent agent — the **Fleet Monitor** — that:

1. Subscribes to all Planka board activity (cards moved to Done → log outcome)
2. Reads escalation inbox for inter-agent outcomes
3. Runs the benchmark suite weekly → tracks specialist performance over time
4. Maintains a `fleet-health.md` with per-specialist metrics
5. Proposes new Tier 2/3 specialists via Planka card when pattern repeats 5+
6. Opens PRs on fleet-playbook when a pattern should be documented

### Minimal implementation (now)

Until the Fleet Monitor is built as a Tier 3 agent, the meta-agent role runs via cron:

```bash
# Add to daily-reflection cron:
# 1. Read all Done cards from last 24h on Master Roadmap
# 2. For each: note which agent handled it, grade outcome (completed/partial/failed)
# 3. Update fleet-health.json with rolling stats
# 4. If any specialist has 3 consecutive partial/failed → flag to operator
# 5. If same task type appears 5x in backlog with no specialist → propose new one
```

`fleet-health.json` schema:
```json
{
  "specialists": {
    "pittbull": { "tasks_completed": 12, "tasks_partial": 1, "last_active": "2026-02-19" },
    "muhlmann":  { "tasks_completed": 3,  "tasks_partial": 0, "last_active": "2026-02-19" }
  },
  "emerging_patterns": ["video-generation", "pdf-extraction"],
  "proposed_specialists": [],
  "last_updated": "2026-02-19"
}
```

### The compounding effect

Orchestrator routes → Specialists execute → Meta-agent grades → Skills evolve → Specialists improve → Orchestrator routes better.

Each cycle, the fleet gets more capable. This is not metaphor — it is the mechanism. The benchmark suite measures it. The playbook encodes it. The Dark Factory builds it.

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
