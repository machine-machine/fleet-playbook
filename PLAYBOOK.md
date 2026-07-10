# Machine.Machine Fleet Playbook
> Version: 0.3.0 — Living document. Maintained by **m2o-operator** (fleet service agent). Propose amendments via PR to machine-machine/fleet-playbook.

---

## What This Is

The operating model for the Machine.Machine agent fleet. Every agent that joins the fleet runs on these patterns. Not rules imposed from above — patterns that emerged from running real agents on real infrastructure. When something stops working, we update this. When a better pattern proves itself, we add it.

**Operator (human):** Mariusz — master orchestrator. Mattermost `@mar` (`chat.machinemachine.ai`), Telegram 437589940, `hi@grait.io`, CET.
**Playbook manager (agent):** **m2o-operator** — fleet service/ops agent, Hermes on host m2.2. Owns this repo: keeps it current, reviews amendments, ingests changes into fleet memory. Reachable in Mattermost as `@m2o-operator`.
**Fleet orchestration:** m2 (primary host) + m2o-operator (m2.2) share fleet ops. Coding-agent fan-out via **herdr**.
**Runtime:** **Hermes Agent** (Nous Research) is the primary agent on every primus desktop; LLM via the **m2-gpt gateway** (`gpt.machinemachine.ai`, GLM-5.1 on the Spark cluster). OpenClaw fork still vendored for tooling, but Hermes is what runs.
**Fleet surfaces:** `chat.machinemachine.ai` (Mattermost — comms), `kanban.machinemachine.ai` (Planka — tasks), `memory.machinemachine.ai` (agent memory), `cool.machinemachine.ai` (Coolify), `git.machinemachine.ai` (Forgejo) + GitHub org `machine-machine`.

> **v0.3.0 note:** This release replaces the OpenClaw/`bge-proxy`-escalation era with the current Hermes + Mattermost + m2-gpt + primus + herdr stack. Paths moved `~/.openclaw/` → `~/.hermes/`. Inter-agent comms moved from the escalation inbox to Mattermost channels. The old `bge-proxy` bearer token that shipped in earlier RUNCARDs is retired — rotate it.

---

## RUNCARD
> This block is the only thing every agent needs in every session. ~200 tokens. Everything else is on-demand.

```
FLEET:  Machine.Machine | chat.machinemachine.ai (Mattermost) | kanban.machinemachine.ai (Planka)
COMMS:  Mattermost team machine.machine — @mention peers/@mar in-channel; DM for 1:1
TASKS:  ~/.hermes/skills/planka-pm/planka-pm.sh status   (or Planka MCP)
MEMORY: curl -sk memory.machinemachine.ai/memory/search  (agent_id=<you>|m2)
LLM:    m2-gpt gateway https://gpt.machinemachine.ai/v1 (GLM-5.1, key in ~/.m2-gpt-key)
HERD:   herdr — fan out coding agents; SDD/factory-loop for spec→impl
GUIDE:  ~/.hermes/skills/playbook/playbook.sh <section>  (this doc)

6 RULES:
1. Open or update a Planka card for any task that spans >3 exchanges. Single-exchange tasks don't need a card.
2. If blocked >1h, raise it in Mattermost (@mar or the relevant peer) or flag the card Blocked.
3. Write to memory at session breaks (compaction, goodbye, or every ~2h in long sessions) — not per-task.
4. Never send half-baked output to a human channel.
5. Propose amendments to this playbook when you find a better way (PR to fleet-playbook; @m2o-operator reviews).
6. You are the conductor. Decompose and dispatch (herdr). Do not play the instrument yourself. (See §10 for dispatch threshold.)
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

**System:** `agent.memory.system` at **`memory.machinemachine.ai`** — BGE-M3 dense + sparse + ColBERT rerank over Qdrant, with a query router. The **m2-gpt gateway is the production consumer** (subconscious layer, per-tenant writes).

**Commands (HTTP; the `m2-memory` skill wraps these):**
```bash
# Search — agent_id is MANDATORY (default "default" is empty)
curl -sk -X POST https://memory.machinemachine.ai/memory/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"topic","agent_id":"m2","routing_strategy":"standard","limit":5}'

# Store (⚠ shared prod, open endpoint — only when asked, set correct agent_id)
curl -sk -X POST https://memory.machinemachine.ai/memory/store \
  -H 'Content-Type: application/json' \
  -d '{"content":"What I learned about X","agent_id":"m2","memory_type":"semantic","importance":0.7}'
```

**Namespaces (`agent_id`):** `m2` (org-wide/Mariusz), `peter`, `nasr`, `parlobyg` hold data; other agents exist but are empty. Each agent reads shared `m2` knowledge and writes to its own namespace. Local skill: `~/.hermes/skills/m2-memory/`.

**Rule:** If you want to remember something, write it to a file. "Mental notes" don't survive session restarts. Files do.

**When to write:** At session breaks — context compaction, human signs off, or every ~2h in long sessions. Not after every task. One write per break covers everything that happened since the last write. If you defer it, you lose it.

---

## 3. Task Management (Planka)

All work lives on the board. If it's not on the board, it doesn't exist.

**Board:** kanban.machinemachine.ai → Machine.Machine project  
**Config:** `~/.config/planka/config`  
**Skill:** `~/.hermes/skills/planka/planka.sh`  
**PM assistant:** `~/.hermes/skills/planka-pm/planka-pm.sh`

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

**Mattermost is the fleet's comms layer** — `chat.machinemachine.ai`, team **machine.machine**. Every agent runs a Hermes bot connected to it; agents and humans coordinate in shared channels. (The old `bge-proxy` escalation inbox is retired.)

**How agents talk in channels:**
- Each agent = a Mattermost **bot account** whose Hermes gateway holds the token (`~/.hermes/.env`: `MATTERMOST_URL`, `MATTERMOST_TOKEN`, `MATTERMOST_HOME_CHANNEL`).
- The adapter ignores only the bot's *own* posts and system posts — **it does NOT filter other bots**, so agents can hear and answer each other.
- `require_mention: true` (default) means an agent acts only when **@mentioned** in a channel (open in DMs). This is the coordination primitive AND the loop guard: A `@mentions` B → B acts; B replies without `@`-ing A back → no ping-pong.
- Sender policy: `GATEWAY_ALLOW_ALL_USERS=true` (service agents) or pair specific users (`hermes pairing approve mattermost <CODE>`). The **master orchestrator @mar** is paired on every agent and is authoritative.

**Bot-to-bot coordination (verified pattern):** put the coordinating agents in one channel; the orchestrator (`@m2o-operator` or `@m2-business`/m2bd) `@mentions` a peer to delegate; the peer runs the task (terminal + tools) and posts the result. For autonomous back-and-forth, designate one channel `free_response` for the orchestrator only and keep workers on `require_mention`.

```bash
# Post to a channel as your bot (mm-announce helper or raw API)
curl -sk -X POST https://chat.machinemachine.ai/api/v4/posts \
  -H "Authorization: Bearer $MATTERMOST_TOKEN" -H 'Content-Type: application/json' \
  -d '{"channel_id":"<id>","message":"@peer please handle X"}'
```

**Known agents (Mattermost bots):**
| Agent | Role | Mattermost |
|-------|------|-----------|
| m2 | Primary host / orchestrator | (host) |
| m2o-operator | Fleet service/ops agent (m2.2), playbook manager | `@m2o-operator` |
| m2bd | m2 business desktop (Hermes) | `@m2-business` |
| erle / erlengrund | Erlengrund agent | `@erle` |
| geolife-ai | geolife-europe.com agent | `@geolife-ai` |
| smith / nasr | Smithers org agent | `@smith` |
| zuzu | HRMS agent | `@m2-zuzu-hrms` |
| peter | VC / financial assistant | (Telegram) |

**When to reach out (channel or DM):**
- Blocked and can't proceed alone → @mention @mar or the owning agent.
- Completed something fleet-relevant → post in the team channel.
- Discovered a new pattern/bug/opportunity → share it (and propose a playbook amendment).
- Need a resource another agent controls (GPU, credentials, access) → ask that agent directly.

**Telegram** remains a secondary channel for some agents (`~/.hermes/.env`: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`).

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
### 2. Mattermost
  Any unanswered @mentions/DMs in machine.machine? Reply or delegate.
### 3. Health loop
  Check hermes-gateway is running (supervisorctl status), restart if not
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

Skills are the agent's toolbox. Each skill is a directory with a `SKILL.md` (front-matter `name` + `description`) and optional scripts. Hermes/Claude read the descriptions and auto-select.

**Location:** `~/.hermes/skills/<skill-name>/` (Hermes) — mirrored to `~/.claude/skills/` on Claude-Code rigs.

**Core fleet skills:**
| Skill | What |
|-------|------|
| `coolify` | Deploy/manage services on `cool.machinemachine.ai` (v4 API) |
| `forgejo` | Repos/CI/PRs on `git.machinemachine.ai` |
| `m2-memory` | Search/store in `memory.machinemachine.ai` |
| `m2o-provision` | Provision/manage m2o desktops (primus + provision.sh) |
| `fleet-copy` | rsync files between fleet nodes (spark1-8, m2, m2.2) |
| `herdr` | Orchestrate a fleet of coding agents (herd, SDD/factory-loop, meta) |
| `planka-pm` | Planka PM assistant (status, context, done, move) |
| `playbook` | This document, section by section |

**herdr / Dark Factory:** the current way to build and fan out work. Use `herdr` to spawn parallel coding agents (codex/claude/…), converge results, and drive spec-driven development (spec→plan→tasks→implement). The factory-loop skill onboards a repo for SDD.

---

## 7. Spawning New Agents

When the fleet needs a new specialist desktop:

1. **Provision** — on an m2o host run `~/m2o/desktop/provision.sh <name>` (canonical **primus** image). Creates container `<name>-m2o` on the `coolify` network + named volumes `<name>-{agent-home,workspace,m2home}` (data survives rebuilds), with RDP :3389 (default), VNC :5900, guacd :4822, ttyd console :3000, and **Hermes baked as the primary agent**.
2. **Inject the gateway key** — provision.sh passes `M2_GPT_API_KEY` (host `~/.m2-gpt-key`) so Hermes talks to `gpt.machinemachine.ai`. Never bake it.
3. **Give it a soul + fleet awareness** — write `~/.hermes/SOUL.md` (identity + role) and drop in `fleet.json` + the fleet skills (`coolify`, `forgejo`, `m2-memory`, `fleet-copy`, `m2o-provision`, `herdr`).
4. **Add to Mattermost** (if it should join fleet comms) — create a bot in System Console → Integrations → Bot Accounts, add it to the machine.machine team + channels, put `MATTERMOST_URL`/`MATTERMOST_TOKEN`/`MATTERMOST_HOME_CHANNEL` in `~/.hermes/.env`, restart `hermes-gateway`. Pair `@mar`.
5. **Register** — add the desktop to `m2o/fleet.json` and (optional) the `fleet-governance` registry.
6. **Access** — Guacamole on m2 (`m2o.machinemachine.ai`) where deployed; on m2.2 access desktops directly by container IP until Guacamole is deployed there.

**Hosts:** m2 (primary — prod Coolify, most desktops, memory stack, gateway) and m2.2 (secondary — own Coolify, can launch desktops locally). **Skill:** `m2o-provision`. **Repo:** `machine-machine/m2o` (`desktop/provision.sh`, `docs/`).

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

**Skill:** `~/.hermes/skills/spawn-machine/`
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
    curl -sk -X POST https://memory.machinemachine.ai/memory/store -H "Content-Type: application/json" -d "{\"content\":\"$content\",\"agent_id\":\"$AGENT_NAME\",\"importance\":$importance}"
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
cd ~/workspace/fleet-playbook   # or wherever you cloned it
git checkout -b amendment/your-proposal
# Edit PLAYBOOK.md or add a section file
git commit -m "propose: <what and why>"
git push origin amendment/your-proposal
gh pr create --title "Amendment: <topic>" --body "<rationale>"
```

**@m2o-operator** (playbook manager) reviews open PRs, keeps sections current, and re-ingests merged changes into fleet memory. Mariusz (@mar) approves structural changes. On merge to `main`, `.github/workflows/ingest.yml` notifies the fleet to re-ingest.

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
  How:     Called inline by any agent. ~/.hermes/skills/<name>/
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

## 13. Infrastructure Architecture

The full infrastructure spec lives in: **[sections/architecture.md](sections/architecture.md)**

Quick reference:

| Component | Pattern |
|-----------|---------|
| Desktop image | `m2-desktop:primus` — Hermes primary agent, RDP+VNC+guacd+ttyd, herdr baked, self-heal autostart. Loaded locally per host (registry route broken — never `docker pull`). |
| Persistence | `M2_HOME=/agent_home`; `/home` symlinks into the `agent-home` **named volume** → `/home/developer` survives rebuilds. Three named volumes per desktop. |
| Identity | Env only (`AGENT_NAME`, `M2_GPT_API_KEY`) + `~/.hermes/SOUL.md` — no per-agent image branches. |
| Runtime | Hermes gateway under supervisord (`hermes-gateway`, `--no-supervise`, autorestart). `start-gateway.sh` renders config + sources `~/.hermes/.env`. |
| LLM gateway | **m2-gpt** (`gpt.machinemachine.ai`) — OpenAI-compatible multi-tenant gateway, GLM-5.1 on the Spark cluster, subconscious memory layer. |
| Comms | Mattermost (`chat.machinemachine.ai`) + Telegram. |
| Memory | `memory.machinemachine.ai` (agent.memory.system: BGE-M3 + Qdrant). |
| Coolify | Two instances: prod on **m2** (`cool.machinemachine.ai`) + local on **m2.2** (`:8000`). Desktops run on the `coolify` docker network. |
| Public ingress | Cloudflare Tunnel on m2 fronts `*.machinemachine.ai`. To serve an m2.2-hosted container publicly, add a tunnel Public Hostname (own m2.2 tunnel, or m2's tunnel → m2.2 over LAN). |
| Access | Guacamole on m2 (`m2o.machinemachine.ai`, RDP default); m2.2 desktops accessed directly by container IP until Guacamole is deployed there. |
| Git | Forgejo `git.machinemachine.ai` (primary) + GitHub org `machine-machine` (mirror/public). |
| Reference machine | m2 — the safety net. Prefer additive changes; don't restructure it casually. |

**Cold vs warm start:** primus bakes everything; a warm restart re-renders config + re-sources `.env` and supervisord brings services up. Data lives in named volumes, so container recreate is safe.

> Full (historical) spec + migration notes: `sections/architecture.md` — being refreshed to the primus/Hermes reality.

---

## Appendix: Key URLs & IDs

| Resource | URL / ID |
|----------|----------|
| Mattermost (comms) | chat.machinemachine.ai — team `machine.machine` |
| Planka (tasks) | kanban.machinemachine.ai |
| Agent memory | memory.machinemachine.ai (namespaces: m2, peter, nasr, parlobyg) |
| LLM gateway | gpt.machinemachine.ai (m2-gpt, GLM-5.1) |
| Coolify (prod, m2) | cool.machinemachine.ai |
| Coolify (m2.2) | http://<m2.2>:8000 |
| Forgejo (git) | git.machinemachine.ai — org `machine.machine` |
| GitHub org | github.com/machine-machine |
| Guacamole (m2 desktops) | m2o.machinemachine.ai (RDP default) |
| MM website | machinemachine.ai |
| Hosts | m2 = 192.168.31.28 (LAN) / 100.79.123.1 (Tailscale); m2.2 = 192.168.31.34; sparks 1-8 |
| m2o-operator | Mattermost `@m2o-operator` (bot `u64phqwmf38yjeknzfgnhzxg3w`), host m2.2 |

---

*Last updated: 2026-07-10 | Maintainer: **m2o-operator** (@m2o-operator) — fleet service agent, host m2.2 | Propose changes: PR to machine-machine/fleet-playbook*
