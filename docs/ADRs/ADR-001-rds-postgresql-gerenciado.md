# ADR 001: Amazon RDS for PostgreSQL 15, single-AZ, em db.t4g.micro

* **Status**: Aceito
* **Data**: 2026-10-12
* **Hora**: 10:00
* **Autor**: Kaue Sabino
* **Revisores**: —
* **Stakeholders envolvidos**: Repositório da aplicação (`tech-challenge-app-`), repositório da Function Serverless, repositório de infraestrutura Kubernetes, avaliação do Tech Challenge Fase 3 (13SOAT)

---

## Contexto

A Fase 3 separa o banco de dados em um repositório próprio, com state e ciclo de vida
independentes do cluster. Dois consumidores passam a depender dele: a aplicação no EKS e a
Function Serverless que autentica o cliente por CPF.

O modelo relacional já existe e é mantido pelas migrations do Prisma no repositório da
aplicação: nove tabelas, sete chaves estrangeiras, enums nativos e um índice único parcial
([modelagem-de-dados.md](../modelagem-de-dados.md)). O ADR-004 do repositório-base já
havia escolhido PostgreSQL como banco principal, mas com o RDS como um arquivo dentro do
Terraform da aplicação. Faltava decidir **qual serviço gerenciado**, **qual
dimensionamento** e **qual configuração**, para um banco que agora é compartilhado.

A análise das alternativas — RDS PostgreSQL, Aurora Serverless v2, Postgres autogerenciado
no EKS e DynamoDB — está na [RFC-001](../RFCs/RFC-001-escolha-do-banco-gerenciado.md).

Requisitos não funcionais mais impactados:
- **integridade** (ACID e FKs no banco);
- **custo** (plano gratuito da AWS ou AWS Academy, dois ambientes);
- **segurança** (banco sem exposição pública, tráfego cifrado);
- **operabilidade** (diagnóstico de lentidão sem acesso ao servidor).

---

## Opções Consideradas

### Opção 1: RDS for PostgreSQL 15, single-AZ, db.t4g.micro
* **Descrição breve**: instância gerenciada, do mesmo major do ambiente local, no menor
  tamanho elegível ao Free Tier, uma por ambiente.
* **Prós**:
  * [✔️] Compatível sem alteração com o Prisma e com as migrations existentes.
  * [✔️] `db.t4g.micro` com 20 GB cabe no Free Tier (750 h/mês cobrem uma instância).
  * [✔️] Paridade com o Postgres local e com os composes da aplicação (`15.19-alpine`).
* **Contras**:
  * [❌] Sem failover: a instância vive em uma AZ.
  * [❌] ~1 GiB de RAM e `max_connections` em torno de 110.

### Opção 2: RDS for PostgreSQL 16, Multi-AZ
* **Descrição breve**: a mesma família, na versão mais nova e com réplica síncrona em
  outra AZ.
* **Prós**:
  * [✔️] Failover automático.
  * [✔️] Recursos mais novos do motor.
* **Contras**:
  * [❌] Multi-AZ dobra o custo da instância e sai do Free Tier.
  * [❌] Subir a major para 16 quebra a paridade com o ambiente local: exige atualizar os
    composes e recriar os volumes locais. É migração deliberada, não troca de linha.

### Opção 3: Aurora Serverless v2
* **Descrição breve**: capacidade elástica em ACUs, armazenamento distribuído.
* **Prós**:
  * [✔️] Compatível com PostgreSQL; escala sem trocar de classe.
* **Contras**:
  * [❌] Fora do Free Tier e cerca de quatro vezes mais caro no mínimo de capacidade.
  * [❌] A pausa automática introduz latência de retomada no login da Lambda.

---

## Decisão

Adotar a **Opção 1**, configurada assim em `modules/database`:

| Configuração | Valor | Por quê |
|---|---|---|
| `engine_version` / `family` | `15` / `postgres15` | Paridade dev/prod; subir para 16 é migração deliberada |
| `instance_class` | `db.t4g.micro` (default de `var.db_instance_class`) | Menor classe elegível ao Free Tier |
| `multi_az` | `false` | Custo; registrado como dívida consciente |
| `allocated_storage` / `max_allocated_storage` | `20` / `0` | O Free Tier limita a 20 GB; melhor falhar previsível em 20 GB do que no meio de uma escrita |
| `storage_encrypted` | `true` | Cifrado com a chave gerenciada `aws/rds` (`.trivyignore`, AWS-0080) |
| `publicly_accessible` | `false`, subnets privadas | O banco não tem rota para a internet |
| `rds.force_ssl` | `1`, explícito | Transforma suposição em garantia: um restore com outro parameter group voltaria a aceitar texto claro |
| `log_min_duration_statement` | `1000` | Toda query acima de 1 s vai para o log |
| `shared_preload_libraries` | `pg_stat_statements`, `pending-reboot` | Estatística por query; exige um reboot manual depois do primeiro apply |
| `enabled_cloudwatch_logs_exports` | `postgresql`, `upgrade`, retenção 7 dias | Sem export, o subscription filter do forwarder não recebe evento |
| `manage_master_user_password` | `false` | A senha vai para o SSM; com `true` haveria dois lugares para a mesma senha (ADR-002) |
| `performance_insights_enabled`, monitoring role | desligados | Menos peça móvel (o Enhanced Monitoring exige uma role de IAM própria); o diagnóstico fica com o log de 1 s e o `pg_stat_statements`. Registrado como dívida no README |
| Versão do módulo `terraform-aws-modules/rds/aws` | `6.13.1`, **exata** | O lock file trava provider, não módulo; bump vira PR explícito |

---

## Justificativa

O critério que decide é a combinação de **compatibilidade sem retrabalho** e **custo
compatível com a conta**. O RDS for PostgreSQL é o único serviço gerenciado que roda o
schema atual sem alteração e cabe no Free Tier. Aurora resolveria uma escala que o
domínio não tem; DynamoDB exigiria reescrever a aplicação; Postgres no EKS não seria
gerenciado.

Os contras da opção escolhida foram aceitos porque cada um tem um **gatilho observável**
de reavaliação, em vez de ser ignorado:
- **conexões**: o alarme `techchallenge-<env>-rds-conexoes` dispara acima de 80, perto do
  teto da classe — é o gatilho escrito para RDS Proxy;
- **single-AZ**: vira inaceitável quando o banco tiver dado real de cliente e um SLA de
  disponibilidade;
- **storage fixo**: o dashboard mostra `FreeStorageSpace`, e o aumento é um PR.

O major 15, em vez do 16, é escolha de paridade: o valor de ter ambiente local é ele se
comportar como produção, e isso inclui a versão do motor.

---

## Consequências

### Positivas

* [✔️] A aplicação e a Lambda conectam a um PostgreSQL de verdade, sem adaptação de código.
* [✔️] Um ambiente cabe no Free Tier; o custo de lista é ~US$ 0,47/dia por ambiente.
* [✔️] O banco não é alcançável de fora da VPC e recusa conexão sem TLS.
* [✔️] Lentidão vira dado: queries acima de 1 s no log e estatística por query no
  `pg_stat_statements`.

### Negativas / Riscos

* [⚠️] Queda da AZ derruba o banco. Sem failover.
* [⚠️] Backup limitado pela conta: retenção 0 em staging e 1 dia em prod. Contas no plano
  gratuito podem recusar retenção maior que zero com `FreeTierRestrictionError`, e o erro
  só aparece no apply.
* [⚠️] O `pg_stat_statements` só existe depois de um reboot manual. O `plan` fica limpo e
  a extensão responde `relation does not exist` até lá.
* [⚠️] Todo consumidor precisa negociar TLS. O sintoma da falta é
  `no pg_hba.conf entry ... no encryption`.

---

## Ações Imediatas

* [x] Módulo `modules/database` com `terraform-aws-modules/rds/aws` 6.13.1.
* [x] Parameter group com `rds.force_ssl`, `log_min_duration_statement` e `pg_stat_statements`.
* [x] Alarmes de CPU, memória, conexões e latência de escrita, e dashboard.
* [x] Testes de `terraform test` cobrindo os parâmetros do Postgres e a rede.
* [ ] Reboot manual da instância depois do primeiro apply de cada ambiente.
* [ ] Reavaliar Multi-AZ e retenção de 7 dias quando a conta sair do plano gratuito.

---

## Lições Aprendidas

Parâmetro estático do Postgres é uma armadilha específica de IaC: o Terraform registra a
mudança e considera o trabalho feito, mas o motor só a lê no próximo boot. Toda
configuração com `apply_method = "pending-reboot"` precisa vir acompanhada de um passo de
runbook, senão o estado declarado e o estado real divergem em silêncio.

---

## Referências

* [RFC-001](../RFCs/RFC-001-escolha-do-banco-gerenciado.md) — escolha do banco gerenciado
* ADR-004 do repositório-base: https://github.com/DevKaue/TechChallange
* `modules/database/rds.tf` e `modules/database/parameter-group.tf`
* Amazon RDS for PostgreSQL — parâmetros e grupos de parâmetros
