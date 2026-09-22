terraform {
  required_version = "~> 1.10"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.90" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  # O bucket precisa existir ANTES do primeiro init (chicken-and-egg do backend).
  # Criação, uma vez por conta — ver README:
  #   aws s3api create-bucket --bucket techchallenge-fiap-v1 --region us-east-1
  #   aws s3api put-bucket-versioning --bucket techchallenge-fiap-v1 \
  #     --versioning-configuration Status=Enabled
  #
  # A KEY É LITERAL, e é isso que separa os ambientes de verdade. Com
  # `terraform workspace` a key seria calculada e um `workspace select`
  # esquecido no CI faria o pipeline de homologação planejar contra o state de
  # PRODUÇÃO — que é exatamente o acidente que o critério de aceite "o plan não
  # pode propor destruir o banco" existe para pegar. Com diretório, o ambiente
  # aparece no path, no diff do PR e aqui.
  backend "s3" {
    bucket       = "techchallenge-fiap-v1"
    key          = "db/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # locking nativo do S3 (1.10+), sem DynamoDB
  }
}
