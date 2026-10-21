#!/usr/bin/env bash
# Confere um tfplan e grava o resumo das mudanças.
#
# Uso: conferir-plan.sh <tfplan> <arquivo-de-resumo>
#
# O critério de aceite é que o plan nunca proponha destruir o banco. Um replace
# (delete + create) de aws_db_instance apaga os dados mesmo com o apply "dando
# certo", então o pipeline para antes do apply.
#
# O resumo tem só endereço e ações de cada recurso, nunca valores: é ele que o
# job de apply compara com o próprio plan, e por isso pode virar artifact num
# repositório público. O tfplan não pode: carrega a senha do banco em claro.
set -euo pipefail

plano=$1
resumo=$2

terraform show -json "$plano" > plan.json

destruidos=$(jq -r '(.resource_changes // [])[]
  | select(.type == "aws_db_instance")
  | select(.change.actions | index("delete"))
  | .address' plan.json)
if [ -n "$destruidos" ]; then
  echo "::error::O plan destrói o banco: $destruidos"
  exit 1
fi

jq -S '[(.resource_changes // [])[]
  | select(.change.actions != ["no-op"])
  | {address, actions: .change.actions}]
  | sort_by(.address)' plan.json > "$resumo"
rm plan.json
