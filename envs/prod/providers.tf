provider "aws" {
  region = var.region

  # As mesmas tags que o repositório de Kubernetes aplica na VPC. É por elas que
  # o módulo descobre a rede (modules/database/network.tf) — mudar aqui sem mudar
  # lá quebra a descoberta.
  default_tags {
    tags = {
      Project     = var.project
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}
