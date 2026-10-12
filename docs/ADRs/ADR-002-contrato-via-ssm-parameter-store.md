# ADR 002: Contrato de conexão publicado no SSM Parameter Store e rede descoberta por tag

* **Status**: Aceito
* **Data**: 2026-10-12
* **Hora**: 10:30
* **Autor**: Kaue Sabino
* **Revisores**: —
* **Stakeholders envolvidos**: Repositório da aplicação (`tech-challenge-app-`), repositório da Function Serverless, repositório de infraestrutura Kubernetes

---

## Contexto

Com o banco em um repositório próprio, três perguntas de integração precisam de resposta
estável:

1. **Como este repositório acha a rede** onde o banco deve morar? A VPC e as subnets são
   criadas pelo repositório de infraestrutura Kubernetes.
2. **Como os consumidores acham o banco** — endpoint, porta, nome, usuário e senha — sem
   copiar valores à mão?
3. **Como se autoriza o tráfego** entre o banco e os consumidores, sem que um repositório
   precise conhecer os security groups do outro?

O repositório-base resolvia tudo dentro de um único state: o RDS referenciava
`module.eks.node_security_group_id` e o Secret do Kubernetes lia a senha direto do recurso.
Separado em repositórios, esse atalho deixa de existir, e as alternativas óbvias têm custos
concretos:

- **`terraform_remote_state`** do repositório de Kubernetes exigiria dar `s3:GetObject`
  num state que guarda `JWT_SECRET`, `PASSWORD_SALT`, `WEBHOOK_SECRET` e a senha do banco
  em texto claro. Quando a decisão foi tomada havia um segundo motivo, registrado em
  `network.tf`: `terraform_remote_state` só lê **outputs**, e o repositório de Kubernetes
  não exportava `vpc_id` nem as subnets privadas. Hoje o `develop` daquele repositório já
  exporta `vpc_id` e `private_subnet_ids`, então esse motivo caducou — o primeiro, que é o
  decisivo, continua de pé.
- **Copiar o endpoint à mão** para um Secret do Kubernetes e para a variável da Lambda
  garante que os três lugares divirjam na primeira mudança.
- **Descobrir o SG dos nós do EKS por data source** é frágil: o módulo do EKS cria mais de
  um SG com as mesmas tags, e discriminar por `Name` depende de um sufixo aleatório.

---

## Opções Consideradas

### Opção 1: Remote state nos dois sentidos
* **Descrição breve**: este repositório lê a VPC do state de Kubernetes; os consumidores
  leem endpoint e senha do state deste repositório.
* **Prós**:
  * [✔️] Nenhum recurso extra na AWS.
* **Contras**:
  * [❌] Cada leitor ganha acesso ao state inteiro do outro, segredos incluídos.
  * [❌] Cria dependência circular de apply: o banco precisa da rede, e o Kubernetes
    precisaria do banco para montar o Secret.
  * [❌] Renomear um output quebra o consumidor com `Unsupported attribute`, longe daqui.

### Opção 2: Secrets Manager com o segredo gerenciado pelo RDS
* **Descrição breve**: `manage_master_user_password = true`; o RDS cria e rotaciona um
  segredo no Secrets Manager, e os consumidores o leem.
* **Prós**:
  * [✔️] Rotação automática da senha nativa.
* **Contras**:
  * [❌] US$ 0,40 por segredo por mês, por ambiente, contra custo zero do SSM Standard.
  * [❌] O nome do segredo é gerado pela AWS, não é um path previsível: o consumidor
    precisaria descobrir o ARN de alguma forma — de volta ao problema 2.
  * [❌] Endpoint, porta e SG de cliente continuariam precisando de outro canal.

### Opção 3: SSM Parameter Store com prefixo fixo, rede por tag e SG de cliente publicado
* **Descrição breve**: este repositório acha a VPC e as subnets privadas **por tag**,
  cria um SG de cliente sem propósito próprio, e publica tudo que o consumidor precisa em
  `/techchallenge/<env>/db/`.
* **Prós**:
  * [✔️] Ninguém lê o state de ninguém.
  * [✔️] Path previsível, derivado só do nome do ambiente.
  * [✔️] Controle de acesso por policy de IAM no path, sem custo.
* **Contras**:
  * [❌] As tags passam a ser contrato com o repositório de Kubernetes.
  * [❌] Sem rotação automática de senha.

---

## Decisão

Adotar a **Opção 3**.

**Descoberta da rede** (`modules/database/network.tf`):
- VPC por `tag:Project = techchallenge`, `tag:ManagedBy = terraform` e
  `tag:Environment = <env>`. O filtro de ambiente é obrigatório: a infra Kubernetes cria
  uma VPC por ambiente, as duas com o mesmo `Project`; sem ele, o plan falha com
  "multiple VPC matched", ou — pior, com só um ambiente aplicado — o banco de prod nasce na
  VPC de staging.
- Subnets privadas por `tag:kubernetes.io/role/internal-elb = 1`, a única tag que separa
  privada de pública. Ela também é exigida pelo AWS Load Balancer Controller, então não
  some sem quebrar o Ingress junto.
- Um bloco `check` exige pelo menos duas subnets e, se não achar, diz que a infra
  Kubernetes precisa ser aplicada primeiro — em vez do erro opaco do subnet group.

**Autorização de rede** (`security-groups.tf`): o SG do RDS só aceita 5432/tcp vindo do
SG `techchallenge-<env>-db-client`, que este repositório cria e publica para ser
**anexado** aos nós do EKS e à Lambda. O SG de cliente tem egress explícito 5432 para o
SG do RDS, porque a Lambda não sai sem regra.

**Contrato publicado** (`discovery.tf`, `secrets.tf`), todos com o prefixo
`/techchallenge/<env>/db`:

| Parâmetro | Tipo |
|---|---|
| `endpoint` (host:porta), `host`, `port`, `name`, `username` | `String` |
| `password` | `SecureString`, chave `alias/aws/ssm`, `ignore_changes = [value]` |
| `client-sg-id` | `String` |

**Sem Secrets Manager**: `manage_master_user_password = false`, para que a senha exista
em **um** lugar só.

O contrato é protegido em três camadas: o `terraform test` confere os paths e os tipos, o
job `contrato` do CI confere os outputs dos dois ambientes, e o `deploy.yml` confere os
sete parâmetros no SSM depois de cada apply.

---

## Justificativa

O critério principal é **nenhum repositório ler o state de outro**. O state deste
repositório guarda a senha gerada em texto claro, e o do Kubernetes guarda os segredos da
aplicação; qualquer opção baseada em remote state entrega segredos ao repositório errado.

Entre SSM e Secrets Manager, o controle que importa é o mesmo — policy de IAM por path —
e o SSM o entrega sem custo e com um path que o consumidor sabe montar sozinho. Secrets
Manager passa a valer o preço quando houver rotação automática de verdade, e essa é a
condição escrita de revisão.

O SG de cliente inverte a dependência: em vez de o banco precisar conhecer quem o acessa,
quem precisa acessar carrega o SG. Nenhum dos lados precisa do id do outro.

`endpoint` e `host` são `String` e não `SecureString` porque não são segredo: cifrá-los
obrigaria a dar `kms:Decrypt` a quem só precisa descobrir o banco.

---

## Consequências

### Positivas

* [✔️] Mudança de endpoint (um restore, por exemplo) se propaga pelo SSM, sem PR em outro
  repositório.
* [✔️] Uma única senha, em um único lugar, com acesso por path.
* [✔️] A ordem de apply é explícita e o erro de ordem errada diz o que fazer.

### Negativas / Riscos

* [⚠️] As tags `Project`, `Environment`, `ManagedBy` e `kubernetes.io/role/internal-elb`
  viraram contrato com o repositório de Kubernetes. Mudá-las lá quebra a descoberta aqui.
* [⚠️] A mensagem do bloco `check` cita só as tags `Project` e `ManagedBy`, embora o
  filtro da VPC use também `Environment`. Uma VPC com a tag de ambiente errada falha antes,
  no data source, com `no matching EC2 VPC found`.
* [⚠️] Sem rotação de senha. O `ignore_changes` evita trocar a senha por acidente, mas
  também significa que trocá-la é uma operação manual.
* [⚠️] **Divergência atual com os consumidores.** Na data deste ADR, os outros dois
  repositórios ainda não leem este contrato:
  * o `deploy.yml` do `develop` da aplicação monta o `DATABASE_URL` lendo o **Secrets
    Manager** (`aws secretsmanager get-secret-value --secret-id ${{ secrets.DB_SECRET_ID }}`,
    com as chaves JSON `host`, `port`, `dbname`, `username` e `password`), que este
    repositório **não** cria;
  * o `develop` do repositório de infraestrutura Kubernetes lê o state deste repositório
    por `terraform_remote_state` (key `db/prod/terraform.tfstate`) e espera um output
    `db_password`, que este repositório **não** exporta — e a ordem de apply que aquele
    código pressupõe (banco primeiro) é a inversa da daqui (rede primeiro).

  Enquanto esses dois pontos não forem alinhados, o banco sobe e publica o contrato, mas a
  aplicação não o encontra.

---

## Ações Imediatas

* [x] Descoberta de VPC e subnets por tag, com o filtro de ambiente e o bloco `check`.
* [x] SG de cliente publicado em `client-sg-id`.
* [x] Os sete parâmetros publicados e cobertos por teste, CI e conferência pós-deploy.
* [ ] Repositório da aplicação: trocar a leitura do Secrets Manager por
      `aws ssm get-parameter --with-decryption --name /techchallenge/<env>/db/password` e
      os demais paths do prefixo.
* [ ] Repositório de infraestrutura Kubernetes: remover o `terraform_remote_state` do
      banco e anexar o `client-sg-id` aos nós do EKS.
* [ ] Repositório da Lambda: anexar o `client-sg-id` à função e ler o prefixo em
      `DB_SSM_PREFIX`.

---

## Lições Aprendidas

Um contrato entre repositórios só é contrato se o produtor o testa. Aqui o nome de cada
path está num teste que falha se mudar — e ainda assim os consumidores divergiram, porque
foram escritos contra uma versão anterior do desenho. Contrato testado do lado do produtor
não substitui o consumidor testar a leitura do lado dele.

---

## Referências

* `modules/database/network.tf`, `security-groups.tf`, `discovery.tf`, `secrets.tf`
* `modules/database/tests/database.tftest.hcl` — run `contrato_de_descoberta_no_ssm`
* [README do módulo](../../modules/database/README.md) — tabela do contrato
* AWS Systems Manager Parameter Store — parâmetros `SecureString`
