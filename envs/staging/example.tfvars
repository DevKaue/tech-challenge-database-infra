# Copie para terraform.tfvars (gitignored) e ajuste.
# NENHUMA senha aqui: a do banco é gerada por random_password e vai direto para o
# SSM como SecureString.

region  = "us-east-1"
project = "techchallenge"

db_instance_class = "db.t4g.micro"

# Vazio desliga o encaminhamento de logs — o repositório aplica sem exigir conta
# de Datadog/New Relic.
log_forwarder_arn = ""

# ARNs de SNS para os alarmes notificarem. Vazio = alarme muda de estado e
# ninguém fica sabendo.
alarm_actions = []
