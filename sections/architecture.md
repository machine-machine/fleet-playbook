# Machine.Machine OS — Architecture Spec v1.1
*Self-audit based on m2 (reference instance) + fleet analysis — 2026-02-21*
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

# Skills to install on cold boot
AGENT_SKILLS: m2-memory,rlm-memory,planka,planka-pm,playbook,xfce-desktop,stt
```

---

### 3.3 Runtime Layer — Claude CLI

**Claude Code CLI is pre-installed in the Docker image** (Dockerfile):
```dockerfile
# Install Claude Code CLI at image build time
RUN curl -fsSL https://claude.ai/install.sh | sh \
    || npm install -g @anthropic-ai/claude-code
```

This ensures even a cold-booted agent without a persisted home can run `claude` immediately.

**On warm restart** — `startup.sh` always runs:
```bash
# Update Claude to latest — non-blocking, best-effort
claude update --skip-permissions 2>/dev/null &
```

**Result:** Cold boot = Claude available from image. Warm boot = latest Claude auto-updated in background. The binary lives in `~/.local/bin/claude` (persisted via m2_home pattern), so after first install it's always there.

---

### 3.4 Bootstrap Layer

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
├── WARM START (restart):
│     claude update --skip-permissions &   ← background, non-blocking
│     git pull --ff-only on all skill repos (non-destructive)
│     relink openclaw fork symlink
│     start VNC + guacd + OpenClaw gateway
│
└── COLD START (new agent):
      1.  Clone openclaw:m2-custom → ~/.openclaw/platform/openclaw && npm ci
      2.  ln -sfn ~/.openclaw/platform/openclaw /usr/lib/node_modules/openclaw
      3.  Clone fleet-playbook → ~/.openclaw/platform/fleet-playbook
      4.  Install skills (git clone each from AGENT_SKILLS)
      5.  generate-openclaw-config.js  (from env vars → openclaw.json)
      6.  write_config_files()  (planka, coolify, bge-proxy, cerebras configs)
      7.  Ingest bootstrap memories (JSONL from fleet-playbook or env URL)
      8.  Register in Guacamole (register-guacamole.sh)
      9.  Write identity files (SOUL.md, AGENTS.md, USER.md from template)
      10. Start VNC + guacd + OpenClaw gateway
```

---

### 3.5 Skill Layer

**Rule: every skill = a git repo under `machine-machine/openclaw-{skill}-skill`.**

```
Status:
  ✅ git-tracked:  m2-memory, rlm-memory, planka, bmad-elicit, spawn-machine, x-monitor
  ❌ need repos:   planka-pm, playbook, xfce-desktop, stt, coolify, homeassistant,
                   tts-manager, x-scraper, browser-persistence, twenty, video-ad-creator
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

### 3.10 Spawn Flow

```bash
spawn_agent() {
  NAME=$1; TOKEN=$2; KEY=$3; SKILLS=$4

  # 1. Host: create bind mount dir (needs SSH or Coolify pre_deployment_command)
  # 2. Create Coolify app from machine-machine/m2-desktop:base
  #    with M2_HOME=/agent_home, AGENT_NAME=$NAME, all keys
  # 3. Deploy → cold boot → full bootstrap runs automatically
  # 4. Agent registers itself in Guacamole (bootstrap step 8)
  # 5. m2 adds agent to registry.yaml
}
```

---

## 4. Migration Plan

| Phase | What | Touches m2? | Est. |
|-------|------|-------------|------|
| 0 | Fix agents: add `M2_HOME=/agent_home` + volume at `/agent_home` | ❌ | 30 min |
| 1 | Extract `m2o-guacamole` standalone repo + Coolify deploy | ❌ | Done today |
| 2 | `base` branch: updated entrypoint + cold/warm + write_config_files | ❌ | 2 days |
| 3 | Claude pre-install in Dockerfile + `claude update` on warm start | ❌ | in phase 2 |
| 4 | Push 11 missing skill repos to GitHub | m2 skills only | 3 days |
| 5 | Fleet control Streamlit `m2o-fleet` | ❌ | 1 week |
| 6 | Host bind mounts `/opt/m2o/` (needs Coolify host SSH) | ❌ | coordinate |
| 7 | Migrate m2 to new architecture | ✅ last | when stable |

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

*Spec v1.1 — 2026-02-21. Owner: m2. Do not edit the copy in docs/ directly — edit fleet-playbook sections/architecture.md and sync.*
