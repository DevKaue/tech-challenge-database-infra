# Infraestrutura do Banco de Dados Gerenciado — Tech Challenge Fase 3

Provisiona, por Terraform, o **PostgreSQL gerenciado (Amazon RDS)** que sustenta o sistema
da oficina mecânica, em dois ambientes — homologação e produção —, com state próprio,
ciclo de vida próprio e a modelagem de dados documentada e justificada.

É um dos quatro repositórios da Fase 3:

| Repositório | Papel |
|---|---|
| [TechChallange](https://github.com/DevKaue/TechChallange) | Aplicação principal em Kubernetes (Fases 1 e 2) |
| [TechChallange---Function-Serverless](https://github.com/DevKaue/TechChallange---Function-Serverless) | Function Serverless de autenticação por CPF |
| **tech-challenge-database-infra** (este) | **Banco de dados gerenciado (Terraform)** |
| _(a definir)_ | Infraestrutura Kubernetes (Terraform) |

> **Status: bootstrap.** Este repositório acabou de ser criado. As seções abaixo existem
> porque são entregáveis obrigatórios do desafio e vão ser preenchidas nos marcos M1 e M5
> do plano de execução. O que já vale: o fluxo de contribuição em
> [CONTRIBUTING.md](CONTRIBUTING.md) e a decisão de bootstrap em
> [ADR-000](docs/ADRs/ADR-000-bootstrap-do-repositorio.md).

## Propósito

<!-- M1 -->

## Tecnologias utilizadas

| Camada | Tecnologia | Justificativa |
|---|---|---|
| IaC | Terraform `~> 1.10` | `use_lockfile` no backend S3 exige 1.10+ |
| Nuvem | AWS | Continuidade com as Fases 1 e 2 |
| Banco | PostgreSQL 15 (Amazon RDS) | Paridade com o ambiente local e com os composes do repositório-base |
| CI/CD | GitHub Actions com OIDC ou credenciais temporárias do AWS Academy | Sem chave estática de usuário IAM em secret |
| Segurança de IaC | Trivy (`scan-type: config`) | Mesmo gate do repositório-base, em MEDIUM+ |

## Passos para execução e deploy

### Ambientes

| Branch | Ambiente | Diretório | State |
|---|---|---|---|
| `develop` | staging | `envs/staging` | `db/staging/terraform.tfstate` |
| `homolog` | staging | `envs/staging` | `db/staging/terraform.tfstate` |
| `main` | prod | `envs/prod` | `db/prod/terraform.tfstate` |

### Ordem entre os repositórios

1. Infraestrutura Kubernetes: cria a VPC com as tags `Project`, `Environment` e `ManagedBy`,
   que é por onde este repositório acha a rede.
2. **Este repositório**: cria o RDS e publica o contrato em `/techchallenge/<env>/db/`
   (`endpoint`, `host`, `port`, `name`, `username`, `password` e `client-sg-id`).
3. Lambda e aplicação: leem esse prefixo do SSM.

### Pré-requisito, uma vez por conta

O bucket do state precisa existir antes do primeiro `init`:

```bash
aws s3api create-bucket --bucket techchallenge-fiap-v1 --region us-east-1
aws s3api put-bucket-versioning --bucket techchallenge-fiap-v1 \
  --versioning-configuration Status=Enabled
```

### Local

```bash
cd envs/staging
cp example.tfvars terraform.tfvars
terraform init
terraform plan
```

Sem credencial da AWS dá para rodar o que o CI roda: `terraform fmt -check -recursive`,
`terraform init -backend=false && terraform validate` em cada `envs/<env>`, e
`terraform test` em `modules/database`.

### Deploy

[`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) roda no push para `develop`
e `homolog` (staging) e para `main` (prod), e também manualmente:

1. `terraform plan` do ambiente da branch.
2. Para se o plan destruir ou recriar o `aws_db_instance`: um replace apaga os dados mesmo
   com o apply terminando sem erro.
3. `terraform apply` do plan salvo.
4. Confere se todos os parâmetros do contrato estão no SSM.

Configuração por environment do GitHub (`staging` e `production`):

| Nome | Tipo | Para quê |
|---|---|---|
| `AWS_DEPLOY_ROLE` | secret | Role do OIDC, fora do AWS Academy |
| `AWS_LAB_ACCESS_KEY_ID`, `AWS_LAB_SECRET_ACCESS_KEY`, `AWS_LAB_SESSION_TOKEN` | secret | Credenciais temporárias do AWS Academy; recoladas a cada sessão do lab |
| `LOG_FORWARDER_ARN` | variável | Lambda que encaminha os logs ao Datadog/New Relic; vazio desliga |
| `ALARM_ACTIONS` | variável | Lista JSON de ARNs de SNS dos alarmes, ex.: `["arn:aws:sns:..."]` |

Use OIDC **ou** as credenciais do lab, nunca os dois. O environment `production` deve ter
aprovação obrigatória, para o push na `main` parar antes do apply.

## Diagrama da arquitetura deste repositório

<!-- M1 — bloco ```mermaid INLINE. O GitHub não renderiza .mmd linkado, e quem avalia não
     clona o repositório para ver desenho. A fonte fica em docs/diagrams/ -->

## Modelagem de dados

<!-- M1 (status "Proposto") → M5 (status "Aceito"):
     - justificativa formal da escolha do banco (docs/RFCs/RFC-002)
     - diagrama ER com as 9 tabelas e cardinalidades
     - explicação escrita de cada relacionamento
     - justificativa de cada índice
     - ajuste do modelo relacional: coluna `status` em `customers` -->

## Link para o Swagger/Postman das APIs

**Não se aplica.** Este repositório provisiona infraestrutura; não expõe API e não produz
artefato executável. Pelo mesmo motivo **não há Dockerfile** aqui, e os jobs de build de
imagem, validação de manifestos Kubernetes e `kubeconform` não fazem parte do CI.

## Custo estimado

<!-- M1 — tabela em US$/dia, com as DUAS instâncias na conta -->

## Dívidas conscientes

<!-- M1 — cada dívida com o critério que a tornaria inaceitável -->

## Documentação

- [ADRs](docs/ADRs) — decisões arquiteturais permanentes
- [RFCs](docs/RFCs) — propostas técnicas em discussão
- [CONTRIBUTING.md](CONTRIBUTING.md) — commits, branches, merge e revisão
