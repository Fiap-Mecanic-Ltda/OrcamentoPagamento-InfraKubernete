#!/usr/bin/env bash
# Deploy do overlay local no cluster criado por scripts/cluster-local.sh.
#
#   scripts/deploy-local.sh [caminho-do-OrcamentoPagamento-service]
#
# 1. Constrói a imagem da API a partir do Dockerfile do serviço.
# 2. Importa as imagens no containerd do k3s (o cluster não enxerga o Docker do host).
# 3. Cria o Secret a partir do .env deste repositório (ou do arquivo em ENV_FILE).
# 4. Aplica k8s/overlays/local e espera tudo ficar pronto.
set -euo pipefail
export MSYS_NO_PATHCONV=1

# Caminho absoluto. No Git Bash (Windows), `pwd -W` devolve C:/..., formato que o
# docker.exe e o kubectl.exe entendem mesmo com MSYS_NO_PATHCONV; fora dele, pwd normal.
absoluto() { (cd "$1" && (pwd -W 2>/dev/null || pwd)); }

RAIZ="$(absoluto "$(dirname "$0")/..")"
SERVICO="$(absoluto "${1:-$RAIZ/../OrcamentoPagamento-service}" 2>/dev/null || echo "${1:-}")"
NOME="${K3S_CONTAINER:-orcamento-k3s}"
NS=orcamento
export KUBECONFIG="${KUBECONFIG:-$RAIZ/.kube/config}"
# Git Bash: KUBECONFIG=/c/... não é convertido com MSYS_NO_PATHCONV e o kubectl.exe não o acha.
command -v cygpath >/dev/null 2>&1 && KUBECONFIG="$(cygpath -m "$KUBECONFIG")"

ENV_FILE="${ENV_FILE:-$RAIZ/.env}"
[ -f "$ENV_FILE" ] || { echo "Crie $ENV_FILE a partir de .env.example" >&2; exit 1; }
[ -f "$SERVICO/src/OrcamentoPagamento.API/Dockerfile" ] || {
  echo "Não encontrei o OrcamentoPagamento-service em $SERVICO" >&2; exit 1; }

set -a; . "$ENV_FILE"; set +a
: "${SA_PASSWORD:?SA_PASSWORD vazio no .env}"
: "${JWT_SECRET_KEY:?JWT_SECRET_KEY vazio no .env}"

echo "==> Construindo orcamento-api:latest"
docker build -t orcamento-api:latest -f "$SERVICO/src/OrcamentoPagamento.API/Dockerfile" "$SERVICO"

echo "==> Importando imagens no k3s"
# --platform: com o image store do containerd, `docker save` de uma imagem multiplataforma
# exporta o índice inteiro sem os blobs das outras arquiteturas, e o import falha.
PLATAFORMA="linux/$(docker exec "$NOME" uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"

importar() {
  docker save --platform "$PLATAFORMA" "$1" | docker exec -i "$NOME" ctr -n k8s.io images import - >/dev/null
}

echo "    orcamento-api:latest"
importar orcamento-api:latest

# Imagens de terceiros: importa a cópia do host se existir (evita baixar ~2 GB do SQL
# Server de novo). Se não existir ou o import falhar, o k3s baixa sozinho na subida.
for img in mcr.microsoft.com/mssql/server:2022-latest localstack/localstack:3 busybox:1.36; do
  if docker image inspect "$img" >/dev/null 2>&1; then
    echo "    $img"
    importar "$img" || echo "      (falhou; o k3s vai baixar do registry)"
  fi
done

echo "==> Secret orcamento-secrets"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create secret generic orcamento-secrets -n "$NS" \
  --from-literal=SA_PASSWORD="$SA_PASSWORD" \
  --from-literal=JWT_SECRET_KEY="$JWT_SECRET_KEY" \
  --from-literal=ConnectionStrings__DefaultConnection="Server=orcamento-sqlserver;Database=${ORCAMENTO_DB_NOME:-MechanicOrcamentoDb};User Id=sa;Password=${SA_PASSWORD};TrustServerCertificate=True;" \
  --from-literal=MERCADOPAGO_ACCESS_TOKEN="${MERCADOPAGO_ACCESS_TOKEN:-}" \
  --from-literal=MERCADOPAGO_WEBHOOK_SECRET="${MERCADOPAGO_WEBHOOK_SECRET:-}" \
  --from-literal=MERCADOPAGO_NOTIFICATION_URL="${MERCADOPAGO_NOTIFICATION_URL:-}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "==> Aplicando k8s/overlays/local"
# O overlay remove o Secret placeholder da base, então o criado acima não é sobrescrito.
kubectl apply -k "$RAIZ/k8s/overlays/local"

# Imagem com a mesma tag "latest": sem restart o pod continuaria com o binário antigo.
kubectl rollout restart deployment/orcamento-api -n "$NS" >/dev/null

echo "==> Aguardando os pods"
kubectl rollout status deployment/orcamento-sqlserver -n "$NS" --timeout=300s
kubectl rollout status deployment/orcamento-localstack -n "$NS" --timeout=300s
kubectl rollout status deployment/orcamento-api -n "$NS" --timeout=420s

kubectl get pods,svc,hpa -n "$NS"
echo
echo "API:  kubectl port-forward -n $NS svc/orcamento-api 8082:8080   ->  http://localhost:8082/health"
