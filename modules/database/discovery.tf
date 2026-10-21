# Contrato de descoberta: tudo que os outros repositórios precisam saber sobre o
# banco sai por aqui, num path previsível. A alternativa — copiar o endpoint na
# mão para um Secret do Kubernetes e para a variável da Lambda — é a que garante
# que os três lugares divirjam na primeira mudança.
#
# O consumidor lê por PATH, nunca por remote state: assim ninguém precisa de
# acesso ao state deste repositório, que guarda a senha em texto claro.

resource "aws_ssm_parameter" "db_endpoint" {
  name        = "${local.ssm_prefix}/endpoint"
  description = "Endpoint do Postgres de ${var.environment} (host:porta)"
  type        = "String"
  value       = module.rds.db_instance_endpoint
  tags        = local.tags
}

resource "aws_ssm_parameter" "db_host" {
  name        = "${local.ssm_prefix}/host"
  description = "Host do Postgres de ${var.environment}, sem a porta"
  type        = "String"
  value       = module.rds.db_instance_address
  tags        = local.tags
}

resource "aws_ssm_parameter" "db_port" {
  name  = "${local.ssm_prefix}/port"
  type  = "String"
  value = tostring(module.rds.db_instance_port)
  tags  = local.tags
}

resource "aws_ssm_parameter" "db_name" {
  name  = "${local.ssm_prefix}/name"
  type  = "String"
  value = var.db_name
  tags  = local.tags
}

resource "aws_ssm_parameter" "db_username" {
  name  = "${local.ssm_prefix}/username"
  type  = "String"
  value = var.db_username
  tags  = local.tags
}

# O id do SG de cliente é publicado para que o repositório de Kubernetes anexe
# aos nós e o da Lambda anexe à função — sem que nenhum dos dois precise
# conhecer o security group do banco.
resource "aws_ssm_parameter" "db_client_sg_id" {
  name        = "${local.ssm_prefix}/client-sg-id"
  description = "Security group a ANEXAR em quem precisa falar com o banco de ${var.environment}"
  type        = "String"
  value       = aws_security_group.db_client.id
  tags        = local.tags
}
