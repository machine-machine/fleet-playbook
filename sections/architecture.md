# Machine.Machine OS — Architecture Spec v1.4
*Self-audit based on m2 (reference instance) + fleet analysis — 2026-02-21*
*Updated 2026-02-21: Added §3.11 m2o-autoheal self-healing gateway monitor*
*Updated 2026-02-22: Added §7 The Rhythm — Human-in-the-Loop Operating Model*
*Updated 2026-07-12: Truth pass — Hermes runtime, Mattermost comms, Guacamole on m2, m2-gpt gateway, memory.machinemachine.ai, herdr, primus*
*Lives in: machine-machine/fleet-playbook @ sections/architecture.md*

---

## ⚠️ Prime Directive: Don't Touch m2

m2 is the reference machine. Months of accumulated work, skills, memory, crons, custom Hermes runtime, TTS pipeline — all running. **Do not redeploy, restructure, or migrate m2** until every agent is on the new architecture and proven stable. m2 is the safety net.

All architecture work targets the `base`/`primus` image for new/other agents only.

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
Agents set `HERMES_HOME=/hermes_home` but NOT `M2_HOME`.  
Volume was mounted at `/hermes_home` — entrypoint symlinked `/home` to `/m2_home/home` (a path inside the ephemeral layer).  
**Every restart = cold start.** One missing env var.

**Fix:** `M2_HOME=/agent_home` + volume mounted at `/agent_home`.

### Guacamole — the actual topology

Guacamole is **not** a standalone external host anymore. It runs **on m2** and is reachable at `m2o.machinemachine.ai`, serving **RDP-default** desktops for the fleet.

```
On m2 (Coolify):
  m2o-guacamole
  ├── guacamole-db             ✅ RUNNING — MariaDB on coolify network
  └── guacamole                ✅ RUNNING — reachable at m2o.machinemachine.ai
                                  serves RDP connections to each agent desktop

  m2-desktop:main
  └── m2-desktop-worker        ✅ m2's own desktop, registered as a Guacamole connection
```

Each agent's desktop is registered as a Guacamole RDP connection; operators open `m2o.machinemachine.ai` and pick the agent.

---

## 2. Self-Audit: m2's Gaps

| Problem | Severity |
|---------|----------|
| 17/21 skills have no git tracking | 🔴 HIGH |
| 3 skill repos dirty (planka, spawn-machine, x-monitor) | 🟡 MED |
| Skills can't be auto-updated (no git pull) | 🔴 HIGH |
| `/workspace` volume misaligned (real workspace is in m2_home) | 🟡 LOW |
| hermes.json not git-backed | 🟡 MED (secrets — env vars are source of truth) |

These will be resolved for new agents via the `primus` image. m2 will be migrated last.

---

## 3. Target Architecture

### Layer stack

```
┌──────────────────────────────────────────────────────────┐
│  ORCHESTRATION   herdr / m2herd  (panes + worktrees)     │
├──────────────────────────────────────────────────────────┤
│  DESKTOPS        m2o.machinemachine.ai  (Guacamole/RDP)  │
├──────────────────────────────────────────────────────────┤
│  LLM GATEWAY     gpt.machinemachine.ai  (m2-gpt/Bifrost) │
├──────────────────────────────────────────────────────────┤
│  IDENTITY        env vars only (AGENT_NAME, keys)        │
├──────────────────────────────────────────────────────────┤
│  RUNTIME         Claude CLI + Hermes agent runtime       │
├──────────────────────────────────────────────────────────┤
│  SKILL LAYER     all skills = git repos, pull on start   │
├──────────────────────────────────────────────────────────┤
│  CONFIG LAYER    written from env vars on cold boot      │
├──────────────────────────────────────────────────────────┤
│  PERSISTENCE     /opt/m2o/{name}/home → /agent_home      │
│                  bind mount on Coolify host              │
├──────────────────────────────────────────────────────────┤
│  BASE IMAGE      machine-machine/primus:latest           │
│                  one image, all agents same base         │
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

# Memory (memory.machinemachine.ai)
COLLECTION_NAME: agent_memory_${AGENT_NAME}
QDRANT_URL: http://memory-qdrant:6333

# Comms + services (set via Coolify shared env group)
MATTERMOST_URL: https://chat.machinemachine.ai
MATTERMOST_TOKEN: ...          # agent's Mattermost bot token
M2_GPT_URL: https://gpt.machinemachine.ai   # m2-gpt gateway (GLM via Bifrost)
PLANKA_URL: https://kanban.machinemachine.ai
PLANKA_TOKEN: ...
COOLIFY_TOKEN: ...

# TTS/STT
AGENT_TTS_BASE_URL: http://speech_gateway/v1
AGENT_STT_BASE_URL: http://speaches-.../v1

# Hermes runtime
AGENT_HERMES_REPO: https://github.com/machine-machine/hermes.git
AGENT_HERMES_BRANCH: main

# Skills to install on cold boot (all agents, non-negotiable defaults)
AGENT_SKILLS: m2-memory,rlm-memory,bmad-elicit,planka,planka-pm,playbook,herdr,xfce-desktop,stt
```

---

### 3.3 Runtime Layer — Two-Tier Docker Image

**"Minutes onboarding" requires pre-baking slow steps into the image — not running them at container start.**

```
Tier 1: base image  (machine-machine/primus:base)
  Ubuntu + XFCE + RDP/VNC + guacd + system deps
  Claude CLI (curl install at build time)
  Rebuilt: rarely (major system changes only)

Tier 2: agent image  (machine-machine/primus:latest)
  FROM base
  + Hermes runtime cloned + npm ci (done at build time)
  + All skill repos pre-cloned
  Rebuilt: weekly via GitHub Actions CI
```

All agents pull `primus:latest`. Cold boot = `git pull` (seconds) not `git clone + npm ci` (15 min).

**Staged base always warm in Coolify:** A permanent `primus-staging` app keeps image layers cached. Real agent deploys pull from cache — not a fresh build.

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

**Critical path principle:** The only thing on the blocking path to "reachable" is: config write → RDP/VNC start → gateway start. Everything else is background.

```bash
provision.sh
│
├── Phase 1 (ALWAYS): persistent home setup
│     entrypoint symlink pattern (M2_HOME/home → /home)
│
├── Phase 2: warm or cold?
│     if ~/.hermes/hermes.json exists → WARM
│     else → COLD
│
├── WARM START (fast path, ~60s):
│     claude update --skip-permissions &        ← background
│     git pull --ff-only skills/* &             ← background, parallel
│     git pull hermes:main --ff-only &          ← background
│     relink Hermes runtime symlink
│     start RDP/VNC + guacd + Hermes gateway    ← only blocking steps
│
└── COLD START (new agent, target <5 min):
      # BLOCKING (sequential, critical path):
      1.  validate_env_vars() — missing required → post to Mattermost @m2 + exit
      2.  git pull --ff-only on pre-cloned Hermes (image has it already)
      3.  ln -sfn ~/.hermes/platform/hermes /usr/lib/node_modules/hermes
      4.  generate-hermes-config.js  (from env vars → hermes.json)
      5.  write_config_files()  (planka, coolify, mattermost, m2-gpt, cerebras)
      6.  Write identity files (SOUL.md, AGENTS.md, USER.md from template)
      7.  Start RDP/VNC + guacd + Hermes gateway
      8.  Notify master: "⚡ {AGENT_NAME} is online. Desktop: m2o.machinemachine.ai
                          Connection: {AGENT_NAME}. Seeding memories in background."

      # BACKGROUND (non-blocking, parallel after gateway starts):
      9.  git pull --ff-only skills/* &
      10. ingest_bootstrap_memories.py &   ← doesn't block comms
      11. clone fleet-playbook if missing &
```

---

### 3.5 Skill Layer

**Rule: every skill = a git repo under `machine-machine/hermes-{skill}-skill` (mirrored to Forgejo).**

```
Status:
  ✅ ALL fleet skills now git-tracked (2026-02-21):
     hermes-m2-memory-skill, hermes-rlm-memory-skill, hermes-spawn-machine-skill
     hermes-bmad-elicit-skill, planka, x-monitor  (legacy naming)
     m2o-skill-planka-pm, m2o-skill-playbook, m2o-skill-xfce-desktop
     m2o-skill-stt, m2o-skill-coolify, m2o-skill-herdr, m2o-skill-tts-manager
     m2o-skill-x-scraper, m2o-skill-browser-persistence, m2o-skill-twenty
  🚫 m2-only (not fleet): homeassistant, video-ad-creator, kiedis-po, qwen-tts
```

**Warm restart skill refresh:**
```bash
for skill_dir in ~/.hermes/skills/*/; do
  [ -d "$skill_dir/.git" ] && git -C "$skill_dir" pull --ff-only --quiet 2>/dev/null &
done
```

**m2 skill migration (don't touch now):**  
On next m2 maintenance window: push each manual skill to its own GitHub/Forgejo repo, then convert to git clone. Until then, m2's skills are safe inside `m2_home` volume.

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

  # Mattermost (comms)
  install -m 600 /dev/null ~/.config/mattermost/config
  printf "MATTERMOST_URL=%s\nMATTERMOST_TOKEN=%s\n" "$MATTERMOST_URL" "$MATTERMOST_TOKEN" \
    > ~/.config/mattermost/config

  # m2-gpt gateway (GLM via Bifrost)
  install -m 600 /dev/null ~/.config/m2-gpt/config
  printf "M2_GPT_URL=%s\nM2_GPT_TOKEN=%s\n" "$M2_GPT_URL" "$M2_GPT_TOKEN" \
    > ~/.config/m2-gpt/config

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
cd ~/.hermes/workspace && git add memory/ MEMORY.md && git commit -m "daily backup" && git push
```

**Track B — host bind mount rsync (Coolify host level):**
```bash
rsync -a /opt/m2o/ /backup/m2o/ \
  --exclude='*/.cache/' \
  --exclude='*/node_modules/' \
  --exclude='*/.local/share/flatpak/'
```

---

### 3.8 Guacamole on m2 — RDP-Default Desktops

**Runs on:** m2 (Coolify app `m2o-guacamole`)  
**URL:** `m2o.machinemachine.ai`  
**Principle:** Guacamole is fleet infrastructure hosted on m2, not tied to any single agent. Desktops default to **RDP**.

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

  guacamole:
    image: guacamole/guacamole:1.5.5
    container_name: guacamole
    restart: unless-stopped
    depends_on:
      guacamole-db:
        condition: service_healthy
    environment:
      GUACD_HOSTNAME: ${GUACD_HOSTNAME:-guacd}
      GUACD_PORT: 4822
      MYSQL_HOSTNAME: guacamole-db
      MYSQL_DATABASE: guacamole_db
      MYSQL_USER: guacamole_user
      MYSQL_PASSWORD: ${GUAC_DB_PASSWORD}
    networks:
      coolify:
        external: true
    labels:
      - traefik.http.routers.guacamole.rule=Host(`m2o.machinemachine.ai`)

volumes:
  guacamole_db:
networks:
  coolify:
    external: true
```

**Each agent registers its desktop on cold boot** via `register-guacamole.sh` — RDP connection by default, VNC fallback.

---

### 3.9 Fleet Control

Fleet health, memory sizes, escalations, and Planka summaries are surfaced through Mattermost (`fleet-ops` channel + the morning brief) and the m2-gpt gateway dashboards. A dedicated Streamlit control panel is optional and no longer on the critical path — Mattermost is the human interface.

```
Panel 1 — Fleet Status   → fleet-ops channel: name, Coolify status, last active, desktop link
Panel 2 — Memory         → memory.machinemachine.ai: collection sizes + last write per agent
Panel 3 — Escalations    → Mattermost escalations channel, reply in-thread
Panel 4 — Planka         → Master Roadmap Now/Next/Done summary
Panel 5 — Actions        → provision.sh spawn, restart agent, broadcast, rolling update
Panel 6 — Logs           → Coolify deployment logs, 100 lines per agent
```

---

### 3.10 Spawn Flow — "Minutes Onboarding"

**Goal:** Master provides 2 things (agent name + Telegram token). Everything else is automated by `provision.sh`.

```bash
# Single command:
provision.sh <name> <telegram_bot_token>

spawn_agent() {
  NAME=$1; TOKEN=$2

  # 1. Validate: check name not already in registry
  grep -q "^  $NAME:" ~/.hermes/workspace/platform/incubator/registry.yaml && exit 1

  # 2. Pre-register Guacamole RDP connection on m2 (m2o.machinemachine.ai)
  register-guacamole.sh pre-register "$NAME" "${NAME}-desktop"

  # 3. Create Coolify app from machine-machine/primus:latest
  UUID=$(coolify.sh create-compose-app \
    --name "${NAME}-desktop" \
    --repo machine-machine/primus \
    --branch latest \
    --attach-env-group m2o-shared)   # ← gets Qdrant, Mattermost, m2-gpt, TTS, Planka, Coolify creds

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

**Timeline after `provision.sh peter <token>`:**
```
T+0:00  provision.sh runs (Coolify app created + deploy triggered)
T+0:30  Coolify pulls primus:latest image (cached layers — fast)
T+1:00  Container starts, entrypoint runs (first boot: copy /home to volume)
T+2:00  Configs written, Hermes gateway starts
T+3:00  "⚡ peter is online" Telegram message + Mattermost fleet-ops post
T+5:00  Background: memories seeded, skills updated, fleet-playbook pulled
```

---

### 3.11 m2o-autoheal — Self-Healing Gateway Monitor

**Every agent container runs `m2o-autoheal` as a supervisord service (priority 35, runs before the gateway).**

It wakes every 15 minutes, checks gateway config health, and self-repairs — no human intervention needed for the most common failure mode (invalid `hermes.json`).

**What it monitors:**
- `hermes.json` for invalid/rejected keys (e.g. stale `meta` block from config generator)
- Gateway process alive (via `pgrep`)
- Crash-loop indicator (repeated `exit status 1` in gateway log)

**Repair flow:**
```
1. Detect broken config (python3 JSON parse + key check)
2. Backup: ~/.hermes/backups/hermes.json.backup.YYYYMMDD-HHMMSS
3. Repair: hermes doctor --fix  (fallback: manual JSON strip)
4. Log outcome to /var/log/m2o-autoheal.log
5. Gateway auto-restarts via supervisord (autorestart=true)
```

**Backup retention:** Last 20 dated backups kept, older ones pruned automatically.

**Source:** `machine-machine/primus:base` → `scripts/m2o-autoheal.sh`  
**Baked into image at:** `/usr/local/bin/m2o-autoheal.sh`  
**Supervisord entry:**
```ini
[program:m2o-autoheal]
command=/bin/bash /usr/local/bin/m2o-autoheal.sh
user=root
autorestart=true
priority=35          # starts before hermes-gateway (priority=40)
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
| 1 | Guacamole on m2 (`m2o-guacamole`) → m2o.machinemachine.ai | ❌ | ✅ Done |
| 2 | `primus` image: Dockerfile + two-tier image + cold/warm bootstrap | ❌ | 2 days |
| 3 | GitHub Actions CI: weekly rebuild of `primus:latest` image | ❌ | in phase 2 |
| 4 | `provision.sh` single command (Coolify + registry + Guacamole) | ❌ | in phase 2 |
| 5 | Push missing skill repos to GitHub/Forgejo | m2 skills only | 3 days |
| 6 | Fleet surfacing via Mattermost + m2-gpt dashboards | ❌ | 1 week |
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
  Trigger: provision.sh {name} {token}  (or queue for review)
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

**fleet control as Telegram Mini App:**
Fleet control panel accessible as inline Telegram web app, mirroring the Mattermost fleet-ops view. Spawn, monitor, escalate — without leaving Telegram.

---

## 5. What NOT to Change

- m2's `m2_home` volume, entrypoint, hermes.json — **untouched until Phase 7**
- Mattermost comms (chat.machinemachine.ai) — working
- memory.machinemachine.ai (BGE-M3 + Qdrant) memory stack — working
- m2-gpt gateway (gpt.machinemachine.ai, GLM via Bifrost) — working
- TTS/STT infrastructure — working
- HEARTBEAT/cron pattern — working
- Daily workspace git push — extend to agents, don't redesign

---

## 6. Open Questions

1. **Coolify host SSH** — needed for `/opt/m2o/` bind mount setup (Phase 0/6)
2. **Telegram tokens** — miauczek, pittbull, peter need bots via @BotFather
3. **Skill repos** — planka-pm, playbook, xfce-desktop — public or private (GitHub + Forgejo mirror)?
4. **`GUACD_HOSTNAME`** — one shared guacd sidecar on m2 vs per-desktop guacd?
5. **Fleet control** — keep it in Mattermost + m2-gpt dashboards, or build a dedicated panel?

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
| Write to memory, update Planka card, send Mattermost message | 🟢 Agent |
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
  • destroy command (provision.sh)
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
   EMPTY  → flag to m2 in Mattermost ("Now list empty, no matching cards in Next 2 Weeks")

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
   → Escalate to m2 (Mattermost)
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

Agent → m2 (Mattermost escalations channel):
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

*Spec v1.4 — 2026-07-12. Owner: m2. Do not edit the copy in docs/ directly — edit fleet-playbook sections/architecture.md and sync.*

## 4c. Spawn Approval Control — ADR

**Decision:** Three-phase spawn approval surface. Single `/spawn/approve/{contact_id}` endpoint — any surface calls it, CRM reflects truth.

| Phase | Surface | When |
|-------|---------|------|
| 1 | Telegram inline Approve/Reject (m2 escalation to master) | Now — zero new UI |
| 2 | Twenty CRM custom action on `pending_review` contact | After Mini App built |
| 3 | Auto-approval (email verified + token valid + billing) | When billing live |

**Fleet app is NOT an approval surface** — it monitors running infrastructure only.

**Planka card:** `1715268064934626884` — Master Roadmap / Next 2 Weeks
