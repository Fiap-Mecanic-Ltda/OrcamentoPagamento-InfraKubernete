# Topologia de mensageria, a mesma que o LocalStack monta no ambiente local
# (k8s/overlays/local/localstack/01-criar-topico-e-fila.sh):
#
#   ordem-servico-eventos (SNS) --> ordem-servico-itens-alterados (SQS) --> DLQ
#   orcamento-eventos     (SNS) <-- publicado por este microsservico
#
# O topico ordem-servico-eventos e publicado pelo monolito, mas nasce aqui: o
# unico assinante hoje e o orcamento, e o monolito so precisa do ARN (output
# ordem_servico_topic_arn / parametro no SSM).

resource "aws_sns_topic" "ordem_servico_eventos" {
  name = "${var.project_name}-${var.environment}-ordem-servico-eventos"

  # Criptografia em repouso com a chave gerenciada da AWS.
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic" "orcamento_eventos" {
  name              = "${local.name_prefix}-eventos"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sqs_queue" "itens_alterados_dlq" {
  name                      = "${var.project_name}-${var.environment}-ordem-servico-itens-alterados-dlq"
  message_retention_seconds = var.sqs_dlq_retention_seconds
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "itens_alterados" {
  name                       = "${var.project_name}-${var.environment}-ordem-servico-itens-alterados"
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  # Long polling do lado da fila, alem do que o consumidor ja pede.
  receive_wait_time_seconds = 20
  sqs_managed_sse_enabled   = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.itens_alterados_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })
}

# So a DLQ desta fila pode receber o redrive dela.
resource "aws_sqs_queue_redrive_allow_policy" "itens_alterados_dlq" {
  queue_url = aws_sqs_queue.itens_alterados_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.itens_alterados.arn]
  })
}

data "aws_iam_policy_document" "itens_alterados_from_sns" {
  statement {
    sid     = "SnsOrdemServicoEnvia"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    resources = [aws_sqs_queue.itens_alterados.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.ordem_servico_eventos.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "itens_alterados" {
  queue_url = aws_sqs_queue.itens_alterados.id
  policy    = data.aws_iam_policy_document.itens_alterados_from_sns.json
}

# raw_message_delivery entrega o JSON do evento puro, sem o envelope do SNS (o
# consumidor aceita os dois). O filtro deixa passar so o tipo que o servico
# trata - outros eventos da OS nao ocupam a fila nem vao parar na DLQ.
resource "aws_sns_topic_subscription" "itens_alterados" {
  topic_arn            = aws_sns_topic.ordem_servico_eventos.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.itens_alterados.arn
  raw_message_delivery = true

  filter_policy = jsonencode({
    tipoEvento = ["ordem-servico.itens-alterados"]
  })

  depends_on = [aws_sqs_queue_policy.itens_alterados]
}
