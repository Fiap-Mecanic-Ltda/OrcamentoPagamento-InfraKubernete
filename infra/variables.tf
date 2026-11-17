variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# project_name e environment precisam bater com os do InfraKubernete do
# monolito: as roles IAM e o prefixo do SSM sao derivados deles.
variable "project_name" {
  type    = string
  default = "mechanicltda"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "service_name" {
  type        = string
  description = "Nome curto do microsservico. Compoe nomes de recursos e o prefixo do SSM."
  default     = "orcamento"
}

# Cluster compartilhado: VPC, EC2/k3s, ALB e roles vem do state remoto do
# InfraKubernete do monolito (data.tf), so leitura.

variable "kubernetes_state_bucket" {
  type        = string
  description = "Bucket S3 com o state do InfraKubernete do monolito."
  default     = "mechanicltda-terraform-state-788516091173"
}

variable "kubernetes_state_key" {
  type        = string
  description = "Chave do state do InfraKubernete do monolito dentro do bucket."
  default     = "prod/terraform.tfstate"
}

# ECR

variable "ecr_repository_name" {
  type        = string
  description = "Repositorio ECR da imagem do servico. O CI do OrcamentoPagamento-service publica nele."
  default     = "mechanicltda-orcamento"
}

# Kubernetes

variable "node_port" {
  type        = number
  description = "NodePort do Service orcamento-api (k8s/overlays/prod). 8080 e 8090 sao do monolito."
  default     = 8081
}

# Rotas que o ALB interno desvia para este servico. O API Gateway manda todo o
# /api/* para o mesmo listener; sem estas regras, tudo cai no monolito.
variable "alb_path_patterns" {
  type        = list(string)
  description = "Caminhos encaminhados pelo ALB interno ao NodePort do servico (maximo 5 por regra)."
  default = [
    "/api/orcamento",
    "/api/orcamento/*",
    "/api/pagamento",
    "/api/pagamento/*",
    "/api/webhooks/mercadopago",
  ]
}

variable "alb_rule_priority" {
  type        = number
  description = "Prioridade da regra no listener do ALB interno (menor = avaliada antes)."
  default     = 10
}

# Mercado Pago. Todos opcionais: vazios, o parametro nao e criado no SSM e o
# deploy sobe o servico com o gateway de pagamento fake.

variable "mercadopago_access_token" {
  type        = string
  description = "Access token de TESTE (TEST-...) da aplicacao no Mercado Pago."
  sensitive   = true
  default     = ""
}

variable "mercadopago_webhook_secret" {
  type        = string
  description = "Secret da validacao do header x-signature do webhook."
  sensitive   = true
  default     = ""
}

variable "mercadopago_notification_url" {
  type        = string
  description = "URL publica do webhook (API Gateway + /api/webhooks/mercadopago)."
  default     = ""
}
