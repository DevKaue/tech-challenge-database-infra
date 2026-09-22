locals {
  name = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Component   = "database"
  }

  # Prefixo único de todos os parâmetros publicados. É o contrato de descoberta
  # entre este repositório e os consumidores (Kubernetes e Lambda) — ver
  # discovery.tf e a tabela no README.
  ssm_prefix = "/${var.project}/${var.environment}/db"
}
