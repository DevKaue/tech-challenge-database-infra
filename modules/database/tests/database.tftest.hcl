# Testes do módulo `database` com `terraform test` + provider mockado.
#
# Rodam SEM credencial da AWS e sem criar nada: `mock_provider` responde a todo
# recurso e data source com valores sintéticos, e `command = plan` garante que
# nenhum apply acontece. O que se prova aqui é o que o `validate` não enxerga:
# validações das variáveis, o CONTRATO de nomes publicado no SSM, as regras de
# rede e o bloco `check` que explica a ordem de apply entre os repositórios.
#
# Rodar: cd modules/database && terraform init -backend=false && terraform test

mock_provider "aws" {}
mock_provider "random" {}

# A rede é do repositório de Kubernetes e é descoberta por tag. Aqui ela é
# fixada para o plan conseguir montar o subnet group.
override_data {
  target = data.aws_vpc.this
  values = {
    id = "vpc-0a1b2c3d4e5f60718"
  }
}

override_data {
  target = data.aws_subnets.private
  values = {
    ids = ["subnet-0aaa1111aaaa1111a", "subnet-0bbb2222bbbb2222b"]
  }
}

override_data {
  target = data.aws_region.current
  values = {
    name = "us-east-1"
  }
}

variables {
  environment = "staging"
}

run "contrato_de_descoberta_no_ssm" {
  command = plan

  # Estes paths são lidos pela Lambda (env DB_SSM_PREFIX) e pelo repositório de
  # Kubernetes. Mudar qualquer um aqui quebra os dois consumidores em silêncio.
  assert {
    condition     = output.ssm_prefix == "/techchallenge/staging/db"
    error_message = "Prefixo do SSM mudou — é contrato com a Lambda e com o Kubernetes."
  }

  assert {
    condition     = output.db_password_ssm_path == "/techchallenge/staging/db/password"
    error_message = "Path da senha mudou — a Lambda lê exatamente este path."
  }

  assert {
    condition = alltrue([
      aws_ssm_parameter.db_endpoint.name == "/techchallenge/staging/db/endpoint",
      aws_ssm_parameter.db_host.name == "/techchallenge/staging/db/host",
      aws_ssm_parameter.db_port.name == "/techchallenge/staging/db/port",
      aws_ssm_parameter.db_name.name == "/techchallenge/staging/db/name",
      aws_ssm_parameter.db_username.name == "/techchallenge/staging/db/username",
      aws_ssm_parameter.db_client_sg_id.name == "/techchallenge/staging/db/client-sg-id",
    ])
    error_message = "Algum parâmetro de descoberta saiu do path documentado na tabela do README do módulo."
  }

  assert {
    condition     = aws_ssm_parameter.db_password.type == "SecureString"
    error_message = "A senha precisa ser SecureString."
  }

  assert {
    condition     = aws_ssm_parameter.db_host.type == "String" && aws_ssm_parameter.db_endpoint.type == "String"
    error_message = "Endpoint e host não são segredo; como SecureString exigiriam kms:Decrypt de quem só precisa descobrir o banco."
  }
}

run "senha_segura_para_url" {
  command = plan

  assert {
    condition     = random_password.db.length == 32
    error_message = "Senha do banco com menos de 32 caracteres."
  }

  assert {
    condition     = random_password.db.override_special == "-_"
    error_message = "Especiais fora de '-_' exigem percent-encoding no DATABASE_URL e quebram a conexão em silêncio."
  }
}

run "rede_fechada_por_security_group" {
  command = plan

  assert {
    condition = alltrue([
      aws_vpc_security_group_ingress_rule.rds_from_client.from_port == 5432,
      aws_vpc_security_group_ingress_rule.rds_from_client.to_port == 5432,
      aws_vpc_security_group_ingress_rule.rds_from_client.ip_protocol == "tcp",
    ])
    error_message = "Ingress do RDS precisa ser só 5432/tcp."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.rds_from_client.cidr_ipv4 == null && aws_vpc_security_group_ingress_rule.rds_from_client.cidr_ipv6 == null
    error_message = "Ingress do RDS por CIDR abre o banco para qualquer coisa na VPC; só por security group de origem."
  }

  assert {
    condition = alltrue([
      aws_vpc_security_group_egress_rule.client_to_rds.from_port == 5432,
      aws_vpc_security_group_egress_rule.client_to_rds.to_port == 5432,
      aws_vpc_security_group_egress_rule.client_to_rds.ip_protocol == "tcp",
    ])
    error_message = "Sem egress 5432 no SG de cliente, a Lambda dá timeout de conexão sem log útil."
  }
}

run "parametros_do_postgres" {
  command = plan

  # Referência a `local`: suportada pelo `terraform test` nas asserções. Se a
  # versão do CI recusar, troque por um output de teste no módulo.
  assert {
    condition     = contains([for p in local.db_parameters : "${p.name}=${p.value}"], "rds.force_ssl=1")
    error_message = "rds.force_ssl=1 precisa estar explícito no parameter group."
  }

  assert {
    condition = anytrue([
      for p in local.db_parameters :
      p.name == "shared_preload_libraries" && p.apply_method == "pending-reboot"
    ])
    error_message = "shared_preload_libraries é estático: apply_method precisa ser pending-reboot."
  }
}

run "observabilidade_sem_forwarder" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_subscription_filter.postgresql) == 0
    error_message = "Sem log_forwarder_arn, o subscription filter não pode ser criado."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.cpu.alarm_name == "techchallenge-staging-rds-cpu",
      aws_cloudwatch_metric_alarm.connections.threshold == 80,
      aws_cloudwatch_metric_alarm.freeable_memory.threshold == 134217728,
    ])
    error_message = "Alarmes do RDS fora do documentado no README (nome por ambiente, 80 conexões, 128 MB)."
  }
}

run "observabilidade_com_forwarder" {
  command = plan

  variables {
    log_forwarder_arn = "arn:aws:lambda:us-east-1:123456789012:function:datadog-forwarder"
  }

  assert {
    condition     = length(aws_cloudwatch_log_subscription_filter.postgresql) == 1
    error_message = "Com log_forwarder_arn, o subscription filter precisa existir."
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.postgresql[0].destination_arn == var.log_forwarder_arn
    error_message = "Subscription filter apontando para outro destino."
  }
}

run "nomes_de_producao" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = output.ssm_prefix == "/techchallenge/prod/db"
    error_message = "Produção precisa de prefixo próprio no SSM, senão lê a senha de homologação."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu.alarm_name == "techchallenge-prod-rds-cpu"
    error_message = "Alarme de produção com nome de outro ambiente."
  }
}

run "recusa_ambiente_desconhecido" {
  command = plan

  variables {
    environment = "dev"
  }

  expect_failures = [var.environment]
}

run "recusa_storage_abaixo_do_minimo" {
  command = plan

  variables {
    db_allocated_storage = 10
  }

  expect_failures = [var.db_allocated_storage]
}

run "recusa_retencao_acima_de_35_dias" {
  command = plan

  variables {
    backup_retention_days = 36
  }

  expect_failures = [var.backup_retention_days]
}

run "sem_rede_o_check_explica_a_ordem_de_apply" {
  command = plan

  # Simula o banco aplicado ANTES do repositório de Kubernetes: nenhuma subnet
  # privada com as tags. O check precisa falhar com a mensagem que manda aplicar
  # a rede primeiro, em vez do erro opaco do subnet group.
  override_data {
    target = data.aws_subnets.private
    values = {
      ids = []
    }
  }

  expect_failures = [check.rede_provisionada_pelo_repositorio_de_kubernetes]
}
