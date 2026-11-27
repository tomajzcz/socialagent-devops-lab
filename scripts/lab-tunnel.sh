#!/usr/bin/env bash
# One SSH connection to the lab server carries everything that is not public:
#   localhost:6443  Kubernetes API
#   localhost:9090  Prometheus
#   localhost:3000  Grafana
#   localhost:9093  Alertmanager
# It runs in the background, so no terminal has to stay open.
# Needs the monitoring stack (k8s/monitoring). Before it is installed, open
# only the API tunnel by hand: ssh -N -L 6443:127.0.0.1:6443 <admin user>@<server>
#
# Usage, from anywhere: scripts/lab-tunnel.sh up | status | down
set -euo pipefail
cd "$(dirname "$0")/.."

# KUBECONFIG and LAB_SERVER_IP.
# shellcheck source=/dev/null
source .env

ADMIN_USER=$(awk -F'"' '/^admin_user:/ {print $2}' ansible/group_vars/all.yml)
TARGET="$ADMIN_USER@$LAB_SERVER_IP"
# Control socket of the background connection. ~/.ssh is readable only by its owner.
SOCKET="$HOME/.ssh/socialagent-lab.sock"

# Local port, Service in the monitoring namespace, Service port.
FORWARDS="9090 monitoring-kube-prometheus-prometheus 9090
3000 monitoring-grafana 80
9093 monitoring-kube-prometheus-alertmanager 9093"

connected() { ssh -S "$SOCKET" -O check "$TARGET" 2>/dev/null; }

up() {
  if connected; then
    echo "Already connected."
    status
    return
  fi
  rm -f "$SOCKET" # left behind if the connection died uncleanly
  for port in 6443 9090 3000 9093; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "Port $port is already in use: close the old tunnel or port-forward first." >&2
      exit 1
    fi
  done

  # -M -S: a master connection that later ssh commands control through the socket.
  # -f -N: go to the background once connected, run no remote command.
  # BatchMode: fail instead of asking for the key passphrase (run ssh-add first).
  ssh -M -S "$SOCKET" -f -N \
    -o BatchMode=yes -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -L 6443:127.0.0.1:6443 "$TARGET"

  # The node reaches Services by their ClusterIP, so the same connection can
  # carry them: no kubectl port-forward, and pod restarts do not break it.
  while read -r local_port service service_port; do
    ip=$(kubectl -n monitoring get service "$service" -o jsonpath='{.spec.clusterIP}' --request-timeout=10s)
    ssh -S "$SOCKET" -O forward -L "$local_port:$ip:$service_port" "$TARGET" </dev/null
  done <<<"$FORWARDS"

  echo "Connected."
  status
  echo
  echo "Grafana user: admin. Password to the clipboard:"
  echo "  security find-generic-password -a \"\$USER\" -s socialagent-lab-grafana -w | pbcopy"
}

# Prints OK or FAIL for one endpoint.
check() {
  if "${@:2}" >/dev/null 2>&1; then
    printf '  %-28s OK\n' "$1"
  else
    printf '  %-28s FAIL\n' "$1"
  fi
}

status() {
  if ! connected; then
    echo "Not connected. Run: scripts/lab-tunnel.sh up"
    return 1
  fi
  check "Kubernetes API  :6443" kubectl get --raw=/readyz --request-timeout=5s
  check "Prometheus      :9090" curl -sf --max-time 5 http://localhost:9090/-/ready
  check "Grafana         :3000" curl -sf --max-time 5 http://localhost:3000/api/health
  check "Alertmanager    :9093" curl -sf --max-time 5 http://localhost:9093/-/ready
}

down() {
  if connected; then
    ssh -S "$SOCKET" -O exit "$TARGET" 2>/dev/null
    echo "Disconnected."
  else
    rm -f "$SOCKET"
    echo "Not connected."
  fi
}

case "${1:-}" in
  up) up ;;
  status) status ;;
  down) down ;;
  *)
    echo "Usage: $0 up | status | down" >&2
    exit 2
    ;;
esac
