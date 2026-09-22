# Security group do banco: sem ingress por CIDR, só por security group de
# origem. Assim o RDS continua fechado mesmo que alguém crie outra coisa dentro
# da mesma VPC.
resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "Postgres acessivel somente por quem carrega o security group de cliente"
  vpc_id      = data.aws_vpc.this.id

  tags = local.tags
}

# O SG DE CLIENTE é a peça que quebra o acoplamento entre repositórios.
#
# No repositório-base o ingress do RDS referenciava `module.eks.node_security_group_id`,
# que agora vive em OUTRO state. Descobrir aquele SG por data source é frágil: o
# módulo do EKS cria mais de um SG com as mesmas tags, e discriminar por `Name`
# depende de um sufixo aleatório.
#
# Invertendo: este repositório PUBLICA um SG sem propósito de rede próprio, feito
# para ser ANEXADO por quem precisa falar com o banco — nós do EKS e a Lambda.
# Quem carrega, alcança; quem não carrega, não alcança. E nenhum dos dois lados
# precisa conhecer o id do outro.
resource "aws_security_group" "db_client" {
  name        = "${local.name}-db-client"
  description = "Anexe a quem precisa falar com o Postgres de ${var.environment}"
  vpc_id      = data.aws_vpc.this.id

  tags = local.tags
}

# Egress explícito no cliente: os nós do EKS têm egress irrestrito por padrão do
# módulo, mas a Lambda NÃO sai sem regra. Sem isto o sintoma é timeout de
# conexão sem log útil — parece banco lento, é rede fechada.
resource "aws_vpc_security_group_egress_rule" "client_to_rds" {
  security_group_id            = aws_security_group.db_client.id
  referenced_security_group_id = aws_security_group.rds.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres do ${var.environment}"

  tags = local.tags
}

# `aws_vpc_security_group_ingress_rule` e não o antigo `aws_security_group_rule`:
# o recurso legado não aceita tags e sofre drift quando várias regras dividem o
# mesmo security group.
resource "aws_vpc_security_group_ingress_rule" "rds_from_client" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.db_client.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres a partir de quem carrega o SG de cliente"

  tags = local.tags
}
