# ATENÇÃO: estes nomes são CONTRATO. Dois repositórios consomem daqui, e
# renomear um output é breaking change silencioso — o `plan` do consumidor falha
# com "Unsupported attribute", longe deste arquivo. Há teste de contrato no CI
# conferindo chave e tipo.

output "db_endpoint" {
  description = "Endpoint do RDS no formato host:porta."
  value       = module.rds.db_instance_endpoint
}

output "db_host" {
  description = "Host do RDS, sem a porta."
  value       = module.rds.db_instance_address
}

output "db_port" {
  description = "Porta do Postgres."
  value       = module.rds.db_instance_port
}

output "db_name" {
  description = "Nome do banco criado na instância."
  value       = var.db_name
}

output "db_username" {
  description = "Usuário master."
  value       = var.db_username
}

output "db_security_group_id" {
  description = "Security group do RDS. Só aceita ingress de quem carrega o SG de cliente."
  value       = aws_security_group.rds.id
}

output "db_client_security_group_id" {
  description = "Security group a ANEXAR nos nós do EKS e na Lambda para alcançar o banco."
  value       = aws_security_group.db_client.id
}

output "db_password_ssm_path" {
  description = "Path do SSM onde a senha está, como SecureString. O valor não sai daqui."
  value       = aws_ssm_parameter.db_password.name
}

output "ssm_prefix" {
  description = "Prefixo de todos os parâmetros publicados por este repositório."
  value       = local.ssm_prefix
}
