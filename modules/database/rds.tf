resource "random_password" "db" {
  length = 32

  # O DATABASE_URL é uma URL: caracteres que exigiriam percent-encoding viram bug
  # de conexão difícil de achar, porque a senha "parece certa" no console e falha
  # só no driver.
  override_special = "-_"
}

module "rds" {
  source = "terraform-aws-modules/rds/aws"

  # Versão EXATA, não `~>`. O .terraform.lock.hcl trava PROVIDER, não MÓDULO —
  # com `~>`, um `init` numa máquina nova traria versão diferente da validada, e
  # a diferença só apareceria no plan. Bump vira PR explícito.
  version = "6.13.1"

  identifier = local.name

  engine = "postgres"
  # Mesma major do Postgres local e dos composes da aplicação (15.19-alpine):
  # paridade dev/prod é o ponto de ter ambiente local. Subir para 16 é migração
  # deliberada, não troca de linha.
  engine_version       = "15"
  family               = "postgres15"
  major_engine_version = "15"
  instance_class       = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  # Autoscaling de storage DESLIGADO: o Free Tier limita a 20 GB e crescer além
  # disso seria bloqueado pela AWS. Melhor falhar previsível em 20 GB do que no
  # meio de uma escrita.
  max_allocated_storage = 0
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  # A senha vai para o SSM por secrets.tf. Com `true`, o RDS criaria um segredo
  # próprio no Secrets Manager e os consumidores teriam DOIS lugares para
  # procurar a mesma senha.
  manage_master_user_password = false

  multi_az = false # single-AZ por custo; ver README

  # Subnets privadas: o banco não tem rota para a internet e só é alcançável de
  # dentro da VPC.
  create_db_subnet_group = true
  subnet_ids             = data.aws_subnets.private.ids
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  create_db_parameter_group = true
  parameters                = local.db_parameters

  backup_retention_period = var.backup_retention_days
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection

  # Exportar os logs é o que permite o subscription filter de observability.tf
  # enxergar alguma coisa. Sem isto, o forwarder de Datadog/New Relic assina um
  # log group que nunca recebe evento.
  enabled_cloudwatch_logs_exports        = ["postgresql", "upgrade"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 7

  performance_insights_enabled = false
  create_monitoring_role       = false

  tags = local.tags
}
