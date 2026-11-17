# Os pods do k3s usam as credenciais da instancia (IMDS) - a role do server e a
# dos workers, porque o pod pode ser agendado em qualquer no. As roles sao do
# InfraKubernete do monolito; aqui so entram policies inline adicionais, como
# recursos separados (aws_iam_role_policy), que nao conflitam com o aws_iam_role
# declarado la.

data "aws_iam_policy_document" "nodes" {
  statement {
    sid    = "EcrPullOrcamento"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [aws_ecr_repository.orcamento.arn]
  }
}

resource "aws_iam_role_policy" "ec2_orcamento" {
  name   = "${local.name_prefix}-app"
  role   = data.aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.nodes.json
}

resource "aws_iam_role_policy" "worker_orcamento" {
  name   = "${local.name_prefix}-app"
  role   = data.aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.nodes.json
}

# Role do GitHub Actions (OIDC), criada no monolito. Leitura do SSM, SendCommand
# na EC2 e escrita em deploy/ no bucket ja estao la; falta o push nesta imagem.
# O trust policy precisa listar os repositorios OrcamentoPagamento-service e
# OrcamentoPagamento-InfraKubernete (variavel github_repositories do monolito).
data "aws_iam_policy_document" "github_actions" {
  statement {
    sid    = "EcrPushOrcamento"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      # O deploy descobre a tag da ultima imagem publicada.
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = [aws_ecr_repository.orcamento.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_orcamento" {
  name   = "${local.name_prefix}-github-actions"
  role   = data.aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}
