# ADR 003: Um diretório e um state por ambiente, com key literal no backend

* **Status**: Aceito
* **Data**: 2026-10-12
* **Hora**: 11:00
* **Autor**: Kaue Sabino
* **Revisores**: —
* **Stakeholders envolvidos**: Avaliação do Tech Challenge Fase 3 (13SOAT), operação dos ambientes de homologação e produção

---

## Contexto

O desafio exige **deploy automático das branches de homologação e produção**. O
repositório tem três branches de vida longa (`develop`, `homolog` e `main`, ver ADR-000) e
dois ambientes de banco:

- **staging** — homologação. O nome é `staging`, e não `homolog`, porque é o nome que o
  Kong e a infra Kubernetes usam (ADR-005 do repositório da aplicação): o cluster de
  staging procura o banco em `/techchallenge/staging/db`. Com outro nome, a Lambda e a
  aplicação desse ambiente leriam um prefixo que ninguém publica.
- **prod** — produção.

Os dois ambientes não têm o mesmo propósito. Homologação existe para provar a execução da
pipeline, não para ficar de pé 24 horas por dia: a segunda instância RDS sai do Free Tier
(750 h/mês cobrem **uma**). Produção guarda o dado que importa.

O risco que a organização do state precisa eliminar é concreto e tem nome no critério de
aceite: **o plan não pode propor destruir o banco**. O acidente típico é um pipeline de
homologação planejar contra o state de produção.

---

## Opções Consideradas

### Opção 1: Um root module com `terraform workspace`
* **Descrição breve**: um único diretório; `terraform workspace select staging|prod`
  escolhe o state.
* **Prós**:
  * [✔️] Nenhuma duplicação de arquivos.
* **Contras**:
  * [❌] A key do state é **calculada** a partir do workspace. Um `workspace select`
    esquecido no CI faz o pipeline de homologação planejar contra o state de produção.
  * [❌] O ambiente não aparece no diff do PR: a mesma linha vale para os dois.
  * [❌] Perfis diferentes (descartável vs. endurecido) viram condicionais sobre
    `terraform.workspace` espalhadas pelo código.

### Opção 2: Um root module com `-backend-config` por ambiente
* **Descrição breve**: o bloco `backend` fica parcial e a key é passada na linha de
  comando do `init`.
* **Prós**:
  * [✔️] Também evita duplicação.
* **Contras**:
  * [❌] Mesmo problema da Opção 1: a key depende de um argumento correto em tempo de
    execução, e um erro de digitação aponta para o state errado.

### Opção 3: Um diretório por ambiente, chamando o mesmo módulo, com key literal
* **Descrição breve**: `envs/staging` e `envs/prod` são root modules pequenos que chamam
  `modules/database`; cada um tem o próprio bloco `backend` com a key escrita no arquivo.
* **Prós**:
  * [✔️] O ambiente está no **path**, no **diff do PR** e no **backend**.
  * [✔️] O perfil de cada ambiente é declarado no `main.tf` dele, sem condicional.
  * [✔️] O pipeline escolhe o ambiente pelo `working-directory`, derivado da branch.
* **Contras**:
  * [❌] `versions.tf`, `providers.tf`, `variables.tf` e `outputs.tf` repetidos nos dois
    diretórios.

---

## Decisão

Adotar a **Opção 3**.

| | `envs/staging` | `envs/prod` |
|---|---|---|
| Key do state | `db/staging/terraform.tfstate` | `db/prod/terraform.tfstate` |
| Bucket / região / lock | `techchallenge-fiap-v1`, `us-east-1`, `use_lockfile = true` | idem |
| Branches que fazem deploy | `develop` e `homolog` | `main` |
| Environment do GitHub | `staging` | `production` (com aprovação obrigatória) |
| Perfil | **Descartável** | **Endurecido** |
| `deletion_protection` | `false` | `true` |
| `skip_final_snapshot` | `true` | `false` |
| `backup_retention_days` | `0` | `1` |
| Classe | `db.t4g.micro` | `db.t4g.micro` |

**`prevent_destroy` não é usado, de propósito.** O meta-argumento exige valor literal e só
existe em `resource`, não em `module`: colocá-lo dentro do módulo compartilhado
bloquearia também o destroy do staging, que precisa rodar sem intervenção. A proteção
equivalente em produção é `deletion_protection`, que vale **do lado da AWS** — a API do
RDS recusa a exclusão, com Terraform ou sem.

**Duas guardas no pipeline sustentam a diferença entre os ambientes:**
- o job `contrato` do CI reprova o PR se `envs/prod/main.tf` perder
  `deletion_protection = true` ou `skip_final_snapshot = false` — copiar o `main.tf` de
  staging por cima do de prod continuaria gerando um plan válido;
- o `deploy.yml` para antes do apply se o plan tiver `delete` em qualquer
  `aws_db_instance`, nos dois ambientes.

**Locking nativo do S3** (`use_lockfile`, Terraform 1.10+), sem tabela DynamoDB.

---

## Justificativa

O critério que decide é **tornar o state errado impossível de escolher por engano**, e
não apenas improvável. Com workspace ou `-backend-config`, o state certo depende de um
passo correto em tempo de execução; com key literal, depende do diretório, que é a mesma
coisa que o revisor vê no PR.

A duplicação dos arquivos de entrada é o preço, e ele é pequeno: o que se repete é
declaração de provider, variáveis e outputs. Os outputs repetidos inclusive têm guarda
própria no CI (o job `contrato` confere os nove nos dois ambientes). A lógica fica no
módulo, uma vez só.

`develop` e `homolog` aplicarem o mesmo staging é consequência de haver só dois ambientes
de banco para três branches: o desafio pede homologação e produção, e um terceiro banco
para a `develop` custaria uma instância fora do Free Tier sem provar nada a mais.

---

## Consequências

### Positivas

* [✔️] O ambiente de cada mudança é visível no path do arquivo alterado.
* [✔️] Staging pode ser destruído sem intervenção; produção não pode ser destruída nem
  pela API.
* [✔️] Os dois deploys de staging (`develop` e `homolog`) entram no mesmo grupo de
  concorrência (`deploy-staging`) e nunca aplicam ao mesmo tempo; o lock do state cobre o
  que sobrar.

### Negativas / Riscos

* [⚠️] Staging reflete o **último** push entre `develop` e `homolog`. Um push na `homolog`
  depois de um na `develop` pode aplicar uma versão mais antiga do código por cima de uma
  mais nova. O fluxo de promoção (merge commit `develop → homolog`) mantém a diferença
  pequena, mas ela existe.
* [⚠️] O comentário de `envs/staging/main.tf` e o `.trivyignore` falam em derrubar o
  staging por **workflow agendado**, que **não existe** neste repositório. Hoje o destroy
  do staging é manual (ver QUICKSTART) — registrado como dívida consciente.
* [⚠️] A região está literal no `backend` e também em `var.region`. Trocar só a variável
  deixa o state numa região e a infra em outra.
* [⚠️] O comentário de `envs/prod/main.tf` justifica a retenção de 1 dia pelo Free Tier e,
  ao mesmo tempo, diz que contas gratuitas recusam qualquer valor acima de 0. Se a conta
  recusar, o apply de prod falha com `FreeTierRestrictionError` e a retenção precisa ir
  para 0.

---

## Ações Imediatas

* [x] `envs/staging` e `envs/prod` com backend literal e perfis distintos.
* [x] Guarda de produção endurecida no CI e guarda de não-destruição no deploy.
* [ ] Configurar aprovação obrigatória no environment `production` do GitHub, com
      "Prevent self-review" desligado (ADR-000).
* [ ] Automatizar o destroy do staging fora da janela de avaliação, ou remover a menção ao
      workflow agendado dos comentários.

---

## Lições Aprendidas

Separar ambientes por diretório é menos elegante do que por workspace e mais seguro pelo
mesmo motivo: a elegância do workspace vem de esconder o ambiente, e é exatamente o
ambiente que precisa estar à vista quando o recurso é um banco de dados.

---

## Referências

* `envs/staging/versions.tf`, `envs/prod/versions.tf` — blocos `backend`
* `envs/staging/main.tf`, `envs/prod/main.tf` — perfis
* `.github/workflows/ci.yml` (job `contrato`) e `.github/workflows/deploy.yml`
* [ADR-000](ADR-000-bootstrap-do-repositorio.md) — branches e gate de produção
* Terraform — S3 backend, `use_lockfile`
