output "ecr_repository_url" {
  value = aws_ecr_repository.orcamento.repository_url
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
