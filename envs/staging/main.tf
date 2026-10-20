# Homologação (`staging`): perfil DESCARTÁVEL de propósito.
#
# O nome é `staging`, e não `homolog`, porque é o nome que o Kong e a infra
# Kubernetes usam (ADR-005 do repositório da aplicação): o cluster de staging
# procura o banco em /techchallenge/staging/db. Com outro nome, a Lambda e a
# aplicação desse ambiente leriam um prefixo que ninguém publica.
#
# A decisão de produto é que homologação existe para provar o bullet "deploy
# automático das branches de homologação e produção" — e esse bullet se prova com
# a EXECUÇÃO DA PIPELINE, não com a instância viva 24 horas por dia. A segunda
# instância RDS sai do Free Tier (750 h/mês cobrem UMA), então esta aqui é
# derrubada fora da janela de avaliação pelo workflow `destroy.yml`.
#
# Por isso `deletion_protection = false` e `skip_final_snapshot = true`: o
# destroy precisa rodar sem intervenção manual, senão sobra recurso queimando
# crédito.
module "database" {
  source = "../../modules/database"

  project     = var.project
  environment = "staging"

  db_instance_class = var.db_instance_class

  backup_retention_days = 0
  deletion_protection   = false
  skip_final_snapshot   = true

  log_forwarder_arn = var.log_forwarder_arn
  alarm_actions     = var.alarm_actions
}
