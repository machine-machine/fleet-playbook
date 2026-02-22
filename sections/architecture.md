# Machine.Machine OS — Architecture Spec v1.3
*Self-audit based on m2 (reference instance) + fleet analysis — 2026-02-21*
*Updated 2026-02-21: Added §3.11 m2o-autoheal self-healing gateway monitor*
*Updated 2026-02-22: Added §7 The Rhythm — Human-in-the-Loop Operating Model*
*Lives in: machine-machine/fleet-playbook @ sections/architecture.md*

---

## ⚠️ Prime Directive: Don't Touch m2

m2 is the reference machine. Months of accumulated work, skills, memory, crons, custom OpenClaw fork, TTS pipeline — all running. **Do not redeploy, restructure, or migrate m2** until every agent is on the new architecture and proven stable. m2 is the safety net.

All architecture work targets the `base` branch for new/other agents only.

---

## 1. Ground Truth: How m2 Actually Works

### Persistence — the elegant pattern

```
Docker named volume: m2_home → /m2_home
Docker named volume: m2_workspace → /workspace (legacy, barely used)

entrypoint.sh on EVERY boot:
  if /m2_home/home doesn't exist:
    cp -a /home/. /m2_home/home/    ← first boot: snapshot image /home into volume
  rm -rf /home
  ln -sf /m2_home/home /home        ← /home becomes the volume forever
```

**Result:** All of `/home/developer` is durable. Skills, config, memory, Claude versions, git repos — everything survives container rebuilds.

### Why agents lost data

The same `entrypoint.sh` defaults to `M2_HOME=/m2_home`.  
Agents set `CLAWDBOT_HOME=/clawdbot_home` but NOT `M2_HOME`.  
Volume was mounted at `/clawdbot_home` — entrypoint symlinked `/home` to `/m2_home/home` (a path inside the ephemeral layer).  
**Every restart = cold start.** One missing env var.

**Fix:** `M2_HOME=/agent_home` + volume mounted at `/agent_home`.

### Guacamole server — the actual topology

```
Coolify deployments:
  clawdbot-desktop:guacamole  ← OLD deployment
  ├── clawdbot-desktop-worker  (exited — irrelevant)
  ├── guacamole-db             ✅ RUNNING — MariaDB on coolify network
  └── guacamole-full           ✅ RUNNING — Central Guacamole for fleet

  m2-desktop:main
  └── m2-desktop-worker        ✅ m2's desktop, connects to guacamole-full above
```

The Guacamole server has been surviving on the corpse of the old guacamole branch deployment. It needs its own permanent home.

---

## 2. Self-Audit: m2's Gaps

| Problem | Severity |
|---------|----------|
| 17/21 skills have no git tracking | 🔴 HIGH |
| 3 skill repos dirty (planka, spawn-machine, x-monitor) | 🟡 MED |
| Skills can't be auto-updated (no git pull) | 🔴 HIGH |
| `/workspace` volume misaligned (real workspace is in m2_home) | 🟡 LOW |
| openclaw.json not git-backed | 🟡 MED (secrets — env vars are source of truth) |

These will be resolved for new agents via the `base` branch. m2 will be migrated last.

---

## 3. Target Architecture

### Layer stack

```
┌──────────────────────────────────────────────────────────┐
│  FLEET CONTROL   fleet.machinemachine.ai  (Streamlit)   │
├──────────────────────────────────────────────────────────┤
│  GUACAMOLE       g2.machinemachine.ai    (standalone)   │
├──────────────────────────────────────────────────────────┤
│  IDENTITY        env vars only (AGENT_NAME, keys)       │
├──────────────────────────────────────────────────────────┤
│  RUNTIME         Claude CLI + OpenClaw m2-custom fork   │
├──────────────────────────────────────────────────────────┤
│  SKILL LAYER     all skills = git repos, pull on start  │
├──────────────────────────────────────────────────────────┤
│  CONFIG LAYER    written from env vars on cold boot     │
├──────────────────────────────────────────────────────────┤
│  PERSISTENCE     /opt/m2o/{name}/home → /agent_home     │
│                  bind mount on Coolify host              │
├──────────────────────────────────────────────────────────┤
│  BASE IMAGE      machine-machine/m2-desktop:base        │
│                  one branch, all agents same image      │
└──────────────────────────────────────────────────────────┘
```

---

### 3.1 Persistence Layer

**Host bind mounts** — transparent, backup-friendly, no Docker volume opacity.

```
Coolify host:
/opt/m2o/
├── peter/home/     → /agent_home (peter container)
├── miauczek/home/  → /agent_home (miauczek container)
├── pittbull/home/  → /agent_home (pittbull container)
└── [future agents]
```

**docker-compose.agent.yml (same for all):**
```yaml
environment:
  M2_HOME: /agent_home          # ← the one env var that makes persistence work
  AGENT_NAME: ${AGENT_NAME}

volumes:
  - /opt/m2o/${AGENT_NAME}/home:/agent_home
```

**Coolify `pre_deployment_command`:**
```bash
mkdir -p /opt/m2o/${AGENT_NAME}/home && chown -R 1000:1000 /opt/m2o/${AGENT_NAME}/home
```

**entrypoint.sh** (unchanged from m2 — just needs M2_HOME set):
```bash
PERSISTENT_HOME="${M2_HOME}/home"       # = /agent_home/home
# first boot:  cp -a /home/. /agent_home/home/
# every boot:  rm -rf /home && ln -sf /agent_home/home /home
```

---

### 3.2 Identity Layer

One compose, identity = env vars only:

```yaml
# Required
AGENT_NAME: peter              # drives paths, aliases, memory namespace
ANTHROPIC_API_KEY: sk-ant-...  # Claude access
AGENT_TELEGRAM_BOT_TOKEN: ...  # Telegram channel

# Memory
COLLECTION_NAME: agent_memory_${AGENT_NAME}
QDRANT_URL: http://memory-qdrant:6333

# Comms (set via Coolify shared env group)
BGE_PROXY_TOKEN: ...
PLANKA_URL: https://kanban.machinemachine.ai
PLANKA_TOKEN: ...
COOLIFY_TOKEN: ...

# TTS/STT
AGENT_TTS_BASE_URL: http://speech_gateway/v1
AGENT_STT_BASE_URL: http://speaches-.../v1

# OpenClaw fork
AGENT_OPENCLAW_REPO: https://github.com/machine-machine/openclaw.git
AGENT_OPENCLAW_BRANCH: m2-custom

# Skills to install on cold boot (all agents, non-negotiable defaults)
AGENT_SKILLS: m2-memory,rlm-memory,bmad-elicit,planka,planka-pm,playbook,xfce-desktop,stt
```

---

### 3.3 Runtime Layer — Two-Tier Docker Image

**"Minutes onboarding" requires pre-baking slow steps into the image — not running them at container start.**

```
Tier 1: base image  (machine-machine/m2-desktop:base)
  Ubuntu + XFCE + VNC + guacd + system deps
  Claude CLI (curl install at build time)
  Rebuilt: rarely (major system changes only)

Tier 2: agent image  (machine-machine/m2-desktop:agent-latest)
  FROM base
  + OpenClaw:m2-custom cloned + npm ci (done at build time)
  + All skill repos pre-cloned
  Rebuilt: weekly via GitHub Actions CI
```

All agents pull `agent-latest`. Cold boot = `git pull` (seconds) not `git clone + npm ci` (15 min).

**Staged base always warm in Coolify:** A permanent `base-staging` app keeps image layers cached. Real agent deploys pull from cache — not a fresh build.

**Claude CLI pre-installed at image build time:**
```dockerfile
RUN curl -fsSL https://claude.ai/install.sh | sh
```

**On warm restart** — non-blocking background update:
```bash
claude update --skip-permissions 2>/dev/null &
```

---

### 3.4 Bootstrap Layer

**Critical path principle:** The only thing on the blocking path to "Telegram-reachable" is: config write → VNC start → gateway start. Everything else is background.

```bash
startup.sh
│
├── Phase 1 (ALWAYS): persistent home setup
│     entrypoint symlink pattern (M2_HOME/home → /home)
│
├── Phase 2: warm or cold?
│     if ~/.openclaw/openclaw.json exists → WARM
│     else → COLD
│
├── WARM START (fast path, ~60s):
│     claude update --skip-permissions &        ← background
│     git pull --ff-only skills/* &             ← background, parallel
│     git pull openclaw:m2-custom --ff-only &   ← background
│     relink openclaw fork symlink
│     start VNC + guacd + OpenClaw gateway      ← only blocking steps
│
└── COLD START (new agent, target <5 min):
      # BLOCKING (sequential, critical path):
      1.  validate_env_vars() — missing required → escalate to m2 + exit
      2.  git pull --ff-only on pre-cloned OpenClaw (image has it already)
      3.  ln -sfn ~/.openclaw/platform/openclaw /usr/lib/node_modules/openclaw
      4.  generate-openclaw-config.js  (from env vars → openclaw.json)
      5.  write_config_files()  (planka, coolify, bge-proxy, cerebras)
      6.  Write identity files (SOUL.md, AGENTS.md, USER.md from template)
      7.  Start VNC + guacd + OpenClaw gateway
      8.  Notify master: "⚡ {AGENT_NAME} is online. Guacamole: g2.machinemachine.ai
                          Connection: {AGENT_NAME}. Seeding memories in background."

      # BACKGROUND (non-blocking, parallel after gateway starts):
      9.  git pull --ff-only skills/* &
      10. ingest_bootstrap_memories.py &   ← doesn't block Telegram
      11. clone fleet-playbook if missing &
```

---

### 3.5 Skill Layer

**Rule: every skill = a git repo under `machine-machine/openclaw-{skill}-skill`.**

```
Status:
  ✅ ALL fleet skills now git-tracked (2026-02-21):
     openclaw-m2-memory-skill, openclaw-rlm-memory-skill, openclaw-spawn-machine-skill
     openclaw-bmad-elicit-skill, planka, x-monitor  (legacy naming)
     m2o-skill-planka-pm, m2o-skill-playbook, m2o-skill-xfce-desktop
     m2o-skill-stt, m2o-skill-coolify, m2o-skill-tts-manager
     m2o-skill-x-scraper, m2o-skill-browser-persistence, m2o-skill-twenty
  🚫 m2-only (not fleet): homeassistant, video-ad-creator, kiedis-po, qwen-tts
```

**Warm restart skill refresh:**
```bash
for skill_dir in ~/.openclaw/skills/*/; do
  [ -d "$skill_dir/.git" ] && git -C "$skill_dir" pull --ff-only --quiet 2>/dev/null &
done
```

**m2 skill migration (don't touch now):**  
On next m2 maintenance window: push each manual skill to its own GitHub repo, then convert to git clone. Until then, m2's skills are safe inside `m2_home` volume.

---

### 3.6 Config Layer

Credential config files are **generated from env vars on cold boot**. Never written manually.

```bash
write_config_files() {
  # Planka
  install -m 600 /dev/null ~/.config/planka/config
  printf "PLANKA_URL=%s\nPLANKA_TOKEN=%s\n" "$PLANKA_URL" "$PLANKA_TOKEN" \
    > ~/.config/planka/config

  # Coolify
  install -m 600 /dev/null ~/.config/coolify/config
  printf "COOLIFY_API_URL=%s\nCOOLIFY_TOKEN=%s\n" "$COOLIFY_API_URL" "$COOLIFY_TOKEN" \
    > ~/.config/coolify/config

  # BGE proxy
  printf "BGE_URL=http://bge-proxy.machinemachine.ai\nBGE_TOKEN=%s\n" "$BGE_PROXY_TOKEN" \
    > ~/.config/bge-proxy/config

  # Cerebras
  install -m 600 /dev/null ~/.config/cerebras/config
  printf "CEREBRAS_API_KEY=%s\n" "$CEREBRAS_API_KEY" > ~/.config/cerebras/config
}
```

---

### 3.7 Backup Layer

**Track A — workspace git push (daily cron on every agent):**
```bash
# Already on m2 as m2-daily-backup
# Bootstrap sets up same cron on new agents
cd ~/.openclaw/workspace && git add memory/ MEMORY.md && git commit -m "daily backup" && git push
```

**Track B — host bind mount rsync (Coolify host level):**
```bash
rsync -a /opt/m2o/ /backup/m2o/ \
  --exclude='*/.cache/' \
  --exclude='*/node_modules/' \
  --exclude='*/.local/share/flatpak/'
```

---

### 3.8 Guacamole — Standalone Service

**Repo:** `machine-machine/m2o-guacamole`  
**URL:** `g2.machinemachine.ai`  
**Principle:** The Guacamole server is fleet infrastructure, not tied to any agent.

```yaml
# docker-compose.yml
services:
  guacamole-db:
    image: mariadb:10.11
    container_name: guacamole-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${GUAC_DB_ROOT_PASSWORD}
      MYSQL_DATABASE: guacamole_db
      MYSQL_USER: guacamole_user
      MYSQL_PASSWORD: ${GUAC_DB_PASSWORD}
    volumes:
      - guacamole_db:/var/lib/mysql
      - ./config/guacamole/initdb.sql:/docker-entrypoint-initdb.d/initdb.sql:ro
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s; timeout: 5s; retries: 5; start_period: 30s

  guacamole-full:
    image: guacamole/guacamole:1.5.5
    container_name: guacamole-full
    restart: unless-stopped
    depends_on:
      guacamole-db:
        condition: service_healthy
    # NOTE: No depends_on desktop-worker — server is standalone
    environment:
      GUACD_HOSTNAME: ${GUACD_HOSTNAME:-m2-desktop-worker}  # configurable
      GUACD_PORT: 4822
      MYSQL_HOSTNAME: guacamole-db
      MYSQL_DATABASE: guacamole_db
      MYSQL_USER: guacamole_user
      MYSQL_PASSWORD: ${GUAC_DB_PASSWORD}
    networks:
      coolify:
        external: true
    labels:
      - traefik.http.routers.guacamole-full.rule=Host(`g2.machinemachine.ai`)

volumes:
  guacamole_db:
networks:
  coolify:
    external: true
```

**Each agent registers its VNC on cold boot** via `register-guacamole.sh`.  
`GUACD_HOSTNAME` env var points to whichever agent is the primary guacd source (currently m2).

---

### 3.9 Fleet Control Streamlit

**Repo:** `machine-machine/m2o-fleet`  
**URL:** `fleet.machinemachine.ai`

```
Panel 1 — Fleet Status
  Agent cards: name, Coolify status, last active, compliance %, Guacamole link

Panel 2 — Memory
  Qdrant collection sizes + last write per agent + cross-agent search

Panel 3 — Escalations
  Pending/resolved via BGE proxy API, reply from UI

Panel 4 — Planka
  Master Roadmap Now/Next/Done summary

Panel 5 — Actions
  Spawn agent form, restart agent, broadcast escalation, rolling update

Panel 6 — Logs
  Coolify deployment logs, 100 lines per agent
```

---

### 3.10 Spawn Flow — "Minutes Onboarding"

**Goal:** Master provides 2 things (agent name + Telegram token). Everything else is automated.

```bash
# Single command:
spawn-machine.sh <name> <telegram_bot_token>

spawn_agent() {
  NAME=$1; TOKEN=$2

  # 1. Validate: check name not already in registry
  grep -q "^  $NAME:" ~/.openclaw/workspace/platform/incubator/registry.yaml && exit 1

  # 2. Pre-register Guacamole connection (no need to wait for agent to do it)
  register-guacamole.sh pre-register "$NAME" "${NAME}-desktop"

  # 3. Create Coolify app from machine-machine/m2-desktop:agent-latest
  UUID=$(coolify.sh create-compose-app \
    --name "${NAME}-desktop" \
    --repo machine-machine/m2-desktop \
    --branch agent-latest \
    --attach-env-group m2o-shared)   # ← gets Qdrant, BGE, TTS, Planka, Coolify creds

  # 4. Set the 2 agent-specific env vars (everything else from shared group)
  coolify.sh env-set $UUID AGENT_NAME "$NAME"
  coolify.sh env-set $UUID AGENT_TELEGRAM_BOT_TOKEN "$TOKEN"
  # ANTHROPIC_API_KEY comes from shared group (all agents use same key)

  # 5. Set pre_deployment_command (host bind mount setup)
  coolify.sh set $UUID pre_deployment_command \
    "mkdir -p /opt/m2o/$NAME/home && chown -R 1000:1000 /opt/m2o/$NAME/home"

  # 6. Deploy → cold bootstrap runs → agent notifies master when live
  coolify.sh deploy $UUID

  # 7. Add to registry
  add_to_registry "$NAME" "$UUID"

  echo "Deploying $NAME. Agent will notify you on Telegram when ready (~5 min)."
}
```

**Master's total input:**
```
Name:           peter
Telegram token: 7890123456:AAH...
```
That's it. No SSH, no Guacamole UI, no env var hunting.

**Timeline after `spawn-machine.sh peter <token>`:**
```
T+0:00  spawn-machine.sh runs (Coolify app created + deploy triggered)
T+0:30  Coolify pulls agent-latest image (cached layers — fast)
T+1:00  Container starts, entrypoint runs (first boot: copy /home to volume)
T+2:00  Configs written, OpenClaw gateway starts
T+3:00  "⚡ peter is online" Telegram message to master
T+5:00  Background: memories seeded, skills updated, fleet-playbook pulled
```

---

### 3.11 m2o-autoheal — Self-Healing Gateway Monitor

**Every agent container runs `m2o-autoheal` as a supervisord service (priority 35, runs before the gateway).**

It wakes every 15 minutes, checks gateway config health, and self-repairs — no human intervention needed for the most common failure mode (invalid `openclaw.json`).

**What it monitors:**
- `openclaw.json` for invalid/rejected keys (e.g. stale `meta` block from config generator)
- Gateway process alive (via `pgrep`)
- Crash-loop indicator (repeated `exit status 1` in gateway log)

**Repair flow:**
```
1. Detect broken config (python3 JSON parse + key check)
2. Backup: ~/.openclaw/backups/openclaw.json.backup.YYYYMMDD-HHMMSS
3. Repair: openclaw doctor --fix  (fallback: manual JSON strip)
4. Log outcome to /var/log/m2o-autoheal.log
5. Gateway auto-restarts via supervisord (autorestart=true)
```

**Backup retention:** Last 20 dated backups kept, older ones pruned automatically.

**Source:** `machine-machine/m2-desktop:base` → `scripts/m2o-autoheal.sh`  
**Baked into image at:** `/usr/local/bin/m2o-autoheal.sh`  
**Supervisord entry:**
```ini
[program:m2o-autoheal]
command=/bin/bash /usr/local/bin/m2o-autoheal.sh
user=root
autorestart=true
priority=35          # starts before clawdbot-gateway (priority=40)
startsecs=5
stdout_logfile=/var/log/m2o-autoheal.log
stderr_logfile=/var/log/m2o-autoheal.log
```

**Tunable via env var:** `M2O_AUTOHEAL_INTERVAL` (default: 900 seconds / 15 min)

**Why this matters:** The config generator was adding invalid `meta` keys on every `AGENT_CONFIG_GENERATE=true` restart. Without autoheal, this caused a permanent gateway crash loop that required manual exec into the container to fix. With autoheal, the next check cycle detects and fixes it automatically.

---

## 4. Migration Plan

| Phase | What | Touches m2? | Est. |
|-------|------|-------------|------|
| 0 | Fix agents: add `M2_HOME=/agent_home` + volume at `/agent_home` | ❌ | 30 min |
| 1 | Extract `m2o-guacamole` standalone repo + Coolify deploy | ❌ | ✅ Done |
| 2 | `base` branch: Dockerfile + two-tier image + cold/warm bootstrap | ❌ | 2 days |
| 3 | GitHub Actions CI: weekly rebuild of `agent-latest` image | ❌ | in phase 2 |
| 4 | `spawn-machine.sh` single command (Coolify + registry + Guacamole) | ❌ | in phase 2 |
| 5 | Push 11 missing skill repos to GitHub | m2 skills only | 3 days |
| 6 | Fleet control Streamlit `m2o-fleet` | ❌ | 1 week |
| 7 | Host bind mounts `/opt/m2o/` (needs Coolify host SSH) | ❌ | coordinate |
| 8 | Migrate m2 to new architecture | ✅ last | when stable |

---

## 4b. Client Self-Onboarding Flow

**Goal:** A stranger on the internet gets their own AI agent in under 10 minutes, zero technical knowledge required.

```
machinemachine.ai → "Get Your Agent"
        ↓
t.me/mm_onboarding_bot?start=onboard
        ↓
Telegram Mini App:
  Step 1: Email → OTP via Brevo → verify → Twenty CRM contact created
  Step 2: BotFather tutorial (embedded 30s screen recording)
           "Go to @BotFather → /newbot → follow steps → forward the confirmation here"
  Step 3: Forward BotFather confirmation → parse token + bot username
           Fallback: manual token input field
           Validate: api.telegram.org/bot{token}/getMe → confirms ownership
  Step 4: Choose agent name (display name)
  Step 5: Confirm screen → "Setting up your agent..."
        ↓
Backend (machinemachine-api):
  CRM state: email_verified → token_validated → name_chosen → provisioning
  Trigger: spawn-machine.sh {name} {token}  (or queue for review)
        ↓
Client receives:
  - Message on their new bot: "⚡ Your agent {name} is live. Say hello!"
  - Email via Brevo: welcome + deeplink to their bot
```

**CRM state machine (Seven CRM states → seven Brevo triggers):**
```
email_pending → email_verified → token_validated → name_chosen
  → provisioning → live → [active | degraded | churned]
```

**Security hardening:**
- Email OTP before BotFather step (proves ownership, blocks fake email abuse)
- Token validated via `getMe` before accepted (no trust in forwarded text alone)
- Rate limiting: 1 agent/email, 3 attempts/Telegram user/day
- Provision gate: CRM status = `pending_review` → m2 approves → spawn (or auto on payment)
- Weekly fleet health: `getMe` check per agent → token revocation detected early
- Web fallback: `onboard.machinemachine.ai` for non-Mini-App Telegram clients

**fleet.machinemachine.ai as Telegram Mini App:**
Fleet control panel accessible as inline Telegram web app. Same Streamlit UI, embedded via Mini App protocol. Spawn, monitor, escalate — without leaving Telegram.

---

## 5. What NOT to Change

- m2's `m2_home` volume, entrypoint, openclaw.json — **untouched until Phase 7**
- BGE proxy escalation API — working
- Qdrant + BGE-M3 memory stack — working
- TTS/STT infrastructure — working
- HEARTBEAT/cron pattern — working
- Daily workspace git push — extend to agents, don't redesign

---

## 6. Open Questions

1. **Coolify host SSH** — needed for `/opt/m2o/` bind mount setup (Phase 0/6)
2. **Telegram tokens** — miauczek, pittbull, peter need bots via @BotFather
3. **Skill repos** — planka-pm, playbook, xfce-desktop — public or private?
4. **`GUACD_HOSTNAME`** — after extracting m2o-guacamole, should guacd run in m2's container or a dedicated container?
5. **Fleet control** — build Streamlit ourselves or adapt an existing dashboard?

---

## 6. Open Questions

~~1. **Coolify host SSH** — resolved: named volumes replace bind mounts~~
2. **Telegram tokens** — miauczek, pittbull, peter still need bots via @BotFather
3. **Skill repos** — planka-pm, playbook, xfce-desktop — public or private?
4. **`GUACD_HOSTNAME`** — guacd should run in its own sidecar, not in any agent container
5. ~~**Fleet control** — resolved: Streamlit, deployed at fleet.machinemachine.ai~~

---

## 7. The Rhythm — Human-in-the-Loop Operating Model

*Added 2026-02-22*

### 7.1 Principle

> Agents run continuously. Humans touch only decisions that are genuinely theirs to make.

The fleet is not a set of reactive chatbots waiting to be told what to do. Each agent has a role, a rhythm, and an autonomy radius. It acts within that radius without asking. It surfaces decisions — never raw problems.

---

### 7.2 Autonomy Radius

Every agent operates within three concentric circles of authority:

```
        ┌─────────────────────────────────────┐
        │  🔴 Master-only  (~weekly)          │  spend money, external comms,
        │                                     │  major product / fleet decisions
        │  ┌─────────────────────────────┐    │
        │  │  🟡 m2-approve  (occasional)│    │  deploy to prod, send to users,
        │  │                             │    │  merge PRs, spawn agents, billing
        │  │  ┌───────────────────────┐  │    │
        │  │  │  🟢 Autonomous        │  │    │  research, write, read, remember,
        │  │  │  (continuous)         │  │    │  run checks, analyze, fix config,
        │  │  │                       │  │    │  update Planka, send memory briefs
        │  │  └───────────────────────┘  │    │
        │  └─────────────────────────────┘    │
        └─────────────────────────────────────┘
```

**Default autonomy by action type:**

| Action | Who decides |
|---|---|
| Read files, search web, analyze, summarize | 🟢 Agent |
| Write to memory, update Planka card, send internal message | 🟢 Agent |
| Run code in sandbox, fix config, restart process | 🟢 Agent |
| Send message to a user's Telegram | 🟡 m2 (routing approval) |
| Deploy to production, merge PR, run migration | 🟡 m2 → master brief |
| Spend credits, send public comms, create external accounts | 🔴 Master |
| Spawn or destroy an agent | 🔴 Master (until billing auto-approve ships) |

Each agent has `AUTONOMY_RADIUS` defined in their `IDENTITY.md`. Anything outside their radius → escalate up (not block and wait).

---

### 7.3 The Brief Loop

The daily human interface. Master reads one message. Makes a small number of decisions. Everything else flows.

**Daily cadence (m2 sends at 07:00 UTC):**

```
☀️ Morning Brief — {DATE}

NEEDS YOU ({n}):
  [✅ Approve] [❌ Skip]  Deploy machinemachine-api v2.1
  [✅ Approve] [❌ Pass]  maya spawn — hi@company.io (researcher, score 85)

HAPPENING:
  peter → TopoDIM blog post 3
  miauczek → processing pitch leads
  m2 → weekly memory consolidation

SHIPPED YESTERDAY:
  • destroy command (spawn-machine.sh)
  • fleet compliance dashboard live

BLOCKED:
  • peter gateway offline → needs ANTHROPIC_API_KEY in Coolify [30s fix]

Fleet: m2 🟢 | peter 🔴 | miauczek 🔴 | pittbull 🔴
```

**Rules:**
- One message per day. Not one per event.
- All decisions have inline buttons. No manual reply required.
- "Blocked" items always include the exact fix, not just the symptom.
- If nothing needs master: brief is skipped. Silence = all clear.

---

### 7.4 Planka Pull Protocol

**The fleet is self-scheduling.** Master's job: keep Planka reflecting priorities. Agents' job: pull and execute.

```
HEARTBEAT cycle for each agent:

1. Check "Now" list → do I have an assigned card?
   YES → continue working it, update comment with progress
   NO  → go to step 2

2. Check "Next 2 Weeks" → top unassigned card matching my preset label
   FOUND  → assign to self, move to Now, begin work
   EMPTY  → flag to m2 ("Now list empty, no matching cards in Next 2 Weeks")

3. Work the card
   → Autonomous actions: just do them
   → Actions outside radius: escalate first, then do after approval

4. On completion:
   → Move card to Done
   → Add 3-line summary comment: what was done / what changed / what's next
   → Pull next card

5. If stuck >1h with no progress:
   → Write comment: what I tried, what I need
   → Move card to Blocked
   → Escalate to m2
```

**Label convention:**

| Label | Assigned to |
|---|---|
| `orchestrator` | m2 |
| `researcher` | researcher-preset agents |
| `builder` | builder-preset agents |
| `creator` | creator-preset agents |
| `generalist` | any agent |
| `master-only` | never auto-assigned — surfaces in brief |

---

### 7.5 The Stuck Protocol

No agent waits passively when blocked. The chain:

```
Agent hits blocker
  ↓ try 2 alternatives (document what you tried)
  ↓ if still stuck after 1h:

Agent → m2 escalation:
  {
    "doing": "deploying machinemachine-api v2.1",
    "tried": ["curl deploy endpoint", "checked Coolify logs — 422 on fqdn field"],
    "need": "someone with Coolify API access to set fqdn manually"
  }

m2 has 4h to resolve:
  → if m2 can fix it autonomously: fixes it, notifies agent
  → if not: surfaces in next morning brief with proposed solution

Master gets one inline button:
  [✅ Approve proposed fix] [❌ Skip] [🔄 Modify]
  (tap takes <30 seconds)

Master decision → m2 routes back → agent continues
```

**What master never sees:** raw errors, full stack traces, "I don't know what to do." Every escalation arrives pre-digested with a proposed path forward.

---

### 7.6 Proactive Behaviors by Role

**m2 (orchestrator):**

| Cadence | Behavior |
|---|---|
| Daily 07:00 UTC | Morning brief to master |
| Every heartbeat | Planka pull + fleet health check |
| Every heartbeat | Spawn queue watch (execute pending spawns) |
| Weekly (Friday) | Priority suggestion: "Here's what I think we should focus on next week" |
| On-demand | Escalation routing (agent → master pre-digested) |

**Specialist agents (peter / fleet agents):**

| Cadence | Behavior |
|---|---|
| Every heartbeat | Planka pull → work active card |
| On completion | Card → Done, summary comment, pull next |
| On stuck (>1h) | Escalate to m2 with context |
| Weekly | Progress report to m2 on assigned cards |

**Client agents (user-facing, spawned via onboarding):**

| Cadence | Behavior |
|---|---|
| Daily at user's 9am (from USER.md timezone) | Proactive check-in: 3 concrete suggestions based on recent context |
| On new relevant information found | "Found something you should see — want a brief?" |
| End of productive session | Write session summary to `memory/YYYY-MM-DD.md` |
| Weekly | "Here's what we got done this week. What's the priority next?" |

**Client agent daily check-in format:**

```
Good morning 👋

Here's what I'm thinking for today:
1. You mentioned [X] — want to pick up where we left off?
2. I found [Y relevant to their work] — should I brief you?
3. [optional: calendar-aware] You have [event] at [time] — want a prep brief?

Or just tell me what's on your mind.
```

The user never has to think of what to ask. The agent manages the relationship.

---

### 7.7 Client Onboarding — Qualify-First Flow

*Replaces the manual approval gate (removed 2026-02-22)*

```
                    ┌─ QUALIFY (score ≥ 70) ──→ Mini App → auto-spawn → 🟢 live
email → bot ───────┤
                    └─ CONTACT TRACK (score < 70) → CRM → nurture → optional master push
```

**Qualification scoring (automated, no human in the loop):**

| Signal | Points |
|---|---|
| Company email domain (not gmail/yahoo/hotmail) | +30 |
| Specific use case selected (not "general") | +20 |
| Team size: solo +0, small team +20, company +40 | up to +40 |
| Referred (has referral code) | +25 |
| Base | 50 |

**Thresholds:**
- Score ≥ 70 → `qualified` → Mini App link sent immediately → auto-spawn on completion
- Score < 70 → `contact_track` → nurture email sequence + CRM tag + weekly review digest

**New OnboardState values:**
```typescript
'qualifying'    // bot is running qualification conversation
'qualified'     // auto-spawn path — no master approval needed
'contact_track' // nurture path — master can push anytime via /qualify {email}
'waitlisted'    // capacity cap reached (future)
```

**Master's role in onboarding:** Weekly digest of contact_track leads. One tap to push any lead to qualified. No real-time approval bottleneck.

---

### 7.8 The One-Liner

> **The agents run the work. Master sets the priorities. Humans only touch decisions that are genuinely theirs to make.**

---

*Spec v1.3 — 2026-02-22. Owner: m2. Do not edit the copy in docs/ directly — edit fleet-playbook sections/architecture.md and sync.*

## 4c. Spawn Approval Control — ADR

**Decision:** Three-phase spawn approval surface. Single `/spawn/approve/{contact_id}` endpoint — any surface calls it, CRM reflects truth.

| Phase | Surface | When |
|-------|---------|------|
| 1 | Telegram inline Approve/Reject (m2 escalation to master) | Now — zero new UI |
| 2 | Twenty CRM custom action on `pending_review` contact | After Mini App built |
| 3 | Auto-approval (email verified + token valid + billing) | When billing live |

**Fleet app is NOT an approval surface** — it monitors running infrastructure only.

**Planka card:** `1715268064934626884` — Master Roadmap / Next 2 Weeks

---

## §8. OpenClaw Release + Update Rhythm

### 8.1 Design Goal

OpenClaw m2-custom stays current with upstream without manual intervention. New spawns always boot with the latest build. Running agents update in-place at 3am — no session loss.

### 8.2 Daily Pipeline

```
01:00 UTC — machine-machine/openclaw: sync-upstream.yml
  └─ Fetches openclaw/openclaw:main
  └─ Merges into m2-custom (abort if conflict, keep custom)
  └─ Tags: m2-custom-YYYY-MM-DD
  └─ Dispatches 'openclaw-updated' event → m2-desktop

02:30 UTC — machine-machine/m2-desktop: build-agent.yml
  └─ Triggered by dispatch OR daily schedule
  └─ Builds Dockerfile (clones m2-custom, pnpm build)
  └─ Pushes ghcr.io/machine-machine/m2-desktop:agent-latest
  └─ New spawns pull this image — OpenClaw baked in

03:00 UTC — each running agent: openclaw-update.sh (via supervisord)
  └─ git fetch origin m2-custom
  └─ If new commits: git pull + pnpm install + pnpm build
  └─ supervisorctl restart clawdbot-gateway
  └─ No container restart — sessions unaffected
  └─ Logs to /var/log/openclaw-update.log
  └─ Rolls back on build failure
```

### 8.3 Component Locations

| Component | Location | Branch |
|-----------|----------|--------|
| Sync workflow | machine-machine/openclaw/.github/workflows/sync-upstream.yml | m2-custom |
| Build workflow | machine-machine/m2-desktop/.github/workflows/build-agent.yml | base |
| In-agent updater | machine-machine/m2-desktop/scripts/openclaw-update.sh | base |
| Supervisord entry | machine-machine/m2-desktop/scripts/supervisord.conf `[openclaw-updater]` | base |
| Prebuild location | /opt/openclaw-prebuild (inside agent-latest image) | — |
| Runtime fork | ${WORKSPACE}/platform/openclaw (agent named volume) | m2-custom |

### 8.4 Cold Boot Behaviour

On first boot (openclaw.json missing):
1. entrypoint.sh detects `/opt/openclaw-prebuild/dist` exists → `cp` to workspace fork (fast, no network)
2. symlinks `/usr/lib/node_modules/openclaw` → workspace fork
3. `generate-openclaw-config.js` writes `openclaw.json`
4. Gateway starts immediately — no build delay

### 8.5 Conflict Strategy

If upstream merges with conflicts:
- Workflow aborts merge, keeps m2-custom unchanged
- No tag created, no dispatch, no rebuild
- m2 heartbeat monitors for failed sync runs and alerts master with diff summary
- Master resolves manually via `git merge upstream/main` on local clone

### 8.6 Required GitHub Secret

`M2_DESKTOP_DISPATCH_TOKEN` must be set in `machine-machine/openclaw` repo secrets:
- GitHub → machine-machine/openclaw → Settings → Secrets → Actions
- Value: PAT with `repo` scope on `machine-machine/m2-desktop`
- Without this: sync + tag still work, but image rebuild must be triggered manually

### 8.7 Manual Trigger

Force a sync + rebuild at any time:
```bash
# Trigger sync (even without new upstream commits)
gh workflow run sync-upstream.yml --repo machine-machine/openclaw --field force=true

# Trigger image rebuild directly
gh workflow run build-agent.yml --repo machine-machine/m2-desktop
```

---
*Added 2026-02-22. Commits: openclaw de667ef, m2-desktop 1b742ebd.*
