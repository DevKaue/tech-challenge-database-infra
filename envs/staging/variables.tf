variable "region" {
  # ATENÇÃO: o bloco `backend` em versions.tf tem a região como LITERAL, porque
  # backend não aceita variável. Trocar aqui NÃO troca a do backend — os dois
  # precisam mudar juntos, senão o state fica numa região e a infra em outra.
  description = "Região da AWS. Precisa bater com a região do backend em versions.tf."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefixo de nome e valor da tag Project usada para descobrir a VPC."
  type        = string
  default     = "techchallenge"
}

variable "db_instance_class" {
  description = "Classe da instância RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "log_forwarder_arn" {
  description = "ARN da Lambda forwarder de logs (Datadog/New Relic). Vazio desliga."
  type        = string
  default     = ""
}

variable "alarm_actions" {
  description = "ARNs de SNS notificados pelos alarmes."
  type        = list(string)
  default     = []
}
