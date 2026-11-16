# OrcamentoPagamento-InfraKubernete

Terraform e manifestos Kubernetes do microsserviço
[OrcamentoPagamento-service](https://github.com/Fiap-Mecanic-Ltda/OrcamentoPagamento-service),
no mesmo padrão do [InfraKubernete](https://github.com/Fiap-Mecanic-Ltda/InfraKubernete) do
monólito: `terraform plan/apply` e deploy no cluster.

O serviço **não tem cluster próprio**: roda no k3s do monólito, no namespace `orcamento`.
Este repositório só acrescenta ao cluster o que é do orçamento.

- **`infra/`**: Terraform do ECR, SNS/SQS com DLQ, regra no ALB interno, policies nas roles
  dos nós e do GitHub Actions e parâmetros no SSM.
- **`k8s/overlays/local`**: desenvolvimento num cluster local, com SQL Server e LocalStack
  (SNS/SQS) como pods.
- **`k8s/overlays/prod`**: o k3s da EC2 do monólito, com o banco no RDS do
  [OrcamentoPagamento-InfraSGBD](https://github.com/Fiap-Mecanic-Ltda/OrcamentoPagamento-InfraSGBD)
  e SNS/SQS reais.

## Estrutura

```
.
├── .github/workflows/
│   ├── terraform.yml               # plan (homolog/PR) e apply (main, Environment production)
│   └── deploy.yml                  # kustomize + SSM Run Command no server k3s
├── infra/                          # Terraform (state em s3://.../prod/orcamento/terraform.tfstate)
│   ├── data.tf                     # remote state do InfraKubernete do monólito + roles existentes
│   ├── ecr.tf                      # mechanicltda-orcamento
│   ├── messaging.tf                # SNS ordem-servico-eventos -> SQS itens-alterados -> DLQ; SNS orcamento-eventos
│   ├── alb.tf                      # target group 8081 + regra /api/orcamento|pagamento|webhooks no ALB interno
│   ├── iam.tf                      # SNS/SQS/ECR para os nós; push no ECR para o GitHub Actions
│   └── ssm.tf                      # ARNs/URL da mensageria e segredos do Mercado Pago
├── k8s/
│   ├── base/                       # Namespace, ConfigMap, Secret (placeholder), API: Deployment/Service/HPA
│   └── overlays/
│       ├── local/                  # + sqlserver, + localstack (com script de init), initContainers
│       └── prod/                   # NodePort 8081, mensageria ligada, imagePullSecrets, sem Secret placeholder
├── scripts/
│   ├── cluster-local.sh            # k3s dentro de um container Docker (up | down | status)
│   ├── deploy-local.sh             # build da imagem, import no k3s, Secret a partir do .env, apply
│   └── esperar-ssm.sh              # espera um comando do SSM terminar (usado pelo deploy.yml)
└── .env.example                    # Segredos do cluster local
```

| Recurso | Onde |
|---|---|
| Namespace `orcamento`, ConfigMap `orcamento-config` | `k8s/base/` |
| Deployment/Service/HPA `orcamento-api` | `k8s/base/api-*.yaml` |
| SQL Server (pod + PVC, só local) | `k8s/overlays/local/sqlserver-*.yaml` |
| LocalStack (pod, só local) | `k8s/overlays/local/localstack-*.yaml` |
| Mensageria ligada, endpoints do LocalStack | patch do ConfigMap em `overlays/local/kustomization.yaml` |
| NodePort, ECR, `imagePullSecrets` | patches em `overlays/prod/kustomization.yaml` |

## Rodando localmente

Pré-requisito: **só Docker**. O cluster é um k3s rodando num container, a mesma distribuição
usada em produção. Ele já traz metrics-server (usado pelo HPA) e StorageClass `local-path`
(usada pelo PVC do SQL Server). Os comandos abaixo são para bash; no Windows, use o Git Bash.

Os dois repositórios precisam estar lado a lado:

```
repos/
├── OrcamentoPagamento-service/
└── OrcamentoPagamento-InfraKubernete/
```

```bash
cp .env.example .env                 # ajuste SA_PASSWORD e JWT_SECRET_KEY

scripts/cluster-local.sh up          # cria o cluster e grava .kube/config
export KUBECONFIG="$PWD/.kube/config"

scripts/deploy-local.sh              # ou: scripts/deploy-local.sh /caminho/do/OrcamentoPagamento-service
```

O `deploy-local.sh`:

1. constrói `orcamento-api:latest` a partir do Dockerfile do serviço;
2. importa essa imagem no containerd do k3s, junto com SQL Server, LocalStack e busybox se já
   existirem no Docker do host (o cluster não enxerga as imagens do host);
3. cria o Secret `orcamento-secrets` a partir do `.env`;
4. aplica `k8s/overlays/local` e espera os três Deployments ficarem prontos.

Acessando a API:

```bash
kubectl port-forward -n orcamento svc/orcamento-api 8082:8080
curl http://localhost:8082/health
```

A porta 8082 não conflita com o compose do serviço, que usa a 8081.

Acompanhando:

```bash
kubectl get pods,svc,hpa -n orcamento
kubectl logs -n orcamento deploy/orcamento-api -f
kubectl exec -n orcamento deploy/orcamento-localstack -- awslocal sqs list-queues
```

Removendo:

```bash
kubectl delete -k k8s/overlays/local    # só os recursos; o cluster continua
scripts/cluster-local.sh down           # o cluster inteiro
```

Também funciona em kind ou minikube: aponte o `KUBECONFIG` para o cluster e carregue a
imagem com `kind load docker-image orcamento-api:latest` ou `minikube image load
orcamento-api:latest`, em vez de usar o `deploy-local.sh`.

## Decisões

- **Mesma imagem, configuração por ambiente.** Tudo o que muda entre local e produção vem do
  ConfigMap e do Secret. A base deixa mensageria e pagamento real **desligados**, e cada overlay
  liga o que tem disponível.
- **Secret fora do Git.** `base/secret.yaml` só documenta as chaves esperadas. Os dois overlays
  removem esse placeholder: no local, o Secret vem do `.env` pelo `deploy-local.sh`; em
  produção, virá do SSM Parameter Store pela pipeline.
- **HPA com até 3 réplicas.** É seguro para este serviço: as migrations do EF Core 9 usam lock
  (`sp_getapplock`), então só uma réplica migra por vez; não há seed; e o consumidor SQS usa
  visibility timeout.
- **Script do LocalStack duplicado.** `overlays/local/localstack/01-criar-topico-e-fila.sh` é
  uma cópia do `scripts/localstack/` do serviço, porque o kustomize não lê arquivos fora da
  pasta do overlay. Se a topologia mudar, atualize os dois.
- **Banco no pod sem o script do InfraSGBD.** No overlay local, quem cria o banco é o EF Core,
  na primeira migration. O `READ_COMMITTED_SNAPSHOT` que o InfraSGBD liga no compose não é
  aplicado aqui.

## Produção (Terraform + deploy)

### Ordem de aplicação

Cada stack lê o anterior via `terraform_remote_state`, então a ordem importa:

| # | Repositório | O que faz |
|---|---|---|
| 1 | [InfraKubernete](https://github.com/Fiap-Mecanic-Ltda/InfraKubernete) | Cluster, ALB, roles; libera a 8081 no SG dos nós e põe os repos do orçamento no trust do OIDC |
| 2 | **este** (`terraform.yml`) | ECR, SNS/SQS, regra do ALB, policies, SSM |
| 3 | [OrcamentoPagamento-InfraSGBD](https://github.com/Fiap-Mecanic-Ltda/OrcamentoPagamento-InfraSGBD) | RDS + `db-connection-string` no SSM |
| 4 | [OrcamentoPagamento-service](https://github.com/Fiap-Mecanic-Ltda/OrcamentoPagamento-service) | Push na `main` publica a imagem e dispara o `deploy.yml` daqui |

Rodando o Terraform na mão:

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # opcional: só para o Mercado Pago real
terraform init
terraform plan
terraform apply
```

### O que é criado

| Recurso | Nome |
|---|---|
| ECR | `mechanicltda-orcamento` |
| SNS (publicado pelo monólito) | `mechanicltda-prod-ordem-servico-eventos` |
| SQS + DLQ (consumida pelo serviço) | `mechanicltda-prod-ordem-servico-itens-alterados` (+ `-dlq`, 5 tentativas) |
| SNS (publicado pelo serviço) | `mechanicltda-prod-orcamento-eventos` |
| Target group + regra no ALB interno | `/api/orcamento*`, `/api/pagamento*`, `/api/webhooks/mercadopago` → NodePort 8081 |
| Policies inline | `mechanicltda-prod-ec2-role` e `-worker-role` (SNS/SQS/ECR), `-github-actions` (push no ECR) |
| SSM `/mechanicltda/prod/orcamento/` | `topico-eventos-arn`, `fila-itens-alterados-url`, `mercadopago-*` (opcionais) |
| SSM `/mechanicltda/prod/` | `ordem-servico-eventos-arn`, para o monólito publicar |

O deploy monta o Secret `orcamento-secrets` com `db-connection-string` (do InfraSGBD),
`jwt-secret-key` (o mesmo do monólito) e os parâmetros do Mercado Pago, se existirem. Sem o
access token no SSM, o serviço sobe com `Pagamentos__Habilitado=false` (gateway fake).

### Secrets do GitHub (este repositório)

| Nome | Tipo | Uso |
|---|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | secret | `terraform.yml` (terraform-deployer) |
| `AWS_ROLE_ARN` | secret | `deploy.yml` (OIDC). Output `github_actions_role_arn` do InfraKubernete |
| `MERCADOPAGO_ACCESS_TOKEN` / `MERCADOPAGO_WEBHOOK_SECRET` | secret | opcionais |
| `MERCADOPAGO_NOTIFICATION_URL` | variable | opcional |

No **OrcamentoPagamento-service**, o `INFRA_DISPATCH_TOKEN` precisa ser um token fine-grained
com acesso a **este** repositório (Contents: read/write).

### Limitações conhecidas

- **Só o server k3s está no target group.** O kube-proxy encaminha para o pod em qualquer nó,
  então funciona; mas se a EC2 do server for recriada, rode o apply daqui de novo para
  registrar o Instance ID novo.
- **Webhook do Mercado Pago no API Gateway.** O `ANY /api/{proxy+}` do repositório Lambda
  exige JWT. Para o Mercado Pago chamar o webhook, `POST /api/webhooks/mercadopago` precisa
  entrar em `rotas_publicas` no `infra/cluster.tf` de lá.
- **Credenciais AWS no pod vêm do IMDS.** Funciona porque a AMI AL2023 usa hop limit 2. Se
  isso mudar, o SDK dentro do pod deixa de achar credenciais.
