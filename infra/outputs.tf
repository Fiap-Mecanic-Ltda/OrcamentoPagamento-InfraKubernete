output "ecr_repository_url" {
  value = aws_ecr_repository.orcamento.repository_url
}

output "orcamento_eventos_topic_arn" {
  description = "Topico onde o servico publica os eventos do orcamento (Messaging:TopicoEventosArn)."
  value       = aws_sns_topic.orcamento_eventos.arn
}

output "ordem_servico_topic_arn" {
  description = "Topico onde o monolito publica as alteracoes de itens da OS."
  value       = aws_sns_topic.ordem_servico_eventos.arn
}

output "itens_alterados_queue_url" {
  description = "Fila consumida pelo servico (Messaging:FilaItensAlteradosUrl)."
  value       = aws_sqs_queue.itens_alterados.id
}

output "itens_alterados_dlq_url" {
  value = aws_sqs_queue.itens_alterados_dlq.id
}

output "target_group_arn" {
  value = aws_lb_target_group.orcamento.arn
}

output "node_port" {
  value = var.node_port
}

output "ssm_path_prefix" {
  value = local.ssm_path_prefix
}
