# O servico roda no k3s do monolito. Rede, nos, ALB e roles pertencem ao
# InfraKubernete de la; este stack le os outputs do state remoto (so leitura,
# nao trava nem grava o state do outro repositorio) e so acrescenta o que e
# do orcamento.
data "terraform_remote_state" "kubernetes" {
  backend = "s3"

  config = {
    bucket = var.kubernetes_state_bucket
    key    = var.kubernetes_state_key
    region = var.aws_region
  }
}

data "aws_caller_identity" "current" {}

locals {
  cluster = data.terraform_remote_state.kubernetes.outputs

  vpc_id           = local.cluster.vpc_id
  server_id        = local.cluster.ec2_instance_id
  alb_listener_arn = local.cluster.alb_listener_arn

  name_prefix = "${var.project_name}-${var.environment}-${var.service_name}"

  # Os parametros do servico ficam num subprefixo do prefixo do monolito: as
  # roles da EC2 e do GitHub Actions ja leem /projeto/ambiente/*, entao nao
  # precisam de policy nova para isso.
  ssm_cluster_prefix = "/${var.project_name}/${var.environment}"
  ssm_path_prefix    = "${local.ssm_cluster_prefix}/${var.service_name}"

  # Nomes fixos definidos no iam.tf / github_oidc.tf do monolito. O state de la
  # nao exporta as roles, e o nome e deterministico.
  ec2_role_name            = "${var.project_name}-${var.environment}-ec2-role"
  worker_role_name         = "${var.project_name}-${var.environment}-worker-role"
  github_actions_role_name = "${var.project_name}-${var.environment}-github-actions"
}

data "aws_iam_role" "ec2" {
  name = local.ec2_role_name
}

data "aws_iam_role" "worker" {
  name = local.worker_role_name
}

data "aws_iam_role" "github_actions" {
  name = local.github_actions_role_name
}
