terraform {
  # `~> 1.10` e não `>= 1.10`: o `use_lockfile` do backend S3 exige 1.10+, e um
  # `>=` aberto aceitaria um futuro 2.x com breaking changes.
  required_version = "~> 1.10"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.90" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
