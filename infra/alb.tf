# Entrada pelo mesmo caminho do monolito:
#   API Gateway -> VPC Link -> ALB interno -> NodePort do servico
#
# O API Gateway (repositorio Lambda) ja manda todo o /api/* para o listener do
# ALB. Esta regra desvia os caminhos do orcamento e do pagamento para o
# NodePort 8083 antes da acao padrao, que segue para a API do monolito (8080).
#
# Pre-requisito no InfraKubernete do monolito: os SGs do server e dos workers
# precisam aceitar a 8083 vindo do SG do ALB (o egress do ALB ja cobre 8080-8090).

resource "aws_lb_target_group" "orcamento" {
  name        = "${var.project_name}-${var.environment}-orc-tg"
  port        = var.node_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = local.vpc_id

  # /health e anonimo e responde 200 quando o pod esta pronto.
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = {
    Name = "${local.name_prefix}-tg"
  }
}

resource "aws_lb_listener_rule" "orcamento" {
  listener_arn = local.alb_listener_arn
  priority     = var.alb_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.orcamento.arn
  }

  condition {
    path_pattern {
      values = var.alb_path_patterns
    }
  }
}

# So o server do k3s entra como alvo. O Service e NodePort, entao o kube-proxy
# do server encaminha para o pod mesmo que ele esteja num worker. Registrar os
# workers exigiria mexer no target_group_arns do ASG do monolito (um
# aws_autoscaling_attachment daqui seria desfeito no proximo apply de la).
#
# Se a EC2 do server for recriada (ex.: mudanca de user_data), rode o apply
# deste stack de novo para registrar o Instance ID novo.
resource "aws_lb_target_group_attachment" "server" {
  target_group_arn = aws_lb_target_group.orcamento.arn
  target_id        = local.server_id
  port             = var.node_port
}
