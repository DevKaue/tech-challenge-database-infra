# `modules/database`

Provisiona o PostgreSQL gerenciado de **um** ambiente e publica o contrato de
descoberta que os outros repositórios consomem.

Chamado por `envs/homolog` e `envs/prod`. Não tem backend próprio nem provider
configurado — quem faz isso é o ambiente.

## Arquivos

```
main.tf              locals: nome, tags e prefixo do SSM
versions.tf          required_version e providers
variables.tf         entradas, com blocos validation
network.tf           descoberta da VPC e das subnets POR TAG, + bloco check
security-groups.tf   SG do RDS e o SG DE CLIENTE publicado
parameter-group.tf   rds.force_ssl, log_min_duration_statement, pg_stat_statements
rds.tf               random_password + módulo terraform-aws-modules/rds/aws 6.13.1
secrets.tf           senha em SSM SecureString, com ignore_changes
discovery.tf         endpoint, host, porta, nome, usuário e id do SG de cliente em SSM
observability.tf     4 alarmes, dashboard e subscription filter opcional
outputs.tf           CONTRATO — renomear quebra dois consumidores em silêncio
```

## Contrato publicado no SSM

| Path | Tipo | Quem consome |
|---|---|---|
| `/<project>/<env>/db/endpoint` | String | Kubernetes, Lambda |
| `/<project>/<env>/db/host` | String | Kubernetes, Lambda |
| `/<project>/<env>/db/port` | String | Kubernetes, Lambda |
| `/<project>/<env>/db/name` | String | Kubernetes, Lambda |
| `/<project>/<env>/db/username` | String | Kubernetes, Lambda |
| `/<project>/<env>/db/password` | SecureString | Kubernetes (apply), Lambda (runtime) |
| `/<project>/<env>/db/client-sg-id` | String | Kubernetes (anexa nos nós), Lambda (anexa na função) |

## Pré-requisito

A VPC e as subnets privadas **não** são criadas aqui. Elas vêm do repositório de
infraestrutura Kubernetes e são descobertas por tag. Se ele não tiver sido
aplicado, o `plan` falha no bloco `check` com a mensagem dizendo exatamente isso.

## Armadilha conhecida

`pg_stat_statements` entra em `shared_preload_libraries`, que é parâmetro
**estático**: o apply termina com sucesso, o `plan` fica limpo, e a extensão só
existe **depois de um reboot da instância**. O Terraform não reinicia sozinho.
Reboot uma vez, à mão, depois do primeiro apply.
