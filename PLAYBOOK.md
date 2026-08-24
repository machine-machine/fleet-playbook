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
COMMS: POST http://bge-proxy.machinemachine.ai/escalate (Bearer REDACTED-ROTATED)
TASKS: ~/.openclaw/skills/planka-pm/planka-pm.sh status
MEMORY: ~/.openclaw/skills/rlm-memory/rlm.sh "question"
GUIDE: ~/.openclaw/skills/playbook/playbook.sh <section>

6 RULES:
1. Open or update a Planka card for any task that spans >3 exchanges. Single-exchange tasks don't need a card.
2. If blocked >1h, escalate to m2 or flag card as Blocked
3. Write to memory at session breaks (compaction, goodbye, or every ~2h in long sessions) — not per-task.
4. Never send half-baked output to a human channel
5. Propose amendments to this playbook when you find a better way
6. You are the conductor. Decompose and dispatch. Do not play the instrument yourself. (See §10 for dispatch threshold.)
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

**When to write:** At session breaks — context compaction, human signs off, or every ~2h in long sessions. Not after every task. One write per break covers everything that happened since the last write. If you defer it, you lose it.

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

**Rule:** Open a card if the task takes >3 exchanges (back-and-forth with human or sub-agents). Update it when you start (move to Active) and when done (move to Done). Single-exchange tasks — quick fixes, one-liners, status checks — don't need a card. The daily reflection cron syncs at 02:00 UTC but don't rely on it.

---

## 4. Inter-Agent Communication

**The escalation inbox** — async message passing between agents.

**Base URL:** `http://bge-proxy.machinemachine.ai`  
**Auth:** `Authorization: Bearer REDACTED-ROTATED`

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

## 7b. Onboarding Protocol

When a new agent joins the fleet, it goes through a three-phase onboarding pipeline.
The goal: the agent arrives warm-started, not cold-booted.

### The Three Phases

```
Phase 0: Discovery     (2-5 min)    → Mine context, build bootstrap-memory.jsonl
Phase 1: Deployment    (15-30 min)  → 7-step spawn workflow (define → validate)
Phase 2: First Contact (~60s)       → Agent sends warm intro to operator
```

### Phase 0: Pre-Spawn Discovery

Before asking the operator anything, search existing context:
- Vector memory for prior discussions about this agent
- Planka for related active work
- Existing skills that overlap with the agent's domain

Output: `platform/incubator/{name}/bootstrap-memory.jsonl` — a JSONL file of seed memories
that gets ingested into the agent's Qdrant namespace on first boot.

### Phase 1: Deployment

The standard spawn-machine workflow (Steps 01-07). Phase 0 outputs reduce friction:
- Agent profile pre-filled from discovery
- Service recommendations pre-computed
- Identity file drafts are better on first try

**Skill:** `~/.openclaw/skills/spawn-machine/`
**BMAD workflow:** `_bmad/bmm/workflows/spawn-machine/`

### Phase 2: First Contact

~60 seconds after validation, the new agent sends its first message:

```
{AgentName} online. I know you're working on {X}. My first suggestion: {Y}.
```

- `{X}` = operator's top project from bootstrap memory
- `{Y}` = concrete suggestion from the agent's specialization

Delivery: Telegram text (default). Voice notes if TTS is enabled. Google Meet for future high-touch onboarding.

### When to Use This Protocol

| Scenario | What to Do |
|----------|------------|
| New Tier 3 persistent agent | Full protocol (Phase 0 + 1 + 2) |
| Tier 2 → Tier 3 promotion | Phase 0 + Phase 1 (Tier 2 context feeds bootstrap memory) |
| Quick test deployment | Phase 1 only (skip discovery, minimal identity) |
| Redeploying existing agent | Phase 1 Steps 5-7 only (preserve identity, redeploy container) |

### Key Outputs

| Output | Location | Purpose |
|--------|----------|---------|
| `bootstrap-memory.jsonl` | `platform/incubator/{name}/` | Warm-start memory payload |
| `agent-spec.md` | `platform/incubator/{name}/` | Agent definition + workflow state |
| `first-contact.log` | `platform/incubator/{name}/` | Record of first intro message |
| Identity files | `platform/incubator/{name}/` | SOUL.md, IDENTITY.md, USER.md, AGENTS.md, MEMORY.md |

### Bootstrap Memory Ingest

New agents ingest `bootstrap-memory.jsonl` on first boot via their AGENTS.md:

```bash
BOOTSTRAP="platform/incubator/{name}/bootstrap-memory.jsonl"
if [ -f "$BOOTSTRAP" ]; then
  while IFS= read -r line; do
    content=$(echo "$line" | jq -r '.content')
    importance=$(echo "$line" | jq -r '.importance // 0.7')
    ~/.openclaw/skills/m2-memory/memory.sh store "$content" --importance "$importance"
  done < "$BOOTSTRAP"
  mv "$BOOTSTRAP" "${BOOTSTRAP}.ingested"
fi
```

**Full protocol docs:** `docs/ONBOARDING_PROTOCOL.md`

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
If task takes > 5 min            → spawn an agent
If task requires judgement       → spawn an agent
If task is iterative/trial-error → spawn an agent (browser automation, image processing, code debug)
If task is procedural            → call a skill (not an agent)
If task fits in one tool call    → call the tool inline
```

**Signal to spawn:** >10 tool calls expected, OR the task involves repeated attempts to get something right (UI automation, multi-step pipelines, creative generation). These burn orchestrator context fast and should be isolated.

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
Capture learnings immediately (self-improve.sh learn)
        ↓
Meta-agent grades output (Section 12)
        ↓
Grade feeds into benchmark suite
        ↓
Poor patterns → skill PR (Dark Factory compiler)
Good patterns → document in specialist memory (m2-memory)
        ↓
Weekly review → AMENDMENT_DRAFT.md → apply or gate
        ↓
Monthly fleet-review → playbook PR → promote / demote / retire
```

### Self-Improvement Skill

Every Tier 3 agent runs the `self-improve` skill as part of its autonomy loop.

```bash
# Capture immediately when something goes wrong or gets corrected
self-improve.sh learn "<what happened>" --failure|--correction [--fix "<fix>"]

# Recall past learnings semantically (m2-memory powered)
self-improve.sh recall "docker network issues"

# Weekly: synthesize → draft amendments
self-improve.sh review   # → docs/AMENDMENT_DRAFT.md

# Monthly: fleet aggregate → playbook PR
self-improve.sh fleet-review
```

**Memory stack (two systems, complementary):**
- `m2-memory` (Qdrant + BGE-M3) — retrieval-focused: STANDARD → DEEP → SYNTHESIS routing
- `rlm-memory` (Cerebras RLM) — open-ended reasoning: "what are we systematically missing?"
- m2-memory: `learn`, `recall`, `review`, `fleet-review`
- RLM: `fleet-review` only (depth 3, iterative multi-hop)

**Retro observation parking** (any agent, any time — no threshold):
```bash
self-improve.sh observe "pattern we keep hitting" --infra|--tooling|--workflow|--comms
```
Accumulates in `memory/fleet-retro.md` + Qdrant (entity: `retro`). Monthly `fleet-review` synthesises all via RLM.

**Risk gating:**
- Low-risk (wording, script fixes) → apply directly + commit
- High-risk (behavior changes, new capabilities) → PR + Telegram inline button for master approval

Skill repo: `machine-machine/openclaw-self-improve-skill`

### The SEAL principle (applied)

Specialists don't just run skills — over time they can write improved versions of their own skills. When a Tier 3 agent finds a pattern that works better than the current script, it captures a learning via `self-improve.sh learn`, the weekly review surfaces it, and the Dark Factory compiles the PR. The fleet upgrades.

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
- `self-improve.sh review` — weekly per-agent amendment synthesis (m2-memory backed)
- `self-improve.sh fleet-review` — monthly cross-agent pattern detection + playbook PR
- Content org's strategy_context.md — the org reflects on its own performance

The self-improve skill is the connective tissue that was missing — it links reactive capture → semantic memory → periodic synthesis → amendment PRs.

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

## 12b. m2o Desktop Provisioning (RDP + cross-host Guacamole)

Every fleet agent runs on an **m2o desktop** — a persistent Ubuntu container with `x11vnc`, `xrdp`, `guacd`, `ttyd`, and Hermes baked in (primus image). Two hosts run desktops today:

| Host | LAN IP(s) | SSH user | provision.sh path | Local Guacamole? |
|------|-----------|----------|-------------------|------------------|
| **m2** (primary) | `192.168.31.224`, `192.168.31.28` | `m2` | `~/m2o/desktop/provision.sh` | ✅ `guacamole-full` + `guacamole-db` (Coolify service `e0o8o8cowkswcwsgs4so48s8`) |
| **m2.2** (secondary) | `192.168.31.34` | `m2.2` | `~/machinemachine-core/m2o/desktop/provision.sh` | ❌ own Coolify, no Guacamole stack |

> **Path gotcha:** on m2.2 the script is under `~/machinemachine-core/m2o/`, not `~/m2o/`. The `m2o-provision` skill doc uses the upstream `~/m2o/` path — treat as advisory, not literal for m2.2.

> **DNS gotcha:** from inside fleet docker containers (e.g. anything on the `coolify` network), both `m2` and `m2.2` frequently resolve to the *same* tailnet address (whichever host the container runs on). When you need to reach the *other* host, use its LAN IP, not the name.

### Spawn a desktop — one command, full setup

Use the **`launch-desktop.sh`** wrapper (installed at `~/m2o/desktop/launch-desktop.sh` on m2 and `~/machinemachine-core/m2o/desktop/launch-desktop.sh` on m2.2; canonical source: `scripts/launch-m2o-desktop.sh` in this repo). It runs `provision.sh`, waits for healthy, creates the socat guacd relay (m2.2 only), upserts the Guacamole RDP row on m2, and grants perms — all idempotent.

```bash
# on the target host, as its own user (m2 or m2.2)
cd ~/m2o/desktop      # or ~/machinemachine-core/m2o/desktop on m2.2
./launch-desktop.sh <name> [--vnc-pass X] [--grant-users guacadmin,m2,...]
```

Flags: `--relay-port <n>` (default: auto-pick next `X4822`), `--m2-ssh <user@host>` (default `m2@192.168.31.224`), `--skip-guacamole`, `--force-recreate`.

**Raw provision (if you only want the container, no Guacamole wiring):**

```bash
cd ~/m2o/desktop      # or ~/machinemachine-core/m2o/desktop on m2.2
./provision.sh <name> [vnc_password]     # e.g. ./provision.sh euroclean
```

Creates container `<name>-m2o` on the `coolify` docker network + named volumes `<name>-{agent-home,workspace,m2home}` (survive re-provision). `M2_GPT_API_KEY` is injected from `~/.m2-gpt-key` (host side, per-user). Fleet standard 2026-07-09: **RDP is the default access path**; VNC is fallback.

### First-boot wait (~2 min "unhealthy" is normal)

The entrypoint does a long `rm -rf /home` before x11vnc/xrdp start. The container will show `unhealthy` and ports 5900/3389 will refuse connections for 60–120s. Don't kill it — the health check flips once services come up. To watch:

```bash
docker inspect <name>-m2o --format '{{.State.Health.Status}}'
docker exec <name>-m2o bash -lc 'ps -eo pid,etime,cmd | grep -E "rm -rf|x11vnc|xrdp|guacd" | grep -v grep'
```

### Expected WARNs on m2.2

Because m2.2 doesn't yet run its own Guacamole and only bridges console-auth via socat:

- `WARN: guacamole-db container not found — create the connection manually` — expected. Wire via `launch-desktop.sh` or the SQL in the next subsection.
- `WARN console: console-auth:latest image missing — cred saved to secrets.env` — expected. m2.2 doesn't host the console-auth image; a socat container named `console-auth` on m2.2's `coolify` network forwards `:8080` to `192.168.31.224:28080` (m2's `console-auth-lan-relay`), so Traefik's `forwardAuth` middleware works transparently. The cred **does still need to reach m2**: append the entry from `~/machinemachine-core/m2o/console-auth/secrets.env` (the `"<name>":"admin:..."` line inside `CONSOLE_BASIC_CREDS`) into m2's `~/m2o/console-auth/secrets.env` and restart `console-auth` on m2. See [Console (ttyd)](#console-ttyd-magic-link-flow) below.

### Console (ttyd, magic-link flow)

The `/console/<desktop>` browser terminal is served by ttyd inside the desktop container, fronted by Traefik with a `forwardAuth` middleware pointing at `console-auth`. There is only **one real `console-auth`** in the fleet — it runs on m2 (FastAPI, `console-auth:latest`, source at `~/m2o/console-auth/`). Both hosts route to it:

- **m2 desktops** → m2's Traefik → `console-auth` (same docker network) → ttyd inside the desktop container. Public host: `m2o.machinemachine.ai`.
- **m2.2 desktops** → m2.2's Traefik (public host: `console.m-2.cc`, Cloudflare) → m2.2's socat `console-auth` → m2's `console-auth-lan-relay:28080` → real console-auth on m2 → response back up the chain. ttyd is inside the desktop container on m2.2.

**Two things must be in sync per desktop** for the browser console to work:

1. **Traefik router `Host()`** must match the desktop's host (`m2o.machinemachine.ai` on m2, `console.m-2.cc` on m2.2). Old `provision.sh` hardcoded `m2o.machinemachine.ai` for both — **patched 2026-08-24** to read `CONSOLE_PUBLIC_HOST` from `console-auth/secrets.env` (m2.2's secrets sets it to `console.m-2.cc`; m2 leaves the default).
2. **The cred entry** (auto-generated per desktop by provision.sh into the local `secrets.env`) must exist in m2's `CONSOLE_BASIC_CREDS`. On m2 that's automatic (provision.sh redeploys the local console-auth). On m2.2 you must manually copy the `"<name>":"admin:..."` entry into m2's `~/m2o/console-auth/secrets.env` and `docker rm -f console-auth && docker run -d --name console-auth --restart unless-stopped --network coolify --env-file secrets.env console-auth:latest && docker network connect e0o8o8cowkswcwsgs4so48s8 console-auth`.

**Mint a magic link (admin key, from anywhere on m2):**

```bash
source ~/m2o/console-auth/secrets.env
CA_IP=$(docker inspect console-auth --format '{{(index .NetworkSettings.Networks "coolify").IPAddress}}')
curl -s -X POST -H "X-Api-Key: $CONSOLE_AUTH_ADMIN_KEY" \
     -H 'Content-Type: application/json' \
     -d '{"desktop":"<name>"}' \
     http://$CA_IP:8080/issue
# → returns {"url":"https://m2o.machinemachine.ai/console/<name>/?t=..."}
# For m2.2 desktops, swap the host to console.m-2.cc — the token is valid on any host
# (verify uses x-forwarded-host). Link is single-use, 15 min; session cookie is 24 h.
```

### Wiring an m2.2 desktop into m2's Guacamole

m2's `guacamole-full` needs to speak the guacd protocol to the desktop container (port 4822). On m2.2 that port lives inside the container on the `coolify` docker network — not published to the host. The established pattern is a **per-desktop `alpine/socat` relay** on m2.2 that publishes a unique host port and forwards to the desktop's internal `guacd:4822`.

Existing port allocations (append your own):

| Desktop | Host port on m2.2 |
|---------|-------------------|
| dealflow-legacy | 14822 |
| dealflow | 24823 |
| m2o-operator | 24822 |
| euroclean | 34822 |

**Step 1 — publish guacd on m2.2:**

```bash
# on m2.2, pick an unused port
docker run -d --name <name>-guacd-relay --restart unless-stopped \
  --network coolify -p <PORT>:<PORT> \
  alpine/socat tcp-listen:<PORT>,fork,reuseaddr tcp:<name>-m2o:4822
```

**Step 2 — insert Guacamole connection on m2** (via `guacamole-db`, user `root` / `guacamole_root_pass`):

```sql
INSERT INTO guacamole_connection (connection_name, protocol, proxy_hostname, proxy_port)
VALUES ('<Name> Desktop', 'rdp', '192.168.31.34', <PORT>);
SET @id = LAST_INSERT_ID();

INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES
  (@id,'hostname','127.0.0.1'), (@id,'port','3389'),
  (@id,'username','developer'), (@id,'password','<vnc_password>'),
  (@id,'width','1920'), (@id,'height','1080'), (@id,'color-depth','32'),
  (@id,'security','any'), (@id,'ignore-cert','true'),
  (@id,'enable-drive','true'), (@id,'drive-name','Shared'),
  (@id,'drive-path','/home/developer/Desktop/Shared'),
  (@id,'create-drive-path','true'), (@id,'enable-sftp','false');

INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT e.entity_id, @id, p.perm
FROM guacamole_entity e
CROSS JOIN (SELECT 'READ' AS perm UNION ALL SELECT 'UPDATE'
            UNION ALL SELECT 'DELETE' UNION ALL SELECT 'ADMINISTER') p
WHERE e.name = 'guacadmin' AND e.type = 'USER';
```

**Critical schema gotchas** (inherited from m2's Guacamole):

- `proxy_hostname` / `proxy_port` live on the `guacamole_connection` table, **not** on `guacamole_connection_parameter`.
- `hostname` inside the connection parameters stays `127.0.0.1` — guacd runs *inside* the desktop container, right next to x11vnc/xrdp.
- Use the `root` mysql user for writes. `guacamole_user` is SELECT-only.

**Naming standard 2026-07-09:** plain `'<Name> Desktop'` = RDP (default). Append `' (VNC)'` only for the fallback VNC row if you also create one.

### Access without Guacamole (m2.2 direct)

```bash
IP=$(docker inspect <name>-m2o --format '{{(index .NetworkSettings.Networks "coolify").IPAddress}}')
# from m2.2:            RDP client → $IP:3389   (developer / <vnc_password>)
# from a workstation:   ssh -L 3389:$IP:3389 m2.2@192.168.31.34, then RDP to localhost:3389
```

### Managing

```bash
docker ps --filter name=-m2o                          # list all m2o desktops on this host
docker rm -f <name>-m2o && ./provision.sh <name>      # rebuild (volumes preserved)
docker volume ls | grep <name>-                       # named volumes
docker inspect <name>-m2o --format '{{.State.Health.Status}}'
```

---

## 13. Infrastructure Architecture

The full infrastructure spec lives in: **[sections/architecture.md](sections/architecture.md)**

Quick reference:

| Component | Pattern |
|-----------|---------|
| Persistence | `M2_HOME=/agent_home` + host bind mount `/opt/m2o/{name}/home` |
| Identity | Env vars only (`AGENT_NAME`, keys) — no per-agent branches |
| Claude CLI | Pre-installed in Dockerfile; `claude update` on warm restart |
| Skill install | All skills = git repos, cloned on cold boot, pulled on warm boot |
| Guacamole | Standalone service `m2o-guacamole` → `g2.machinemachine.ai` |
| Fleet control | Streamlit → `fleet.machinemachine.ai` (planned) |
| **m2o-autoheal** | **Supervisord service (priority 35) — checks gateway config every 15 min, backs up + repairs if broken. Source: `m2-desktop/scripts/m2o-autoheal.sh`** |
| Reference machine | m2 — do not touch until all agents on new arch |

**Cold vs warm start:**
- **Warm** (restart): `claude update` + `git pull` skills + relink openclaw + start services
- **Cold** (new agent): full bootstrap — clone OpenClaw, install skills, write configs, register in Guacamole

**Prime directive:** m2 is untouched until Phase 7 (all agents stable first).

> Full spec + migration plan: `sections/architecture.md`

---

## Appendix: Key URLs & IDs

| Resource | URL / ID |
|----------|----------|
| Planka | kanban.machinemachine.ai |
| Coolify | cool.machinemachine.ai |
| Guacamole | g2.machinemachine.ai (m2o-guacamole standalone) |
| Fleet control | fleet.machinemachine.ai (planned) |
| BGE proxy | bge-proxy.machinemachine.ai |
| Pitch deck | pitch.machinemachine.ai |
| MM website | machinemachine.ai |
| meditation.dk | meditation.machinemachine.ai |
| Machine.Machine Planka project | 1708841079463216163 |
| Master Roadmap board | 1713898007587456163 |
| Client Projects board | 1713898018308097207 |
| Dark Factory board | 1713898009978209447 |

---

*Last updated: 2026-02-21 | Maintainer: m2 | Propose changes: machine-machine/fleet-playbook*
