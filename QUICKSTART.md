# Quickstart — subir o banco

Passo a passo direto. Cada arquivo `.tf` está comentado com o porquê das escolhas; as
decisões estão nos [ADRs](docs/ADRs) e o contrato publicado, no
[README do módulo](modules/database/README.md).

- [Validar sem credencial](#validar-sem-credencial) — sua máquina, ~2 min, sem custo
- [AWS](#aws) — RDS de verdade, ~15 min por ambiente e **~US$ 0,47/dia por ambiente**
- [Pipeline](#pipeline) — deploy automático por branch
- [Derrubar](#derrubar)
- [Se der errado](#se-der-errado)

---

## Validar sem credencial

Roda exatamente o que o CI roda, sem conta AWS e sem criar nada.

### Pré-requisitos

- Terraform `~> 1.10` (o CI usa **1.10.5**; o `use_lockfile` do backend exige 1.10+)

### Passos

```bash
terraform fmt -check -recursive

# -backend=false: valida sem tocar no state do S3
for env in staging prod; do
  (cd envs/$env && terraform init -backend=false && terraform validate)
done

# Provider mockado e command = plan: prova o contrato do SSM, a rede e as validações
cd modules/database
terraform init -backend=false
terraform test
```

O `terraform test` precisa terminar com todos os `run` em `pass`, inclusive os que
**esperam falha** (`recusa_ambiente_desconhecido`, `recusa_storage_abaixo_do_minimo`,
`recusa_retencao_acima_de_35_dias` e `sem_rede_o_check_explica_a_ordem_de_apply`).

---

## AWS

> Cada ambiente custa **~US$ 0,47/dia** fora do Free Tier. Faça o [teardown](#derrubar)
> do staging ao terminar.

### Pré-requisitos

- AWS CLI v2 configurado — `aws sts get-caller-identity` precisa responder
- Terraform `~> 1.10` e `jq`
- A **infraestrutura Kubernetes do mesmo ambiente já aplicada**
  ([TechChallenge---Infraestrutura-Kubernetes-com-Terraform](https://github.com/DevKaue/TechChallenge---Infraestrutura-Kubernetes-com-Terraform)).
  Ela é a dona da VPC; este repositório só a encontra

### Ordem entre os repositórios

| # | Repositório | O que faz | Por que nesta ordem |
|---|---|---|---|
| 1 | Infraestrutura Kubernetes | VPC, subnets e EKS, com as tags `Project`, `Environment` e `ManagedBy` | O banco é criado **dentro** dessa VPC |
| 2 | **Este** | RDS + contrato em `/techchallenge/<env>/db/` | Os consumidores leem o contrato |
| 3 | Aplicação | `prisma migrate deploy` cria as tabelas | O RDS nasce **vazio** |
| 4 | Function Serverless | Lê o contrato e consulta `customers` | Sem as tabelas, responde 503 |

### Passo 1 — bucket do state (uma vez por conta AWS)

O bucket é criado pelo bootstrap da infraestrutura Kubernetes e compartilhado pelos
quatro repositórios; as keys não colidem, porque este grava em `db/<env>/terraform.tfstate`.
O nome **não** está no código: nome de bucket é global, e cada conta do AWS Academy precisa
do seu. Guarde-o numa variável do shell:

```bash
export TF_STATE_BUCKET=<nome do bucket do bootstrap>
aws s3api head-bucket --bucket "$TF_STATE_BUCKET"   # precisa responder sem erro
```

Rodando este repositório sozinho, crie um com nome único e versionamento ligado (é o que
permite recuperar um state corrompido ou sobrescrito):

```bash
aws s3api create-bucket --bucket "$TF_STATE_BUCKET" --region us-east-1
aws s3api put-bucket-versioning --bucket "$TF_STATE_BUCKET" \
  --versioning-configuration Status=Enabled
```

### Passo 2 — conferir que a rede existe

```bash
aws ec2 describe-vpcs --query 'Vpcs[].VpcId' --output text --filters \
  Name=tag:Project,Values=techchallenge \
  Name=tag:Environment,Values=staging \
  Name=tag:ManagedBy,Values=terraform
```

Precisa sair **exatamente um** id. Nenhum: a infraestrutura Kubernetes de staging não foi
aplicada. Dois ou mais: o plan vai falhar por ambiguidade.

```bash
VPC=<id do comando anterior>
aws ec2 describe-subnets --query 'Subnets[].SubnetId' --output text --filters \
  Name=vpc-id,Values=$VPC \
  Name=tag:kubernetes.io/role/internal-elb,Values=1
```

Precisa sair **pelo menos duas** subnets — são as privadas, onde o banco vai morar.

### Passo 3 — plan e apply do staging (~10 a 15 min)

```bash
cd envs/staging
cp example.tfvars terraform.tfvars      # gitignored; nenhuma senha aqui
terraform init -backend-config="bucket=$TF_STATE_BUCKET"
terraform plan -out=tfplan              # LEIA o plano antes
```

A mesma guarda que o pipeline aplica — o plan não pode destruir o banco:

```bash
terraform show -json tfplan | jq -r '(.resource_changes // [])[]
  | select(.type == "aws_db_instance")
  | select(.change.actions | index("delete")) | .address'
```

Saída vazia: pode aplicar. Qualquer linha: **pare** e descubra o que força o replace.

```bash
terraform apply tfplan
rm tfplan                               # o plano tem a senha em texto claro
```

### Passo 4 — reboot único, para o `pg_stat_statements`

`shared_preload_libraries` é parâmetro **estático**: o apply termina com sucesso, o `plan`
fica limpo, e a extensão só existe depois de um reboot. Uma vez por instância:

```bash
aws rds reboot-db-instance --db-instance-identifier techchallenge-staging
aws rds wait db-instance-available --db-instance-identifier techchallenge-staging
aws rds describe-db-instances --db-instance-identifier techchallenge-staging \
  --query 'DBInstances[0].DBParameterGroups[].ParameterApplyStatus' --output text
```

Precisa sair `in-sync`. Se sair `pending-reboot`, o reboot não pegou.

### Passo 5 — conferir o contrato

```bash
aws ssm get-parameters-by-path --path /techchallenge/staging/db \
  --query 'Parameters[].Name' --output text
```

Precisa listar os sete: `endpoint`, `host`, `port`, `name`, `username`, `password` e
`client-sg-id`. A senha só aparece com `--with-decryption` — não rode isso em tela
compartilhada.

### Produção

Os mesmos passos em `envs/prod`, trocando `staging` por `prod` nos comandos. Diferenças
que você vai ver:

- `deletion_protection = true`: a própria API do RDS recusa a exclusão;
- `skip_final_snapshot = false`: um destroy deixa um snapshot final para trás;
- `backup_retention_days = 1`: se a conta estiver no plano gratuito, o apply pode falhar
  com `FreeTierRestrictionError` — ver [Se der errado](#se-der-errado).

---

## Pipeline

[`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) faz os passos 3 e 5
sozinho, no push:

| Branch | Ambiente | Environment do GitHub |
|---|---|---|
| `develop` | staging | `staging` |
| `main` | prod | `production` |

O job `plan` publica o plano no resumo do run; o job `apply` espera a aprovação do
environment, planeja de novo e só aplica se o plano for igual ao aprovado.

Configure **um** dos dois conjuntos de credencial, mais o bucket:

| Nome | Onde | Tipo | Para quê |
|---|---|---|---|
| `AWS_DEPLOY_ROLE` | repositório | secret | Role do OIDC, fora do AWS Academy |
| `AWS_LAB_ACCESS_KEY_ID`, `AWS_LAB_SECRET_ACCESS_KEY`, `AWS_LAB_SESSION_TOKEN` | repositório | secret | Credenciais temporárias do AWS Academy; recoladas a cada sessão do lab |
| `TF_STATE_BUCKET` | repositório | variável | Bucket do state, criado pelo bootstrap da infra Kubernetes e compartilhado pelos quatro repositórios |
| `LOG_FORWARDER_ARN` | repositório | variável | Lambda que encaminha os logs ao Datadog/New Relic; vazio desliga |
| `ALARM_ACTIONS` | repositório | variável | Lista JSON de ARNs de SNS dos alarmes, ex.: `["arn:aws:sns:..."]` |

Tudo fica no nível do **repositório** (Settings → Secrets and variables → Actions), não do
environment: o job de `plan` roda sem environment para o plano sair antes do gate, e só
enxerga o que é do repositório. Os environments `staging` e `production` existem para o
gate do `apply`.

Crie os environments `staging` e `production` em **Settings → Environments**. No
`production`, ligue **Required reviewers** e deixe **Prevent self-review** desligado
([ADR-000](docs/ADRs/ADR-000-bootstrap-do-repositorio.md)): o job de apply para antes de
começar e espera a aprovação, com o plano já visível no run.

> O passo 4 (reboot) **não** é feito pelo pipeline. Depois do primeiro deploy de cada
> ambiente, rode-o à mão.

---

## Derrubar

### Staging — ao fim de cada janela de avaliação

Pelo GitHub: **Actions → Destroy do staging → Run workflow**, digitando `staging`. À mão,
os passos abaixo.

A ordem é a inversa da criação: **consumidores → banco → rede**. Enquanto a Lambda carregar o SG de
cliente, a AWS recusa apagá-lo e o destroy para no meio. Os nós do EKS entram por uma
regra que referencia o SG deles, e essa regra sai junto com o banco.

```bash
cd envs/staging
terraform plan -destroy -out=tfdestroy  # LEIA o que será apagado
terraform apply tfdestroy
rm tfdestroy                            # carrega o state inteiro
```

O destroy roda sem intervenção porque staging tem `deletion_protection = false` e
`skip_final_snapshot = true`. Não existe workflow que faça isso sozinho: é manual.

### Produção

Produção **não** é derrubada pelo pipeline nem por engano. Se for preciso ao fim da
avaliação:

```bash
aws rds modify-db-instance --db-instance-identifier techchallenge-prod \
  --no-deletion-protection --apply-immediately
cd envs/prod
terraform plan -destroy -out=tfdestroy
terraform apply tfdestroy
```

O destroy cria um snapshot final (`final-techchallenge-prod-<sufixo>`), que **continua
cobrado** depois que a instância some. Apague-o quando não precisar mais:

```bash
aws rds describe-db-snapshots --snapshot-type manual \
  --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
aws rds delete-db-snapshot --db-snapshot-identifier <id>
```

> **`terraform destroy` não apaga o bucket de state.** Ele é criado fora do Terraform de
> propósito: o histórico de versões serve justamente para recuperar de um destroy indevido.

---

## Se der errado

| Sintoma | O que fazer |
|---|---|
| `no matching EC2 VPC found` no plan | A VPC do ambiente não existe ou está sem uma das tags `Project`, `Environment`, `ManagedBy`. Aplique a infraestrutura Kubernetes do mesmo ambiente; confira com o passo 2 |
| `multiple EC2 VPCs matched` | Duas VPCs com as mesmas três tags. Uma delas está com o `Environment` errado |
| `check ... VPC ou subnets privadas nao encontradas` | A VPC existe, mas há menos de duas subnets com `kubernetes.io/role/internal-elb = 1`. A mensagem cita só `Project` e `ManagedBy`, mas o filtro também usa `Environment` |
| `FreeTierRestrictionError` no apply de prod | A conta recusa retenção de backup > 0. Baixe `backup_retention_days` para `0` em `envs/prod/main.tf` por PR e registre a dívida — o CI só guarda `deletion_protection` e `skip_final_snapshot` |
| Pipeline para em "O plan não destrói o banco" | Algum atributo força o replace do `aws_db_instance`. **Não contorne a guarda**: leia o plan (`terraform show tfplan`) e procure `forces replacement` |
| `Error acquiring the state lock` | Um run anterior foi interrompido. Confirme que nada está rodando e use `terraform force-unlock <ID>`; com `use_lockfile`, o lock é um objeto `.tflock` ao lado do state no S3 |
| `ExpiredToken` / `InvalidClientTokenId` no deploy | As credenciais do AWS Academy expiraram com a sessão. Recole os três secrets `AWS_LAB_*` do repositório |
| Deploy assume a role com as chaves do lab | Os dois conjuntos de credencial estão preenchidos. Deixe só um |
| `relation "pg_stat_statements" does not exist` | Faltou o reboot do passo 4 |
| Consumidor recebe `no pg_hba.conf entry ... no encryption` | O cliente conectou sem TLS e o `rds.force_ssl = 1` recusou. Use `sslmode` no `DATABASE_URL` |
| Lambda ou aplicação com **timeout** de conexão, sem log útil | O consumidor não carrega o SG de cliente (`client-sg-id`). Parece banco lento; é rede fechada |
| Lambda responde **503** para todo CPF | As tabelas ainda não existem (`prisma migrate deploy` não rodou) ou falta a coluna `customers.status` — ver [modelagem de dados](docs/modelagem-de-dados.md#situação-migration-no-develop-da-aplicação) |
| Destroy do staging para em `DependencyViolation` no SG `db-client` | Algum consumidor ainda carrega o SG de cliente. Derrube ou desanexe o consumidor primeiro |
| `InvalidParameterCombination` ao apagar prod | `deletion_protection` ainda está ligado. Rode o `modify-db-instance` acima |

Diagnóstico geral:

```bash
aws rds describe-db-instances --db-instance-identifier techchallenge-staging \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,DBParameterGroups[0].ParameterApplyStatus]'
aws cloudwatch describe-alarms --alarm-name-prefix techchallenge-staging-rds \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output table
aws logs tail /aws/rds/instance/techchallenge-staging/postgresql --since 1h
```
