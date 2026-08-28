#!/usr/bin/env bash
# m2gw-provision-agent.sh — provision a tenant + agent + bearer on the m2-gpt
# gateway, then (optionally) wire the bearer into a target desktop's Hermes.
#
# All state lives in the prod gateway's postgres. Idempotent: existing tenant
# or agent is reused; route bindings are updated in place if they differ.
#
# Runs on m2 (has the gateway container) or on any host that can SSH to m2.
# If the target desktop lives on a different host, wire the Hermes config from
# there using --skip-hermes and copy the printed bearer yourself.
#
# Usage:
#   m2gw-provision-agent.sh <slug> [OPTIONS]
#
# Options:
#   --primary-route <id>     Route for priority 1  (default: spark-glm     — glm-5.3-flash)
#   --fallback-route <id>    Route for priority 2  (default: deepseek-spark — deepseek text)
#   --extra-fallback <id>    Additional route at priority 3                  (default: none)
#   --default-model <name>   Hermes model.default                            (default: m2gw-spark-glm/glm-5.3-flash)
#   --principal <email>      Principal ref for the agent                     (default: hi@grait.io)
#   --budget-usd <n>         Tenant monthly budget in USD                    (default: 20)
#   --retention-days <n>     Tenant memory retention                         (default: 90)
#   --hermes-container <c>   Docker container name of the desktop to wire    (default: <slug>-m2o if it exists on THIS host)
#   --skip-hermes            Do not update any container's Hermes config
#   --m2-ssh <user@host>     SSH target for m2 (only used when NOT on m2)    (default: m2@192.168.31.224)
#   -h, --help
#
# Prints the minted bearer once. Copy it before scrolling.

set -euo pipefail

# -------- defaults --------
PRIMARY_ROUTE="spark-glm"
FALLBACK_ROUTE="deepseek-spark"
EXTRA_FALLBACK=""
DEFAULT_MODEL="m2gw-spark-glm/glm-5.3-flash"
PRINCIPAL="hi@grait.io"
BUDGET_USD="20"
RETENTION_DAYS="90"
HERMES_CONTAINER=""
SKIP_HERMES=false
M2_SSH="m2@192.168.31.224"

# -------- parse --------
[[ $# -lt 1 ]] && { grep -E '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
case "$1" in -h|--help) grep -E '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0;; esac
SLUG="$1"; shift
[[ "$SLUG" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "ERROR: slug must be lowercase alnum/hyphen"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --primary-route)    PRIMARY_ROUTE="$2"; shift 2;;
    --fallback-route)   FALLBACK_ROUTE="$2"; shift 2;;
    --extra-fallback)   EXTRA_FALLBACK="$2"; shift 2;;
    --default-model)    DEFAULT_MODEL="$2"; shift 2;;
    --principal)        PRINCIPAL="$2"; shift 2;;
    --budget-usd)       BUDGET_USD="$2"; shift 2;;
    --retention-days)   RETENTION_DAYS="$2"; shift 2;;
    --hermes-container) HERMES_CONTAINER="$2"; shift 2;;
    --skip-hermes)      SKIP_HERMES=true; shift;;
    --m2-ssh)           M2_SSH="$2"; shift 2;;
    -h|--help)          grep -E '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "ERROR: unknown option: $1"; exit 1;;
  esac
done

# Detect if we're already on m2.
ON_M2=false
case "$(hostname)" in m2|m2-main|m2main) ON_M2=true;; esac

# -------- helper: run a python snippet inside the prod gateway container --------
run_in_gateway() {
  local script="$1"
  local remote_cmd='
PGW=$(docker ps --format "{{.Names}}" | grep "^gateway-akvnse3p7" | head -1)
[ -n "$PGW" ] || { echo "ERROR: prod gateway container not found"; exit 1; }
python3 - <<PYEOF
'"$script"'
PYEOF
'
  if $ON_M2; then
    bash -c "$remote_cmd"
  else
    ssh -o BatchMode=yes "$M2_SSH" bash -c "'$remote_cmd'"
  fi
}

# Simpler: docker cp a file into the gateway then exec it.
run_in_gateway_file() {
  local py="$1"
  local tmpname="/tmp/m2gw_agent_$$.py"
  if $ON_M2; then
    printf '%s' "$py" > "$tmpname"
    local PGW
    PGW=$(docker ps --format '{{.Names}}' | grep '^gateway-akvnse3p7' | head -1)
    [[ -n "$PGW" ]] || { echo "ERROR: prod gateway container not found"; rm -f "$tmpname"; exit 1; }
    docker cp "$tmpname" "$PGW:$tmpname" >/dev/null
    docker exec "$PGW" python3 "$tmpname"
    docker exec "$PGW" rm -f "$tmpname" || true
    rm -f "$tmpname"
  else
    ssh -o BatchMode=yes "$M2_SSH" \
      "cat > $tmpname && PGW=\$(docker ps --format '{{.Names}}' | grep '^gateway-akvnse3p7' | head -1) && \
       docker cp $tmpname \$PGW:$tmpname >/dev/null && docker exec \$PGW python3 $tmpname && \
       docker exec \$PGW rm -f $tmpname && rm -f $tmpname" <<<"$py"
  fi
}

# ---------- 1. tenant (idempotent) ----------
echo ">> [1/4] ensure tenant '$SLUG'"
TENANT_PY="import os, asyncio, asyncpg
SLUG, ROUTE, BUDGET, RETENTION, PRINCIPAL = '$SLUG', '$PRIMARY_ROUTE', $BUDGET_USD, $RETENTION_DAYS, '$PRINCIPAL'
async def main():
    URL = os.environ['M2GW_DATABASE_URL'].replace('postgresql+asyncpg://', 'postgresql://')
    c = await asyncpg.connect(URL)
    exists = await c.fetchval('select 1 from tenants where id=\$1', SLUG)
    if exists:
        print(f'   tenant {SLUG} already exists')
    else:
        await c.execute(
            \"\"\"insert into tenants (id, display_name, default_retention_days,
               default_budget_monthly_usd, default_route_id, status, created_by,
               rate_limit_per_minute, compaction_policy)
               values (\$1, \$1, \$2, \$3, \$4, 'active', \$5, 60, '{}')\"\"\",
            SLUG, RETENTION, BUDGET, ROUTE, PRINCIPAL,
        )
        print(f'   created tenant {SLUG} (default_route={ROUTE}, budget=\${BUDGET}/mo, retention={RETENTION}d)')
    await c.close()
asyncio.run(main())
"
run_in_gateway_file "$TENANT_PY"

# ---------- 2. agent (idempotent — update route bindings if it exists) ----------
echo ">> [2/4] ensure agent '$SLUG' with route chain [${PRIMARY_ROUTE}${FALLBACK_ROUTE:+, ${FALLBACK_ROUTE}}${EXTRA_FALLBACK:+, ${EXTRA_FALLBACK}}]"
CHAIN_JSON="[{\"route_id\":\"$PRIMARY_ROUTE\",\"priority\":1}"
[[ -n "$FALLBACK_ROUTE" ]] && CHAIN_JSON="$CHAIN_JSON,{\"route_id\":\"$FALLBACK_ROUTE\",\"priority\":2}"
[[ -n "$EXTRA_FALLBACK" ]] && CHAIN_JSON="$CHAIN_JSON,{\"route_id\":\"$EXTRA_FALLBACK\",\"priority\":3}"
CHAIN_JSON="$CHAIN_JSON]"

AGENT_PY="import os, asyncio, asyncpg, json
SLUG, PRINCIPAL, CHAIN = '$SLUG', '$PRINCIPAL', json.loads('''$CHAIN_JSON''')
TOOLS = ['m2.memory.query', 'm2.memory.write']
async def main():
    URL = os.environ['M2GW_DATABASE_URL'].replace('postgresql+asyncpg://', 'postgresql://')
    c = await asyncpg.connect(URL)
    exists = await c.fetchval('select 1 from agents where id=\$1', SLUG)
    if exists:
        await c.execute('update agents set route_bindings=\$1::jsonb, principal_ref=\$2 where id=\$3',
                        json.dumps(CHAIN), PRINCIPAL, SLUG)
        print(f'   updated agent {SLUG} chain={[b[\"route_id\"] for b in CHAIN]}')
    else:
        await c.execute(
            \"\"\"insert into agents (id, tenant_id, principal_ref, subconscious_tools,
               route_bindings, config_version, status, subconscious_config)
               values (\$1, \$1, \$2, \$3::jsonb, \$4::jsonb, 'v1', 'active', '{}'::jsonb)\"\"\",
            SLUG, PRINCIPAL, json.dumps(TOOLS), json.dumps(CHAIN),
        )
        print(f'   created agent {SLUG} chain={[b[\"route_id\"] for b in CHAIN]}')
    await c.close()
asyncio.run(main())
"
run_in_gateway_file "$AGENT_PY"

# ---------- 3. bearer (always mint fresh) ----------
echo ">> [3/4] mint bearer for '$SLUG'"
MINT_PY="import os, asyncio, asyncpg, uuid, sys
from gateway.admin_api.keys import _generate_bearer_key, _hash_bearer, _compute_lookup_idx
SLUG = '$SLUG'
async def main():
    URL = os.environ['M2GW_DATABASE_URL'].replace('postgresql+asyncpg://', 'postgresql://')
    c = await asyncpg.connect(URL)
    row = await c.fetchrow('select id, tenant_id from agents where id=\$1', SLUG)
    if not row:
        print(f'ERROR: agent \\\"{SLUG}\\\" not found', file=sys.stderr); await c.close(); sys.exit(1)
    raw = _generate_bearer_key()
    kid = str(uuid.uuid4())
    await c.execute(
        'insert into api_keys (id, tenant_id, agent_id, bearer_hash, bearer_lookup_idx, status) '
        \"values (\$1, \$2, \$3, \$4, \$5, 'active')\",
        kid, row['tenant_id'], SLUG, _hash_bearer(raw), _compute_lookup_idx(raw),
    )
    print(f'BEARER={raw}')
    print(f'KEY_ID={kid}')
    await c.close()
asyncio.run(main())
"
MINT_OUT="$(run_in_gateway_file "$MINT_PY")"
echo "$MINT_OUT"
BEARER="$(printf '%s\n' "$MINT_OUT" | awk -F= '/^BEARER=/{print $2; exit}')"
KEY_ID="$(printf '%s\n' "$MINT_OUT" | awk -F= '/^KEY_ID=/{print $2; exit}')"
[[ -n "$BEARER" ]] || { echo "ERROR: mint failed"; exit 1; }

# ---------- 4. Hermes wire (optional) ----------
if $SKIP_HERMES; then
  echo ">> [4/4] --skip-hermes — done"
else
  [[ -z "$HERMES_CONTAINER" ]] && HERMES_CONTAINER="${SLUG}-m2o"
  if ! docker inspect "$HERMES_CONTAINER" >/dev/null 2>&1; then
    echo ">> [4/4] container '$HERMES_CONTAINER' not on this host — copy the bearer manually"
    echo "   (or re-run with --hermes-container <name> on the host where the desktop lives)"
  else
    echo ">> [4/4] wire Hermes in container '$HERMES_CONTAINER'"
    docker exec "$HERMES_CONTAINER" bash -c "
set -e
cd /home/developer/.hermes
cp config.yaml config.yaml.bak.\$(date +%s)
python3 - <<PY
import re, pathlib
p = pathlib.Path('config.yaml')
s = p.read_text()
s = re.sub(r'^(  default:\s*).*\$', r'\1$DEFAULT_MODEL', s, count=1, flags=re.M)
s = re.sub(r'^(  api_key:\s*).*\$', r'\1$BEARER', s, count=1, flags=re.M)
p.write_text(s)
print('  Hermes config.yaml patched (model.default + model.api_key)')
PY
supervisorctl restart hermes-gateway >/dev/null
sleep 2
supervisorctl status hermes-gateway | tr -s ' '
"
  fi
fi

# ---------- summary ----------
cat <<EOF

>> DONE — tenant + agent + bearer for '$SLUG' on gpt.machinemachine.ai

  tenant             $SLUG
  agent              $SLUG   (principal=$PRINCIPAL)
  route chain        ${PRIMARY_ROUTE}${FALLBACK_ROUTE:+  →  ${FALLBACK_ROUTE}}${EXTRA_FALLBACK:+  →  ${EXTRA_FALLBACK}}
  default model      $DEFAULT_MODEL
  key_id             $KEY_ID
  bearer             $BEARER
                     ^^ save this now — the raw key is NOT stored (argon2-hashed at rest)
EOF
if ! $SKIP_HERMES && docker inspect "${HERMES_CONTAINER:-${SLUG}-m2o}" >/dev/null 2>&1; then
  echo "  Hermes             config.yaml on ${HERMES_CONTAINER:-${SLUG}-m2o} updated, hermes-gateway restarted"
fi
