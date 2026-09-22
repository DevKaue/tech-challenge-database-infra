# Descoberta da rede por TAG, e não por remote state.
#
# Duas razões objetivas para não usar `terraform_remote_state` do repositório de
# Kubernetes:
#
#   1. Aquele state guarda JWT_SECRET, PASSWORD_SALT, WEBHOOK_SECRET e a senha do
#      RDS em TEXTO CLARO. Dar `s3:GetObject` nele para o pipeline do banco
#      entregaria todos os segredos da aplicação ao repositório errado.
#   2. `terraform_remote_state` só lê OUTPUTS, e o repositório de Kubernetes não
#      exporta vpc_id nem private_subnets. Usar remote state exigiria alterar
#      aquele repositório de qualquer forma — some a única vantagem que teria.
#
# As tags já existem: Project/ManagedBy vêm do `default_tags` do provider, e
# `kubernetes.io/role/internal-elb` marca as subnets privadas (ela é obrigatória
# para o AWS Load Balancer Controller descobrir as subnets, então é estável por
# dois motivos independentes — não some sem quebrar o Ingress também).
data "aws_vpc" "this" {
  filter {
    name   = "tag:Project"
    values = [var.project]
  }

  filter {
    name   = "tag:ManagedBy"
    values = ["terraform"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  # As subnets públicas carregam as MESMAS tags Project/ManagedBy. Só esta
  # distingue privada de pública — sem ela, o subnet group do RDS pegaria subnet
  # pública e o banco ficaria alcançável de fora.
  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = ["1"]
  }
}

# Sem esta checagem, "nenhuma subnet encontrada" só estoura lá dentro do módulo
# do RDS, com "subnet group requires at least 2 subnets" — mensagem que não
# menciona a causa real e manda a pessoa procurar no lugar errado.
check "rede_provisionada_pelo_repositorio_de_kubernetes" {
  assert {
    condition     = length(data.aws_subnets.private.ids) >= 2
    error_message = "VPC ou subnets privadas nao encontradas pelas tags Project=${var.project} e ManagedBy=terraform. Aplique primeiro o repositorio de infraestrutura Kubernetes: ele e o dono da rede."
  }
}
