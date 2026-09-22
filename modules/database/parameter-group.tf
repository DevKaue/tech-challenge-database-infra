locals {
  db_parameters = [
    {
      # O Postgres 15 no RDS já vem com rds.force_ssl = 1, mas deixar explícito
      # transforma uma suposição em garantia: se alguém restaurar de um snapshot
      # com outro parameter group, a conexão em texto claro volta a ser aceita
      # sem ninguém perceber.
      #
      # Consequência prática para quem conecta: o driver PRECISA negociar TLS. O
      # @prisma/adapter-pg (node-postgres) só usa TLS se mandarem, e o sintoma da
      # falta é "no pg_hba.conf entry ... no encryption".
      name         = "rds.force_ssl"
      value        = "1"
      apply_method = "immediate"
    },
    {
      # Loga toda query acima de 1s. É o que transforma "o sistema está lento" em
      # uma lista de queries com nome e tempo.
      name         = "log_min_duration_statement"
      value        = "1000"
      apply_method = "immediate"
    },
    {
      # ARMADILHA: shared_preload_libraries é parâmetro ESTÁTICO. O apply grava a
      # configuração e termina com sucesso, mas a extensão só passa a existir
      # DEPOIS de um reboot da instância — e o Terraform não reinicia sozinho.
      #
      # O sintoma é traiçoeiro: `terraform plan` fica limpo, e
      # `SELECT * FROM pg_stat_statements` responde "relation does not exist".
      # O reboot está no runbook do README, e precisa ser feito uma vez, à mão,
      # depois do primeiro apply.
      name         = "shared_preload_libraries"
      value        = "pg_stat_statements"
      apply_method = "pending-reboot"
    },
  ]
}
