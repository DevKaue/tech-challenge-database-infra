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
| CI/CD | GitHub Actions com OIDC | Sem chave estática em secret de repositório |
| Segurança de IaC | Trivy (`scan-type: config`) | Mesmo gate do repositório-base, em MEDIUM+ |

## Passos para execução e deploy

<!-- M1 / M3 — inclui o bootstrap do backend, a ordem de apply entre os repositórios e o
     fato de que o primeiro apply de cada repositório é manual -->

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
