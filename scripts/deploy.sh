#!/usr/bin/env bash
# Install Gleipnir on the Thor as a Decky plugin (needs passwordless sudo or a sudo prompt on the Thor).
# Host: arg 1, $THOR_HOST, $THOR_ENV_FILE, ./local/thor.env or ../../local/thor.env (through the AynThor plugins/ junction).
set -euo pipefail
_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${THOR_HOST:-}" ]; then
    for _f in "${THOR_ENV_FILE:-}" "${_ROOT}/local/thor.env" "${_ROOT}/../../local/thor.env"; do
        if [ -n "$_f" ] && [ -f "$_f" ]; then THOR_HOST="$(sed -n 's/^THOR_HOST=//p' "$_f" | head -1)"; break; fi
    done
fi
THOR_HOST="${1:-${THOR_HOST:-}}"
[ -n "$THOR_HOST" ] || { echo "ERROR: no Thor host. Pass it as arg 1, set THOR_HOST, or fill local/thor.env." >&2; exit 2; }
PLUGIN_DIR="/home/armada/homebrew/plugins/gleipnir"
cd "$_ROOT"
bash -n bin/gleipnir
echo "==> Copying Gleipnir to ${THOR_HOST}:${PLUGIN_DIR}"
ssh "${THOR_HOST}" "rm -rf /tmp/gleipnir-stage && mkdir -p /tmp/gleipnir-stage/bin /tmp/gleipnir-stage/systemd /tmp/gleipnir-stage/dist"
scp plugin.json package.json main.py LICENSE "${THOR_HOST}:/tmp/gleipnir-stage/"
scp bin/gleipnir "${THOR_HOST}:/tmp/gleipnir-stage/bin/"
scp systemd/gleipnir.service "${THOR_HOST}:/tmp/gleipnir-stage/systemd/"
scp dist/index.js "${THOR_HOST}:/tmp/gleipnir-stage/dist/"
ssh "${THOR_HOST}" "
    sudo mkdir -p '${PLUGIN_DIR}' &&
    sudo cp -r /tmp/gleipnir-stage/. '${PLUGIN_DIR}/' &&
    sudo chown -R root:root '${PLUGIN_DIR}' && sudo chmod -R u=rwX,go=rX '${PLUGIN_DIR}' && sudo chmod 755 '${PLUGIN_DIR}/bin/gleipnir' &&
    rm -rf /tmp/gleipnir-stage &&
    sudo systemctl restart plugin_loader.service
"
echo "==> Done. Open the Steam menu > Decky > Gleipnir, press Install, then run the safety test with the charger plugged in."
