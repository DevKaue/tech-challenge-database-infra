# Observabilidade do dado, em IaC e versionada. Cobre o bullet "consumo de
# recursos" e "healthchecks" do desafio na fatia que é deste repositório —
# os dashboards de negócio (volume diário de OS, tempo médio por status, erros de
# integração) são da aplicação principal, não daqui.

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${local.name}-rds-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU do RDS acima de 80% por 10 minutos"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = { DBInstanceIdentifier = module.rds.db_instance_identifier }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory" {
  alarm_name          = "${local.name}-rds-memoria"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  # 128 MB numa db.t4g.micro (1 GB): abaixo disso o Postgres começa a trocar e a
  # latência sobe antes de qualquer erro aparecer.
  threshold          = 134217728
  alarm_description  = "Memoria livre do RDS abaixo de 128 MB"
  alarm_actions      = var.alarm_actions
  treat_missing_data = "notBreaching"

  dimensions = { DBInstanceIdentifier = module.rds.db_instance_identifier }

  tags = local.tags
}

# Este alarme é o GATILHO ESCRITO da dívida "sem RDS Proxy".
#
# Uma db.t4g.micro tem ~1 GB de RAM, o que dá max_connections em torno de 110.
# RDS Proxy custa ~US$11/mês e resolve esgotamento de conexão por concorrência —
# que hoje não existe: a Lambda usa um cliente por container e a aplicação tem
# pool fixo. Se este alarme disparar, a premissa mudou e o Proxy passa a valer o
# preço. Observabilidade e dívida amarradas no mesmo artefato.
resource "aws_cloudwatch_metric_alarm" "connections" {
  alarm_name          = "${local.name}-rds-conexoes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 80
  alarm_description   = "Conexoes acima de 80 (teto ~110 na db.t4g.micro) - reavaliar RDS Proxy"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = { DBInstanceIdentifier = module.rds.db_instance_identifier }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "write_latency" {
  alarm_name          = "${local.name}-rds-latencia-escrita"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "WriteLatency"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 0.05 # 50 ms
  alarm_description   = "Latencia de escrita acima de 50ms por 15 minutos"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = { DBInstanceIdentifier = module.rds.db_instance_identifier }

  tags = local.tags
}

resource "aws_cloudwatch_dashboard" "db" {
  dashboard_name = "${local.name}-database"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title  = "CPU e conexões"
          region = data.aws_region.current.name
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", module.rds.db_instance_identifier],
            [".", "DatabaseConnections", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title  = "Memória livre e armazenamento"
          region = data.aws_region.current.name
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", module.rds.db_instance_identifier],
            [".", "FreeStorageSpace", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 24, height = 6,
        properties = {
          title  = "Latência de leitura e escrita"
          region = data.aws_region.current.name
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", module.rds.db_instance_identifier],
            [".", "WriteLatency", ".", "."],
          ]
        }
      },
    ]
  })
}

data "aws_region" "current" {}

# Encaminhamento dos logs do Postgres para Datadog/New Relic. `count` em cima de
# uma variável vazia mantém o repositório aplicável por quem não tem a chave —
# mesmo padrão do `local.github_enabled` do repositório-base.
resource "aws_cloudwatch_log_subscription_filter" "postgresql" {
  count = var.log_forwarder_arn != "" ? 1 : 0

  name            = "${local.name}-postgresql-forwarder"
  log_group_name  = "/aws/rds/instance/${module.rds.db_instance_identifier}/postgresql"
  filter_pattern  = ""
  destination_arn = var.log_forwarder_arn

  depends_on = [module.rds]
}
