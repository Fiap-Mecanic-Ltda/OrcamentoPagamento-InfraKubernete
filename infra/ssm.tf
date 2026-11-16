# Tudo o que o deploy precisa saber sobre a infra do servico fica no SSM, no
# prefixo /projeto/ambiente/orcamento. A pipeline (.github/workflows/deploy.yml)
# le daqui para montar o ConfigMap e o Secret, sem hardcodar ARN nem segredo.
#
# Outros parametros do mesmo prefixo, criados em outros repositorios:
#   db-connection-string  -> OrcamentoPagamento-InfraSGBD (RDS)
# E do prefixo do monolito, reaproveitado:
#   /projeto/ambiente/jwt-secret-key -> mesma chave que valida os tokens

resource "aws_ssm_parameter" "topico_eventos_arn" {
  name  = "${local.ssm_path_prefix}/topico-eventos-arn"
  type  = "String"
  value = aws_sns_topic.orcamento_eventos.arn
}

resource "aws_ssm_parameter" "fila_itens_alterados_url" {
  name  = "${local.ssm_path_prefix}/fila-itens-alterados-url"
  type  = "String"
  value = aws_sqs_queue.itens_alterados.id
}

# Para o monolito publicar os eventos de itens alterados.
resource "aws_ssm_parameter" "ordem_servico_topic_arn" {
  name  = "${local.ssm_cluster_prefix}/ordem-servico-eventos-arn"
  type  = "String"
  value = aws_sns_topic.ordem_servico_eventos.arn
}

# Mercado Pago: so existem quando informados. Sem o access token, o deploy
# mantem Pagamentos__Habilitado=false (gateway fake). nonsensitive() so no
# teste de vazio - o valor continua sensivel.

resource "aws_ssm_parameter" "mercadopago_access_token" {
  count = nonsensitive(var.mercadopago_access_token != "") ? 1 : 0

  name  = "${local.ssm_path_prefix}/mercadopago-access-token"
  type  = "SecureString"
  value = var.mercadopago_access_token
}

resource "aws_ssm_parameter" "mercadopago_webhook_secret" {
  count = nonsensitive(var.mercadopago_webhook_secret != "") ? 1 : 0

  name  = "${local.ssm_path_prefix}/mercadopago-webhook-secret"
  type  = "SecureString"
  value = var.mercadopago_webhook_secret
}

resource "aws_ssm_parameter" "mercadopago_notification_url" {
  count = var.mercadopago_notification_url != "" ? 1 : 0

  name  = "${local.ssm_path_prefix}/mercadopago-notification-url"
  type  = "String"
  value = var.mercadopago_notification_url
}
