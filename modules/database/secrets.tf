# SecureString com a chave KMS gerenciada do serviço (`alias/aws/ssm`), não com
# uma CMK própria.
#
# Trade-off aceito: uma CMK custa ~US$1/mês por ambiente para proteger o segredo
# de um ambiente descartável, e o controle que realmente importa aqui é a policy
# de IAM por path — quem não tem `ssm:GetParameter` em
# `/techchallenge/<env>/db/*` não lê, com CMK ou sem.
#
# SSM e não Secrets Manager: mesmo controle por path, custo zero contra
# US$0,40/segredo/mês, e menos peça móvel. É o mesmo raciocínio que o
# repositório-base usou para recusar o External Secrets Operator. Secrets Manager
# passa a valer quando houver rotação automática de verdade.
resource "aws_ssm_parameter" "db_password" {
  name        = "${local.ssm_prefix}/password"
  description = "Senha do usuario master do Postgres de ${var.environment}"
  type        = "SecureString"
  value       = random_password.db.result
  tags        = local.tags

  lifecycle {
    # Sem isto, um ciclo destroy/apply gera outra senha e invalida silenciosamente
    # todo consumidor que já tenha lido a anterior. É a mesma classe de problema
    # que o repositório-base registrou como dívida para o PASSWORD_SALT.
    ignore_changes = [value]
  }
}
