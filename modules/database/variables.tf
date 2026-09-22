variable "project" {
  description = "Prefixo de nome e valor da tag Project. É por esta tag que a VPC é descoberta (network.tf)."
  type        = string
  default     = "techchallenge"
}

variable "environment" {
  description = "Ambiente lógico. Entra no nome de todos os recursos e no path dos parâmetros do SSM."
  type        = string

  validation {
    condition     = contains(["homolog", "prod"], var.environment)
    error_message = "environment precisa ser homolog ou prod — são os dois ambientes que o desafio exige (homologação e produção)."
  }
}

variable "db_instance_class" {
  description = "Classe da instância RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Armazenamento em GB. O Free Tier cobre 20 GB."
  type        = number
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20
    error_message = "O RDS exige no mínimo 20 GB para PostgreSQL."
  }
}

variable "db_name" {
  description = "Nome do banco criado na instância."
  type        = string
  default     = "oficinadb"
}

variable "db_username" {
  description = "Usuário master. A senha é gerada por random_password e nunca fica em .tfvars."
  type        = string
  default     = "techchallenge"
}

variable "backup_retention_days" {
  # ATENÇÃO: contas no plano AWS Free Tier RECUSAM retenção > 0 com
  # `FreeTierRestrictionError`, e o erro só aparece no apply. O default 0 existe
  # por causa disso, não por escolha de engenharia — num plano pago, prod deve
  # usar 7. Ver a seção de dívidas conscientes no README.
  description = "Dias de retenção de backup automático. 0 desliga."
  type        = number
  default     = 0

  validation {
    condition     = var.backup_retention_days >= 0 && var.backup_retention_days <= 35
    error_message = "backup_retention_days precisa estar entre 0 e 35."
  }
}

variable "deletion_protection" {
  description = "Impede exclusão da instância pela API. Em produção real, true."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Pula o snapshot final no destroy. Em produção real, false."
  type        = bool
  default     = true
}

variable "log_forwarder_arn" {
  # Vazio DESLIGA o recurso, no mesmo padrão do `local.github_enabled` do
  # repositório-base. Assim o repositório fica pronto para Datadog/New Relic sem
  # obrigar ninguém a ter a chave para rodar `terraform apply`.
  description = "ARN da Lambda forwarder de logs (Datadog/New Relic). Vazio desliga a subscription."
  type        = string
  default     = ""
}

variable "alarm_actions" {
  description = "ARNs de SNS notificados pelos alarmes. Vazio = alarme existe e muda de estado, sem notificar."
  type        = list(string)
  default     = []
}
