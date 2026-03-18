#!/bin/bash
# Deploy netmeta-mcp and netmeta-verify-mcp to biostatistics.med.auth.gr
#
# Usage:
#   ./deploy/deploy.sh [user@host]
#
# Default: deploys to biostatistics.med.auth.gr
#
# Prerequisites on the remote server:
#   - Docker and docker compose installed
#   - Nginx installed and configured for the domain
#   - SSH access

set -euo pipefail

REMOTE="${1:-biostatistics.med.auth.gr}"
REMOTE_DIR="/opt/netmeta-mcp"

echo "=== Deploying netmeta-mcp + netmeta-verify-mcp to ${REMOTE} ==="

# ------------------------------------------------------------------
# Step 1: Build both Docker images locally
# ------------------------------------------------------------------
echo ""
echo "[1/4] Building Docker images..."
docker build -t netmeta-mcp:latest .
docker build -f Dockerfile.verify -t netmeta-verify-mcp:latest .

# ------------------------------------------------------------------
# Step 2: Save, compress and transfer both images
# ------------------------------------------------------------------
echo ""
echo "[2/4] Saving and transferring Docker images..."

docker save netmeta-mcp:latest | gzip > /tmp/netmeta-mcp.tar.gz
echo "  netmeta-mcp size:        $(du -h /tmp/netmeta-mcp.tar.gz | cut -f1)"

docker save netmeta-verify-mcp:latest | gzip > /tmp/netmeta-verify-mcp.tar.gz
echo "  netmeta-verify-mcp size: $(du -h /tmp/netmeta-verify-mcp.tar.gz | cut -f1)"

scp /tmp/netmeta-mcp.tar.gz        "${REMOTE}:/tmp/netmeta-mcp.tar.gz"
scp /tmp/netmeta-verify-mcp.tar.gz "${REMOTE}:/tmp/netmeta-verify-mcp.tar.gz"

rm /tmp/netmeta-mcp.tar.gz /tmp/netmeta-verify-mcp.tar.gz

# ------------------------------------------------------------------
# Step 3: Load images and start containers on remote
# ------------------------------------------------------------------
echo ""
echo "[3/4] Loading images and starting containers on remote..."

ssh "${REMOTE}" bash -s <<'REMOTE_SCRIPT'
set -euo pipefail

echo "  Loading netmeta-mcp..."
docker load < /tmp/netmeta-mcp.tar.gz
rm /tmp/netmeta-mcp.tar.gz

echo "  Loading netmeta-verify-mcp..."
docker load < /tmp/netmeta-verify-mcp.tar.gz
rm /tmp/netmeta-verify-mcp.tar.gz

sudo mkdir -p /opt/netmeta-mcp
REMOTE_SCRIPT

# Copy compose file to remote
scp docker-compose.yml "${REMOTE}:${REMOTE_DIR}/docker-compose.yml"

# Start / restart containers
ssh "${REMOTE}" bash -s <<REMOTE_SCRIPT
set -euo pipefail
cd ${REMOTE_DIR}

docker compose down 2>/dev/null || true
docker compose up -d

echo "  Waiting for health checks..."
sleep 8
docker compose ps
REMOTE_SCRIPT

# ------------------------------------------------------------------
# Step 4: Nginx configuration
# ------------------------------------------------------------------
echo ""
echo "[4/4] Nginx configuration..."

scp deploy/nginx-netmeta-mcp.conf "${REMOTE}:/tmp/nginx-netmeta-mcp.conf"

ssh "${REMOTE}" bash -s <<'REMOTE_SCRIPT'
set -euo pipefail

NGINX_CONF="/etc/nginx/conf.d/netmeta-mcp.conf"
if [ ! -f "${NGINX_CONF}" ]; then
    sudo cp /tmp/nginx-netmeta-mcp.conf "${NGINX_CONF}"
    echo "  Nginx config installed. Testing..."
    sudo nginx -t && sudo nginx -s reload
    echo "  Nginx reloaded."
else
    echo "  Nginx config already exists at ${NGINX_CONF}"
    echo "  Compare with /tmp/nginx-netmeta-mcp.conf and update manually if needed."
fi
rm -f /tmp/nginx-netmeta-mcp.conf
REMOTE_SCRIPT

echo ""
echo "=== Deployment complete ==="
echo ""
echo "  NMA server:    https://biostatistics.med.auth.gr/mcp/netmeta"
echo "  Verify server: https://biostatistics.med.auth.gr/mcp/netmeta-verify"
echo ""
echo "Test NMA server:"
echo "  curl -X POST https://biostatistics.med.auth.gr/mcp/netmeta \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"id\":1,\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"0.1.0\"}}}'"
echo ""
echo "Test Verify server:"
echo "  curl -X POST https://biostatistics.med.auth.gr/mcp/netmeta-verify \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"id\":1,\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"0.1.0\"}}}'"
