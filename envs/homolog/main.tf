# Homologação: perfil DESCARTÁVEL de propósito.
#
# A decisão de produto é que homologação existe para provar o bullet "deploy
# automático das branches de homologação e produção" — e esse bullet se prova com
# a EXECUÇÃO DA PIPELINE, não com a instância viva 24 horas por dia. A segunda
# instância RDS sai do Free Tier (750 h/mês cobrem UMA), então esta aqui é
# derrubada fora da janela de avaliação por workflow agendado.
#
# Por isso `deletion_protection = false` e `skip_final_snapshot = true`: o
# destroy precisa rodar sem intervenção manual, senão sobra recurso queimando
# crédito.
module "database" {
  source = "../../modules/database"

  project     = var.project
  environment = "homolog"

  db_instance_class = var.db_instance_class

  backup_retention_days = 0
  deletion_protection   = false
  skip_final_snapshot   = true

  log_forwarder_arn = var.log_forwarder_arn
  alarm_actions     = var.alarm_actions
}
