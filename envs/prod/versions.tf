terraform {
  required_version = "~> 1.10"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.90" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  # O bucket NÃO está aqui: vem no init, por configuração parcial do backend
  # (`-backend-config="bucket=..."`, da variável TF_STATE_BUCKET no deploy). Nome
  # de bucket é global e cada conta do AWS Academy precisa do seu; com o nome
  # fixo, o init de outra conta falha com AccessDenied num bucket que ela não
  # pode recriar. O bucket é criado pelo bootstrap da infra Kubernetes e
  # compartilhado pelos quatro repositórios, cada um com a sua key.
  #
  # A KEY É LITERAL, e é isso que separa os ambientes de verdade. Com
  # `terraform workspace` a key seria calculada e um `workspace select`
  # esquecido no CI faria o pipeline de homologação planejar contra o state de
  # PRODUÇÃO — que é exatamente o acidente que o critério de aceite "o plan não
  # pode propor destruir o banco" existe para pegar. Com diretório, o ambiente
  # aparece no path, no diff do PR e aqui.
  backend "s3" {
    key          = "db/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # locking nativo do S3 (1.10+), sem DynamoDB
  }
}
