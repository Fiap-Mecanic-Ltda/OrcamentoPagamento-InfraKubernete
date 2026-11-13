# OrcamentoPagamento-InfraKubernete

Manifestos Kubernetes do microsserviço
[OrcamentoPagamento-service](https://github.com/Fiap-Mecanic-Ltda/OrcamentoPagamento-service),
organizados como base + overlays (Kustomize), no mesmo padrão do
[InfraKubernete](https://github.com/Fiap-Mecanic-Ltda/InfraKubernete) do monólito.

- **`overlays/local`**: desenvolvimento num cluster local, com SQL Server e LocalStack
  (SNS/SQS) como pods.
- **`overlays/prod`**: o k3s da EC2 do monólito, com o banco no RDS do
  [OrcamentoPagamento-InfraSGBD](https://github.com/Fiap-Mecanic-Ltda/OrcamentoPagamento-InfraSGBD)
  e SNS/SQS reais. **Ainda não aplicável**: depende do Terraform, que é a próxima etapa.

## Estrutura

```
.
├── k8s/
│   ├── base/                       # Namespace, ConfigMap, Secret (placeholder), API: Deployment/Service/HPA
│   └── overlays/
│       ├── local/                  # + sqlserver, + localstack (com script de init), initContainers
│       └── prod/                   # NodePort 8081, imagem do ECR, imagePullSecrets, sem Secret placeholder
├── scripts/
│   ├── cluster-local.sh            # k3s dentro de um container Docker (up | down | status)
│   └── deploy-local.sh             # build da imagem, import no k3s, Secret a partir do .env, apply
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

## Próximos passos (Terraform)

Para o `overlays/prod` funcionar:

- **ECR** `mechanicltda-orcamento`, que é o nome que o CI do serviço já usa.
- **SNS/SQS**: tópicos `ordem-servico-eventos` e `orcamento-eventos`, fila
  `ordem-servico-itens-alterados` com DLQ. As ARNs entram no ConfigMap do overlay prod, e
  `Messaging__Habilitado` passa a `"true"`.
- **Security group** da EC2 liberando a **8081**.
- **IAM** da instância com permissão de publish no SNS e de consumo da SQS.
- **Pipeline de deploy** (via SSM, como no monólito), criando o Secret a partir do SSM e o
  `ecr-creds` no namespace `orcamento`.
