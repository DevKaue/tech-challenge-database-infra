# C4 Model - Banco de Dados Gerenciado

Este documento reúne os diagramas C4 em Mermaid para visualização direta no GitHub. O
sistema em foco é o **banco de dados gerenciado** que este repositório provisiona; a
aplicação, a Function Serverless e a infraestrutura Kubernetes aparecem como sistemas
externos, e os diagramas C4 de cada um vivem no repositório deles.

Arquivos-fonte:

- [context.mmd](context.mmd)
- [container.mmd](container.mmd)
- [components.mmd](components.mmd)

## Nível 1 - Contexto

Quem usa o banco e de quem ele depende. O banco não tem usuário humano direto: o time de
engenharia o altera só por Pull Request e pipeline, e o cliente da oficina chega a ele
indiretamente, pela Lambda e pela aplicação.

```mermaid
graph TD
    %% Estilos das Classes (mesma paleta do repositório-base)
    classDef person fill:#084298,stroke:#052c65,stroke-width:2px,color:#ffffff,rx:10px,ry:10px;
    classDef system fill:#1168bd,stroke:#0b4884,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;
    classDef extSystem fill:#999999,stroke:#666666,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;

    %% Atores (Personas)
    DEV["<b>Time de engenharia</b><br/><i>[Person]</i><br/>Propõe mudanças por PR e aprova o deploy de produção"]:::person
    CLI["<b>Cliente da oficina</b><br/><i>[Person]</i><br/>Autentica por CPF e acompanha a própria OS"]:::person

    %% Sistema em foco
    S["<b>Banco de dados gerenciado</b><br/><i>[Software System]</i><br/>PostgreSQL no Amazon RDS, por ambiente, com o contrato de conexão publicado no SSM"]:::system

    %% Sistemas externos
    GHA["<b>GitHub Actions</b><br/><i>[Software System]</i><br/>CI e deploy deste repositório"]:::extSystem
    K8S["<b>Infraestrutura Kubernetes</b><br/><i>[Software System]</i><br/>VPC, subnets e cluster EKS"]:::extSystem
    APP["<b>Aplicação da oficina</b><br/><i>[Software System]</i><br/>API NestJS no EKS, dona do schema via Prisma"]:::extSystem
    FN["<b>Function Serverless</b><br/><i>[Software System]</i><br/>Lambda de autenticação por CPF"]:::extSystem
    OBS["<b>Datadog / New Relic</b><br/><i>[Software System]</i><br/>Observabilidade externa, opcional"]:::extSystem

    %% Relacionamentos
    DEV -->|"Abre PR e aprova o environment production"| GHA
    GHA -->|"terraform plan e apply"| S
    S -->|"Descobre a rede por tag"| K8S
    APP -->|"Lê e grava o domínio; aplica migrations"| S
    FN -->|"Consulta existência e status do cliente"| S
    CLI -->|"Informa o CPF, via Kong"| FN
    CLI -->|"Usa a API com o token"| APP
    S -->|"Encaminha logs do Postgres"| OBS
```

## Nível 2 - Container

O que existe dentro da conta AWS, por ambiente. "Container" aqui é unidade implantável no
sentido do C4 — instância RDS, parameter group, security groups, parâmetros do SSM e
recursos do CloudWatch —, e não container Docker. Este repositório não gera imagem.

```mermaid
graph TD
    %% Estilos das Classes (mantendo identidade visual do diagrama de contexto)
    classDef person fill:#084298,stroke:#052c65,stroke-width:2px,color:#ffffff,rx:10px,ry:10px;
    classDef systemBoundary fill:#e7f1ff,stroke:#0b4884,stroke-width:2px,color:#052c65,rx:10px,ry:10px;
    classDef container fill:#1168bd,stroke:#0b4884,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;
    classDef database fill:#0b4884,stroke:#052c65,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;
    classDef extSystem fill:#999999,stroke:#666666,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;

    %% Sistemas externos
    GHA["<b>GitHub Actions</b><br/><i>[Software System]</i><br/>deploy.yml do ambiente da branch"]:::extSystem
    S3[("<b>Bucket de state</b><br/><i>[Software System: S3]</i><br/>db/staging e db/prod, use_lockfile")]:::extSystem
    VPC["<b>VPC do ambiente</b><br/><i>[Software System]</i><br/>Criada pela infra Kubernetes; tags Project, Environment, ManagedBy"]:::extSystem
    APP["<b>API Oficina no EKS</b><br/><i>[Software System]</i><br/>NestJS + Prisma; entra pelo SG dos nós"]:::extSystem
    FN["<b>Lambda techchallenge-auth-env</b><br/><i>[Software System]</i><br/>Node.js + pg; carrega o SG de cliente"]:::extSystem
    OBS["<b>Datadog / New Relic</b><br/><i>[Software System]</i><br/>Forwarder de logs, opcional"]:::extSystem

    %% Fronteira do Sistema
    subgraph SB["Banco de dados gerenciado - um por ambiente"]
        direction TB
        DB[("<b>PostgreSQL 15</b><br/><i>[Container: Amazon RDS]</i><br/>db.t4g.micro, single-AZ, 20 GB cifrado, subnets privadas<br/>Armazena clientes, veículos, OS, orçamentos e usuários")]:::database
        PG["<b>Parameter group</b><br/><i>[Container: RDS parameter group]</i><br/>rds.force_ssl, log de queries acima de 1 s, pg_stat_statements"]:::container
        SG["<b>Security groups</b><br/><i>[Container: EC2 security group]</i><br/>SG do RDS aceita 5432 do SG de cliente e do SG dos nós"]:::container
        SSM["<b>Contrato de conexão</b><br/><i>[Container: SSM Parameter Store]</i><br/>/techchallenge/env/db/: endpoint, host, port, name, username, password, client-sg-id"]:::container
        CW["<b>Observabilidade</b><br/><i>[Container: CloudWatch]</i><br/>4 alarmes, dashboard, log groups postgresql e upgrade"]:::container
    end
    class SB systemBoundary

    %% Relacionamentos
    GHA -->|"terraform apply, credenciais OIDC ou do lab"| SB
    GHA -->|"state e lock"| S3
    SB -.->|"data source por tag"| VPC
    PG -->|"configura"| DB
    SG -->|"filtra 5432/tcp"| DB
    APP -->|"Prisma, SQL sobre TLS, TCP 5432"| DB
    FN -->|"pg, SELECT em customers sobre TLS, TCP 5432"| DB
    APP -.->|"deploy lê o contrato"| SSM
    FN -.->|"lê o contrato"| SSM
    DB -->|"métricas e logs"| CW
    CW -.->|"subscription filter"| OBS
```

## Nível 3 - Components

Como o módulo `modules/database` se divide em arquivos, e qual depende de qual. Os dois
root modules (`envs/staging` e `envs/prod`) chamam o mesmo módulo com perfis diferentes —
ver [ADR-003](../ADRs/ADR-003-um-state-por-ambiente.md).

```mermaid
graph TD
    %% Estilos visuais
    classDef systemBoundary fill:#e7f1ff,stroke:#0b4884,stroke-width:2px,color:#052c65,rx:10px,ry:10px;
    classDef container fill:#1168bd,stroke:#0b4884,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;
    classDef component fill:#1f78d1,stroke:#0b4884,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;
    classDef sharedKernel fill:#0d5ca6,stroke:#083b6c,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;
    classDef infra fill:#0a4f92,stroke:#063867,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;
    classDef database fill:#0b4884,stroke:#052c65,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;
    classDef extSystem fill:#999999,stroke:#666666,stroke-width:2px,color:#ffffff,rx:8px,ry:8px;

    %% Raízes por ambiente
    STG["<b>envs/staging</b><br/><i>[Root module]</i><br/>Perfil descartável; key db/staging"]:::infra
    PRD["<b>envs/prod</b><br/><i>[Root module]</i><br/>Perfil endurecido; key db/prod"]:::infra

    %% Externos
    VPC["<b>VPC e subnets privadas</b><br/><i>[Infra Kubernetes]</i>"]:::extSystem
    RDSMOD["<b>terraform-aws-modules/rds/aws</b><br/><i>[Módulo da comunidade, 6.13.1]</i>"]:::extSystem
    CONS["<b>Consumidores</b><br/><i>[API Oficina e Lambda]</i>"]:::extSystem

    subgraph SB["modules/database"]
        direction TB
        MAIN["<b>main.tf</b><br/><i>[Component: locals]</i><br/>Nome, tags e prefixo do SSM"]:::sharedKernel
        VAR["<b>variables.tf</b><br/><i>[Component: entradas]</i><br/>Validações de ambiente, storage e retenção"]:::sharedKernel
        NET["<b>network.tf</b><br/><i>[Component: descoberta]</i><br/>VPC e subnets por tag + bloco check"]:::component
        SGS["<b>security-groups.tf</b><br/><i>[Component: rede]</i><br/>SG do RDS, SG de cliente e ingress do SG dos nós"]:::component
        PGR["<b>parameter-group.tf</b><br/><i>[Component: parâmetros]</i><br/>force_ssl, log 1 s, pg_stat_statements"]:::component
        RDS["<b>rds.tf</b><br/><i>[Component: instância]</i><br/>random_password + módulo RDS"]:::component
        SEC["<b>secrets.tf</b><br/><i>[Component: segredo]</i><br/>Senha em SSM SecureString"]:::component
        DISC["<b>discovery.tf</b><br/><i>[Component: contrato]</i><br/>Endpoint, host, porta, nome, usuário, client-sg-id"]:::component
        OBSV["<b>observability.tf</b><br/><i>[Component: observabilidade]</i><br/>Alarmes, dashboard, subscription filter"]:::component
        OUT["<b>outputs.tf</b><br/><i>[Component: contrato]</i><br/>9 outputs conferidos pelo CI"]:::component
        TEST["<b>tests/database.tftest.hcl</b><br/><i>[Component: testes]</i><br/>Provider mockado, command = plan"]:::component
    end
    class SB systemBoundary

    STG -->|"module database"| SB
    PRD -->|"module database"| SB

    NET -.->|"data source por tag"| VPC
    SGS -->|"vpc_id"| NET
    RDS -->|"subnet_ids"| NET
    RDS -->|"vpc_security_group_ids"| SGS
    RDS -->|"parameters"| PGR
    RDS -->|"source"| RDSMOD
    SEC -->|"random_password"| RDS
    DISC -->|"endpoint e porta"| RDS
    DISC -->|"id do SG de cliente"| SGS
    OBSV -->|"db_instance_identifier"| RDS
    OUT --> DISC
    OUT --> SEC
    MAIN -.->|"tags e ssm_prefix"| DISC
    VAR -.-> MAIN
    TEST -.->|"assertions"| DISC
    TEST -.->|"assertions"| SGS
    CONS -.->|"leem /techchallenge/env/db/"| DISC
```
