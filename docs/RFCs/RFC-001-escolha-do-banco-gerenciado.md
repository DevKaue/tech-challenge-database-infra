# RFC 001: Escolha do banco de dados gerenciado

* **Status**: Aceita
* **Data**: 2026-10-12
* **Autor**: Kaue Sabino
* **Prazo para comentários**: 2026-10-12
* **Decisão resultante**: [ADR-001](../ADRs/ADR-001-rds-postgresql-gerenciado.md)

> **RFC ou ADR?** A RFC **propõe e pede comentário antes** de a decisão existir: ela abre a
> discussão, apresenta alternativas em pé de igualdade e admite ser rejeitada. O ADR
> **registra a decisão depois** de tomada, e é imutável — muda-se por substituição, não por
> edição. Toda RFC aceita gera um ADR; nem todo ADR vem de uma RFC.

---

## Resumo

Propõe-se usar o **Amazon RDS for PostgreSQL 15**, em instância `db.t4g.micro` single-AZ,
como banco de dados gerenciado do sistema da oficina na Fase 3, um por ambiente (staging e
prod), provisionado por Terraform neste repositório.

A decisão é necessária agora porque a Fase 3 separa o banco em um repositório e um ciclo
de vida próprios: a aplicação no Kubernetes e a Function Serverless de autenticação passam
a depender de uma base que **não** sobe junto com o cluster. Nas Fases 1 e 2 o RDS era um
arquivo dentro do Terraform da aplicação; a escolha foi herdada, nunca justificada
formalmente para um banco compartilhado por dois consumidores.

Se nada for decidido, cada consumidor continua com uma suposição diferente sobre onde o
banco está e como se conectar — o que já aconteceu (ver ADR-002) — e o desafio fica sem a
justificativa formal da escolha do banco, que é entregável obrigatório.

---

## Motivação

O enunciado da Fase 3 pede, para este repositório:

> justificativa formal para a escolha do banco de dados e ajustes no modelo relacional,
> com diagramas ER e explicação dos relacionamentos

Além do requisito formal, há restrições concretas que qualquer opção precisa respeitar:

1. **O modelo é relacional e já existe.** Nove tabelas, sete FKs, enums nativos e um
   índice único parcial (`vehicles_plate_active_unique_idx ... WHERE deleted_at IS NULL`),
   tudo versionado em migrations do Prisma com `provider = "postgresql"`. Ver
   [modelagem-de-dados.md](../modelagem-de-dados.md).
2. **Há fluxos transacionais entre tabelas.** Aprovar um orçamento, mudar o status da OS e
   gravar o histórico da transição precisam acontecer juntos ou não acontecer.
3. **Dois consumidores com perfis diferentes.** A aplicação (pool fixo de conexões, no
   EKS) e a Lambda (uma conexão por container, cold start a cada escala). A Lambda
   responde a uma requisição de login: latência de acordar o banco vira latência de login.
4. **Custo e conta.** O projeto roda em conta no plano gratuito da AWS ou no AWS Academy,
   com crédito limitado e sem tolerância a recurso caro esquecido ligado.
5. **Paridade com o ambiente local.** O Docker Compose e o overlay local da aplicação usam
   Postgres 15 (`15.19-alpine`).

---

## Proposta detalhada

| Item | Valor | Onde está no código |
|---|---|---|
| Motor | PostgreSQL, major **15** (`family = postgres15`) | `modules/database/rds.tf` |
| Classe | `db.t4g.micro` (2 vCPU burstable, 1 GiB, Graviton) | `var.db_instance_class` |
| Disponibilidade | **Single-AZ** (`multi_az = false`) | `rds.tf` |
| Armazenamento | 20 GB, cifrado (`storage_encrypted = true`), sem autoscaling (`max_allocated_storage = 0`) | `rds.tf`, `variables.tf` |
| Rede | Subnets privadas, `publicly_accessible = false`, ingress 5432 só a partir do SG de cliente (Lambda) e do SG dos nós do EKS (`/techchallenge/<env>/eks/node-sg-id`) | `network.tf`, `security-groups.tf` |
| TLS | `rds.force_ssl = 1` explícito no parameter group | `parameter-group.tf` |
| Diagnóstico | `log_min_duration_statement = 1000`, `pg_stat_statements`, logs exportados ao CloudWatch | `parameter-group.tf`, `rds.tf` |
| Credencial | Usuário master com senha gerada por `random_password`, publicada em SSM SecureString | `rds.tf`, `secrets.tf` |
| Ambientes | Uma instância por ambiente: `techchallenge-staging` e `techchallenge-prod` | `envs/staging`, `envs/prod` |

**O que esta RFC não cobre:** o schema (dono: repositório da aplicação), o canal de
publicação da conexão (ADR-002) e a separação de state por ambiente (ADR-003).

---

## Alternativas consideradas

### Alternativa 1 — Amazon RDS for PostgreSQL (proposta)
* **Descrição**: instância Postgres gerenciada pela AWS. A AWS opera hardware, patch de
  sistema operacional, backup automático, snapshot e failover (quando Multi-AZ); o time
  opera parâmetros, conexões e schema.
* **Prós**:
  * [✔️] **Compatibilidade total com o que já existe**: é PostgreSQL de verdade, então o
    `provider = "postgresql"` do Prisma, as migrations, os enums nativos e o índice
    parcial funcionam sem alteração. A aplicação não muda uma linha.
  * [✔️] **ACID completo**, constraints e integridade referencial no próprio banco.
  * [✔️] **Custo**: `db.t4g.micro` com 20 GB é elegível ao Free Tier (750 h/mês cobrem
    uma instância o mês inteiro). Fora dele, ~US$ 0,47/dia por ambiente.
  * [✔️] Sempre ligado: sem latência de "acordar" para a Lambda.
  * [✔️] Mesmo serviço que o repositório-base das Fases 1 e 2 já usava — a migração é de
    repositório, não de tecnologia.
* **Contras**:
  * [❌] Single-AZ não tem failover: se a AZ cair, o banco cai junto.
  * [❌] Cobra 24 h por dia, use-se ou não — staging precisa ser derrubado fora da janela de
    avaliação para não consumir crédito à toa.
  * [❌] `max_connections` em torno de 110 na `db.t4g.micro`: muitas Lambdas concorrentes
    podem esgotar conexões antes de esgotar CPU.
* **Por que foi escolhida**: é a única opção que atende as cinco restrições da motivação
  ao mesmo tempo.

### Alternativa 2 — Amazon Aurora Serverless v2 (PostgreSQL-compatible)
* **Descrição**: cluster Aurora com capacidade em ACUs que escala conforme a carga, com
  armazenamento distribuído em três AZs.
* **Prós**:
  * [✔️] Compatível com PostgreSQL no nível do protocolo e do SQL: Prisma e migrations
    funcionariam.
  * [✔️] Armazenamento replicado em várias AZs por padrão, failover mais rápido.
  * [✔️] Escala a capacidade sem trocar de classe de instância.
* **Contras**:
  * [❌] **Não entra no Free Tier.** Com capacidade mínima de 0,5 ACU, só o compute fica em
    torno de US$ 1,44/dia por ambiente, cerca de quatro vezes a `db.t4g.micro`, antes de
    armazenamento e I/O.
  * [❌] A pausa automática, que reduziria o custo ocioso, devolve a primeira conexão
    depois de segundos de retomada — exatamente o caminho de login da Lambda.
  * [❌] Mais peças para provisionar (cluster, instância, parameter group de cluster) por
    um ganho de escala que o volume de uma oficina não usa.
* **Por que não foi escolhida**: paga-se, todo dia e nos dois ambientes, por elasticidade
  que não é necessária, e a forma de economizar prejudica o consumidor mais sensível a
  latência.

### Alternativa 3 — PostgreSQL autogerenciado no EKS (StatefulSet + EBS)
* **Descrição**: o mesmo Postgres que o overlay local da aplicação usa, rodando como
  StatefulSet no cluster com volume EBS.
* **Prós**:
  * [✔️] Compatibilidade total, mesma imagem do ambiente local.
  * [✔️] Custo marginal baixo: o volume EBS de 20 GB, já que o cluster existe de qualquer
    forma.
* **Contras**:
  * [❌] **Não é gerenciado**, e o repositório existe para entregar um banco gerenciado.
    Backup, restauração, upgrade de versão, failover e monitoramento passam a ser
    responsabilidade do time.
  * [❌] Acopla o ciclo de vida do dado ao do cluster: um `terraform destroy` da infra
    Kubernetes, ou a perda do nó com o volume, leva o banco junto. É exatamente o
    acoplamento que a Fase 3 separa em repositórios.
  * [❌] A Lambda passaria a depender de rede até um Service dentro do cluster, em vez de
    um endpoint de VPC estável.
* **Por que não foi escolhida**: troca custo por responsabilidade operacional e desfaz a
  separação de ciclos de vida que motiva a Fase 3.

### Alternativa 4 — Amazon DynamoDB
* **Descrição**: banco chave-valor/documento serverless, cobrado por requisição ou por
  capacidade provisionada.
* **Prós**:
  * [✔️] Free Tier permanente generoso e custo ocioso praticamente zero.
  * [✔️] Sem gestão de conexões: a Lambda falaria por HTTPS, sem pool nem `max_connections`.
* **Contras**:
  * [❌] **Incompatível com a aplicação**: o Prisma não suporta DynamoDB. Toda a camada de
    persistência das Fases 1 e 2 precisaria ser reescrita.
  * [❌] Sem joins nem FKs: as relações OS → orçamento → itens e OS → histórico virariam
    responsabilidade da aplicação, com desnormalização e consistência eventual em índices
    secundários.
  * [❌] Transações limitadas (`TransactWriteItems`, com teto de itens por transação), em
    vez de ACID sobre qualquer conjunto de linhas.
* **Por que não foi escolhida**: o ganho é de operação e custo ocioso; o preço é reescrever
  a aplicação e abrir mão da integridade referencial que o domínio exige.

### Comparativo

| Critério | RDS PostgreSQL | Aurora Serverless v2 | Postgres no EKS | DynamoDB |
|---|---|---|---|---|
| Compatível com Prisma e com as migrations atuais | Sim | Sim | Sim | **Não** |
| ACID e integridade referencial no banco | Sim | Sim | Sim | Parcial |
| Gerenciado pela AWS | Sim | Sim | **Não** | Sim |
| Free Tier | **Sim** (uma instância) | Não | Só o EBS | Sim |
| Custo por ambiente fora do Free Tier (~US$/dia) | ~0,47 | ~1,44 + storage | ~0,05 (EBS) | ~0 ocioso |
| Latência estável para a Lambda | Sim | Não, com pausa | Depende do cluster | Sim |
| Ciclo de vida independente do cluster | Sim | Sim | **Não** | Sim |

---

## Impacto

* **Custo** (US$/dia, quando houver recurso cobrado): ~US$ 0,47/dia por ambiente fora do
  Free Tier (instância + 20 GB), ~US$ 0,95/dia com staging e prod de pé. Detalhe e
  premissas na seção [Custo estimado do README](../../README.md#custo-estimado).
* **Segurança**: banco em subnet privada, sem IP público, TLS obrigatório
  (`rds.force_ssl = 1`), armazenamento cifrado, ingress só por security group de origem.
* **Operação e runbook**: reboot manual único depois do primeiro apply, para o
  `pg_stat_statements` carregar ([QUICKSTART](../../QUICKSTART.md)); staging é derrubado
  fora da janela de avaliação.
* **Outros repositórios afetados**:
  * `tech-challenge-app-`: nenhuma mudança de código; o `DATABASE_URL` precisa negociar
    TLS. As migrations do Prisma continuam sendo o dono do schema.
  * `TechChallange---Function-Serverless`: conecta com `pg` ao mesmo endpoint, com TLS.
  * `TechChallenge---Infraestrutura-Kubernetes-com-Terraform`: deixa de criar o RDS; passa
    a ser dono só da rede onde ele mora.

---

## Riscos e mitigações

| Risco | Probabilidade | Impacto | Mitigação | Como se detecta |
|---|---|---|---|---|
| Esgotar conexões com muitas Lambdas concorrentes | Baixa | Alto | RDS Proxy quando a premissa mudar | Alarme `techchallenge-<env>-rds-conexoes` (> 80 por 10 min) |
| Falha da AZ derruba o banco | Baixa | Alto | Multi-AZ quando houver SLA (dobra o custo da instância) | Evento do RDS e falha dos health checks da aplicação |
| Storage cheio em 20 GB (autoscaling desligado) | Baixa | Alto | Aumentar `db_allocated_storage` por PR | Widget `FreeStorageSpace` do dashboard |
| Staging esquecido de pé consumindo crédito | Média | Médio | `terraform destroy` do staging ao fim de cada janela | Billing da conta / crédito do lab |
| Driver conectando sem TLS | Média | Médio | `sslmode` no `DATABASE_URL` | Erro `no pg_hba.conf entry ... no encryption` |

---

## Questões em aberto

* Multi-AZ e retenção de backup de 7 dias em produção dependem de a conta sair do plano
  gratuito. Decide: Kaue Sabino, quando houver conta paga.
* Usuário de aplicação com privilégio mínimo (em vez do master) para a Lambda, que só
  precisa de `SELECT` em `customers`. Decide: Kaue Sabino, junto com o repositório da
  aplicação, que é dono das migrations onde o `GRANT` viveria.

---

## Comentários recebidos

| Data | Quem | Comentário | Resolução |
|---|---|---|---|
| — | — | Nenhum comentário recebido no prazo | Aceita como proposta |

---

## Referências

* ADR-004 do repositório-base ([DevKaue/TechChallange](https://github.com/DevKaue/TechChallange)): PostgreSQL como banco principal
* [modelagem-de-dados.md](../modelagem-de-dados.md) — o modelo que o banco precisa sustentar
* Amazon RDS for PostgreSQL — documentação e página de preços
* Amazon Aurora Serverless v2 — documentação e página de preços
* Prisma — conectores de banco de dados suportados
