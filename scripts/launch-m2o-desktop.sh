#!/usr/bin/env bash
# launch-m2o-desktop.sh — spawn an m2o desktop and wire it into fleet Guacamole.
#
# Runs on either m2 (primary) or m2.2 (secondary) and does end-to-end setup:
#   1. provision the desktop container (if not present) via the host's provision.sh
#   2. wait for it to become healthy (tolerating the ~2 min first-boot rm -rf /home)
#   3. on m2.2 only: create a per-desktop alpine/socat guacd relay on m2.2's host
#   4. upsert an RDP row in m2's guacamole-db pointing at the desktop's guacd
#   5. grant Guacamole perms to a configurable user list
#
# Idempotent: safe to re-run. Existing container/relay are reused; the connection
# row is updated in place (matched by connection_name + protocol).
#
# Usage: launch-m2o-desktop.sh <name> [OPTIONS]

set -euo pipefail

# ---------- defaults ----------
VNC_PASS="agentdesktop"
RELAY_PORT=""                       # auto-pick if unset (X4822 scheme)
GRANT_USERS="guacadmin,m2"          # comma-separated Guacamole USER names
M2_SSH="m2@192.168.31.224"          # SSH target for m2 (fallback: 192.168.31.28)
M2_LAN_IP="192.168.31.34"           # m2.2's LAN IP — used as proxy_hostname
GUAC_DB_ROOT_PASS="guacamole_root_pass"
GUAC_DB_NAME="guacamole_db"
SKIP_GUAC=false
FORCE_RECREATE=false

usage() {
  cat <<EOF
Usage: $0 <name> [OPTIONS]

Spawns m2o desktop '<name>-m2o' on the current host and wires it into m2's Guacamole.

Options:
  --vnc-pass <pass>        VNC/RDP password (default: agentdesktop)
  --relay-port <port>      Host port on m2.2 for guacd relay (default: auto-pick)
  --grant-users u1,u2,...  Guacamole users to grant perms (default: guacadmin,m2)
  --m2-ssh <user@host>     SSH target for m2 (default: m2@192.168.31.224)
  --skip-guacamole         Skip Guacamole wiring (provision + relay only)
  --force-recreate         Rebuild container even if it exists (volumes preserved)
  -h, --help               This help
EOF
}

# ---------- parse args ----------
[[ $# -lt 1 ]] && { usage; exit 1; }
case "$1" in -h|--help) usage; exit 0;; esac
NAME="$1"; shift
[[ "$NAME" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "ERROR: name must be lowercase alnum/hyphen"; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vnc-pass)       VNC_PASS="$2"; shift 2;;
    --relay-port)     RELAY_PORT="$2"; shift 2;;
    --grant-users)    GRANT_USERS="$2"; shift 2;;
    --m2-ssh)         M2_SSH="$2"; shift 2;;
    --skip-guacamole) SKIP_GUAC=true; shift;;
    --force-recreate) FORCE_RECREATE=true; shift;;
    -h|--help)        usage; exit 0;;
    *) echo "ERROR: unknown option: $1"; usage; exit 1;;
  esac
done

CONTAINER="${NAME}-m2o"
RELAY_NAME="${NAME}-guacd-relay"
CONN_NAME="$(tr '[:lower:]' '[:upper:]' <<<"${NAME:0:1}")${NAME:1} Desktop"

# ---------- detect host role ----------
H=$(hostname)
case "$H" in
  m2|m2-main|m2main)
    HOST_ROLE="m2"
    PROVISION_DIR="$HOME/m2o/desktop"
    ;;
  m2.2)
    HOST_ROLE="m2.2"
    PROVISION_DIR="$HOME/machinemachine-core/m2o/desktop"
    ;;
  *)
    echo "ERROR: unrecognized hostname '$H' — must be m2 or m2.2"; exit 1;;
esac
echo ">> host role: $HOST_ROLE  (hostname=$H)"
[[ -x "$PROVISION_DIR/provision.sh" ]] || {
  echo "ERROR: provision.sh not found at $PROVISION_DIR/provision.sh"; exit 1; }

# ---------- helper: run SQL on m2's guacamole-db ----------
guac_sql() {
  local sql="$1"
  local cmd='DB=$(docker ps --format "{{.Names}}" | grep -m1 guacamole-db); '
  cmd+='exec docker exec -i "$DB" mysql -uroot -p'"$GUAC_DB_ROOT_PASS"' -Nse "$(cat)" '"$GUAC_DB_NAME"
  if [[ "$HOST_ROLE" == "m2" ]]; then
    printf '%s' "$sql" | bash -c "$cmd"
  else
    printf '%s' "$sql" | ssh -o BatchMode=yes "$M2_SSH" bash -c "'$cmd'"
  fi
}

# ---------- 1. provision ----------
echo ">> [1/5] provision: $CONTAINER"
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
  if $FORCE_RECREATE; then
    echo "   --force-recreate: removing $CONTAINER (named volumes preserved)"
    docker rm -f "$CONTAINER" >/dev/null
    (cd "$PROVISION_DIR" && ./provision.sh "$NAME" "$VNC_PASS")
  else
    echo "   already exists — skipping provision (use --force-recreate to rebuild)"
  fi
else
  (cd "$PROVISION_DIR" && ./provision.sh "$NAME" "$VNC_PASS")
fi

# ---------- 2. wait for healthy + RDP ready ----------
echo ">> [2/5] waiting for $CONTAINER — first-boot cleanup takes ~2 min"
DESKTOP_IP=""
for i in $(seq 1 60); do
  status=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "?")
  ip=$(docker inspect "$CONTAINER" \
        --format '{{(index .NetworkSettings.Networks "coolify").IPAddress}}' 2>/dev/null || true)
  if [[ "$status" == "healthy" && -n "$ip" ]] && timeout 2 bash -c "echo > /dev/tcp/$ip/3389" 2>/dev/null; then
    DESKTOP_IP="$ip"
    echo "   healthy — IP=$DESKTOP_IP, RDP:3389 open"
    break
  fi
  printf '   [%3ds] status=%-10s ip=%-12s\n' $((i*5)) "$status" "${ip:--}"
  sleep 5
done
[[ -n "$DESKTOP_IP" ]] || { echo "ERROR: $CONTAINER never became healthy/ready"; exit 1; }

# ---------- 3. guacd relay (m2.2 only) ----------
GUAC_PROXY_HOST=""
GUAC_PROXY_PORT=""
if [[ "$HOST_ROLE" == "m2.2" ]]; then
  echo ">> [3/5] guacd relay: $RELAY_NAME on m2.2"
  if docker inspect "$RELAY_NAME" >/dev/null 2>&1; then
    existing=$(docker inspect "$RELAY_NAME" \
      --format '{{range $p, $bs := .NetworkSettings.Ports}}{{range $bs}}{{.HostPort}} {{end}}{{end}}' \
      | awk '{print $1}')
    echo "   $RELAY_NAME already exists on host port ${existing:-?} — reusing"
    GUAC_PROXY_PORT="${existing:-$RELAY_PORT}"
  else
    if [[ -z "$RELAY_PORT" ]]; then
      # auto-pick next free X4822 (14822, 24822, 34822, ...) above the current max
      max=$(docker ps -a --format '{{.Ports}}' \
            | grep -oE '0\.0\.0\.0:[0-9]+4822' \
            | awk -F: '{print $2}' | sort -n | tail -1)
      if [[ -z "$max" ]]; then next=14822
      else next=$((max + 10000))
      fi
      RELAY_PORT=$next
      echo "   auto-picked relay port: $RELAY_PORT"
    fi
    docker run -d --name "$RELAY_NAME" --restart unless-stopped \
      --network coolify -p "$RELAY_PORT:$RELAY_PORT" \
      alpine/socat "tcp-listen:$RELAY_PORT,fork,reuseaddr" "tcp:$CONTAINER:4822" >/dev/null
    echo "   created $RELAY_NAME → tcp-listen:$RELAY_PORT → $CONTAINER:4822"
    GUAC_PROXY_PORT="$RELAY_PORT"
  fi
  GUAC_PROXY_HOST="$M2_LAN_IP"
else
  echo ">> [3/5] host=m2 — no relay needed (guacamole-full reaches $CONTAINER:4822 on the coolify network)"
  GUAC_PROXY_HOST="$CONTAINER"
  GUAC_PROXY_PORT="4822"
fi

# ---------- 4. Guacamole connection (upsert) ----------
if $SKIP_GUAC; then
  echo ">> [4/5] --skip-guacamole — skipping Guacamole wiring"
else
  echo ">> [4/5] Guacamole: upsert '$CONN_NAME' → $GUAC_PROXY_HOST:$GUAC_PROXY_PORT"
  ESC_NAME="${CONN_NAME//\'/\\\'}"

  existing_id=$(guac_sql "SELECT connection_id FROM guacamole_connection WHERE connection_name='$ESC_NAME' AND protocol='rdp' LIMIT 1;")
  existing_id=$(echo "$existing_id" | tr -d '[:space:]')

  if [[ -n "$existing_id" ]]; then
    echo "   updating existing connection_id=$existing_id"
    guac_sql "
      UPDATE guacamole_connection
         SET proxy_hostname='$GUAC_PROXY_HOST', proxy_port=$GUAC_PROXY_PORT
       WHERE connection_id=$existing_id;
      DELETE FROM guacamole_connection_parameter WHERE connection_id=$existing_id;
    "
    CONN_ID="$existing_id"
  else
    guac_sql "
      INSERT INTO guacamole_connection (connection_name, protocol, proxy_hostname, proxy_port)
      VALUES ('$ESC_NAME', 'rdp', '$GUAC_PROXY_HOST', $GUAC_PROXY_PORT);
    "
    CONN_ID=$(guac_sql "SELECT connection_id FROM guacamole_connection WHERE connection_name='$ESC_NAME' AND protocol='rdp' LIMIT 1;" | tr -d '[:space:]')
    echo "   inserted new connection_id=$CONN_ID"
  fi

  guac_sql "
    INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES
      ($CONN_ID,'hostname','127.0.0.1'), ($CONN_ID,'port','3389'),
      ($CONN_ID,'username','developer'), ($CONN_ID,'password','$VNC_PASS'),
      ($CONN_ID,'width','1920'), ($CONN_ID,'height','1080'), ($CONN_ID,'color-depth','32'),
      ($CONN_ID,'security','any'), ($CONN_ID,'ignore-cert','true'),
      ($CONN_ID,'enable-drive','true'), ($CONN_ID,'drive-name','Shared'),
      ($CONN_ID,'drive-path','/home/developer/Desktop/Shared'),
      ($CONN_ID,'create-drive-path','true'), ($CONN_ID,'enable-sftp','false');
  "

  # ---------- 4b. m2.2 host override for console-auth (Guacamole "Console" button) ----------
  if [[ "$HOST_ROLE" == "m2.2" ]]; then
    echo ">> [4b/5] recording console host override for '$NAME' → console.m-2.cc"
    ssh -o BatchMode=yes "$M2_SSH" bash -s "$NAME" <<'REMOTE'
set -e
NAME="$1"
cd ~/m2o/console-auth
python3 - "$NAME" <<'PY'
import json, pathlib, sys, re
name = sys.argv[1]
p = pathlib.Path("secrets.env")
lines = p.read_text().splitlines()
found = False
for i, l in enumerate(lines):
    if l.startswith("CONSOLE_HOST_OVERRIDES="):
        raw = l[len("CONSOLE_HOST_OVERRIDES="):].strip()
        d = json.loads(raw) if raw else {}
        if d.get(name) == "console.m-2.cc":
            print("already-set"); sys.exit(0)
        d[name] = "console.m-2.cc"
        lines[i] = "CONSOLE_HOST_OVERRIDES=" + json.dumps(d, separators=(",", ":"))
        found = True
        break
if not found:
    lines.append('CONSOLE_HOST_OVERRIDES={"' + name + '":"console.m-2.cc"}')
p.write_text("\n".join(lines) + "\n")
print("added")
PY
docker rm -f console-auth >/dev/null 2>&1 || true
docker run -d --name console-auth --restart unless-stopped \
  --network coolify --env-file secrets.env console-auth:latest >/dev/null
docker network connect e0o8o8cowkswcwsgs4so48s8 console-auth 2>/dev/null || true
echo "   console-auth redeployed on m2 with '$NAME' host override"
REMOTE
  fi

  # ---------- 5. perms ----------
  echo ">> [5/5] granting perms to: $GRANT_USERS"
  IFS=',' read -ra USERS <<<"$GRANT_USERS"
  for u in "${USERS[@]}"; do
    u_trim=$(echo "$u" | tr -d '[:space:]')
    [[ -z "$u_trim" ]] && continue
    guac_sql "
      INSERT IGNORE INTO guacamole_connection_permission (entity_id, connection_id, permission)
      SELECT e.entity_id, $CONN_ID, p.perm
      FROM guacamole_entity e
      CROSS JOIN (SELECT 'READ' AS perm UNION ALL SELECT 'UPDATE'
                  UNION ALL SELECT 'DELETE' UNION ALL SELECT 'ADMINISTER') p
      WHERE e.name='$u_trim' AND e.type='USER';
    "
    echo "   granted: $u_trim"
  done

  # Guacamole picks up DB changes on next login/session — no restart needed.
  # (An earlier version of this script restarted guacamole-full here; that
  # invalidated every active user's session and made connections appear to
  # "disappear" until they logged back in. Removed 2026-08-24.)
fi

# ---------- summary ----------
cat <<EOF

>> DONE: $CONTAINER

  desktop container   $CONTAINER (IP $DESKTOP_IP on coolify net, host $HOST_ROLE)
  volumes             ${NAME}-agent-home, ${NAME}-workspace, ${NAME}-m2home
  RDP direct          ssh -L 3389:$DESKTOP_IP:3389 $(whoami)@$(hostname) → localhost:3389
  RDP user / pass     developer / $VNC_PASS
EOF
if ! $SKIP_GUAC; then
  cat <<EOF
  guacd endpoint      $GUAC_PROXY_HOST:$GUAC_PROXY_PORT$([[ "$HOST_ROLE" == "m2.2" ]] && echo "  (via $RELAY_NAME)")
  guacamole conn      #$CONN_ID '$CONN_NAME' (rdp)
  guacamole users     $GRANT_USERS
  guacamole URL       https://m2o.machinemachine.ai
EOF
fi
