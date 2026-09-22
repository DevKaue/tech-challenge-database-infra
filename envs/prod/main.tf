# Produção: perfil ENDURECIDO.
#
# Sobre `prevent_destroy`: ele NÃO é usado aqui, e a ausência é deliberada. O
# meta-argumento exige valor literal (não aceita variável) e só existe em
# `resource`, não em `module` — colocá-lo dentro do módulo compartilhado
# bloquearia também o destroy do homolog efêmero, que precisa funcionar sem
# intervenção. A proteção equivalente, e que vale no lado da AWS em vez de só no
# Terraform, é `deletion_protection`: a própria API do RDS recusa a exclusão.
#
# `backup_retention_days` fica em 1 e não em 7 por IMPOSIÇÃO DO FREE TIER, não
# por escolha de engenharia: contas no plano gratuito recusam retenção > 0 com
# FreeTierRestrictionError, e o erro só aparece no apply. Se a conta recusar até
# o 1, baixe para 0 e registre a dívida no README — num plano pago, 7.
module "database" {
  source = "../../modules/database"

  project     = var.project
  environment = "prod"

  db_instance_class = var.db_instance_class

  backup_retention_days = 1
  deletion_protection   = true
  skip_final_snapshot   = false

  log_forwarder_arn = var.log_forwarder_arn
  alarm_actions     = var.alarm_actions
}
