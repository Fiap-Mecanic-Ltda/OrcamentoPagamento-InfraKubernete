# Tudo o que o deploy precisa saber sobre a infra do servico fica no SSM, no
# prefixo /projeto/ambiente/orcamento. A pipeline (.github/workflows/deploy.yml)
# le daqui para montar o ConfigMap e o Secret, sem hardcodar ARN nem segredo.
#
# Outros parametros do mesmo prefixo, criados em outros repositorios:
#   db-connection-string  -> OrcamentoPagamento-InfraSGBD (RDS)
# E do prefixo do monolito (InfraKubernete), reaproveitados:
#   /projeto/ambiente/jwt-secret-key              -> mesma chave que valida os tokens
#   /projeto/ambiente/mensageria/rabbitmq-user    -> usuario do RabbitMQ do cluster
#   /projeto/ambiente/mensageria/rabbitmq-segredo -> senha do RabbitMQ do cluster
#
# A mensageria e o RabbitMQ do namespace "mensageria" (Saga da OS). SNS/SQS sairam:
# nao ha mais topico, fila nem DLQ deste servico.

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
