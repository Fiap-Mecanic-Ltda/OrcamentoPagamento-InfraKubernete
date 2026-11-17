#!/usr/bin/env bash
# Cluster Kubernetes local: k3s (a mesma distribuição da produção) rodando dentro de um
# container Docker. Só precisa de Docker — sem kind, minikube nem Docker Desktop Kubernetes.
#
#   scripts/cluster-local.sh up       cria/inicia o cluster e grava .kube/config
#   scripts/cluster-local.sh down     remove o cluster (e tudo o que estava nele)
#   scripts/cluster-local.sh status
#
# Depois do "up":  export KUBECONFIG="$PWD/.kube/config"
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash no Windows: não converter /etc/... em caminho do Windows

NOME="${K3S_CONTAINER:-orcamento-k3s}"
IMAGEM="${K3S_IMAGEM:-rancher/k3s:v1.31.4-k3s1}"
PORTA="${K3S_PORTA_API:-6445}"   # 6443 fica livre para outro cluster
# No Git Bash (Windows), `pwd -W` devolve C:/..., que o kubectl.exe entende; fora dele, pwd.
RAIZ="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
KUBECONFIG_ARQ="$RAIZ/.kube/config"

up() {
  if docker ps -a --format '{{.Names}}' | grep -qx "$NOME"; then
    docker start "$NOME" >/dev/null
    echo "Cluster $NOME iniciado."
  else
    echo "Criando cluster $NOME ($IMAGEM)..."
    # privileged: o k3s precisa gerenciar cgroups e montar volumes dos pods.
    # traefik desligado: a API é exposta por port-forward / NodePort.
    docker run -d --name "$NOME" --privileged --restart unless-stopped \
      -p "$PORTA:6443" \
      "$IMAGEM" server --disable traefik --tls-san 127.0.0.1 --write-kubeconfig-mode 644 >/dev/null
  fi

  echo -n "Aguardando o nó ficar Ready"
  for _ in $(seq 1 60); do
    if docker exec "$NOME" kubectl get nodes 2>/dev/null | grep -q " Ready"; then
      echo " ok"; break
    fi
    echo -n "."; sleep 3
  done

  mkdir -p "$(dirname "$KUBECONFIG_ARQ")"
  docker exec "$NOME" cat /etc/rancher/k3s/k3s.yaml \
    | sed "s#https://127.0.0.1:6443#https://127.0.0.1:$PORTA#" > "$KUBECONFIG_ARQ"

  echo "kubeconfig gravado em $KUBECONFIG_ARQ"
  echo "Use:  export KUBECONFIG=\"$KUBECONFIG_ARQ\""
}

down() {
  docker rm -f "$NOME" >/dev/null 2>&1 && echo "Cluster $NOME removido." || echo "Cluster $NOME não existe."
  rm -f "$KUBECONFIG_ARQ"
}

status() {
  docker ps -a --filter "name=^${NOME}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  [ -f "$KUBECONFIG_ARQ" ] && KUBECONFIG="$KUBECONFIG_ARQ" kubectl get nodes || true
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  status) status ;;
  *) echo "uso: $0 up|down|status" >&2; exit 2 ;;
esac
