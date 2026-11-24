#!/usr/bin/env bash
# vigilante.sh — lee las direcciones públicas de aEnergia y lleva la issue `caida`.
#
# Una dirección está CAÍDA si falla dos veces seguidas (la lectura y un reintento a los 20 s):
# un fallo suelto de red no es una caída. Solo mira el código HTTP y un campo público de la
# respuesta; nunca imprime el cuerpo ni toca una ruta con sesión.
#
#   - Algo caído y ninguna issue `caida` abierta -> abre UNA, «CAÍDO: <qué>, desde <hora UTC>».
#   - Algo caído y la issue ya abierta           -> no abre otra; comenta solo si cambia QUÉ está caído.
#   - Todo responde y hay issue abierta          -> comenta la hora y la cierra.
#   - Si algo está caído, el run acaba en ROJO (exit 1): GitHub manda su aviso de run fallido.
#
# Entorno: GITHUB_REPOSITORY y GH_TOKEN (los pone Actions), RUN_URL (enlace del run),
# DIRECCION_FALSA (opcional, solo para probar el aviso: se lee como una dirección más),
# AVISAR (las cuentas que se mencionan al abrir y al cerrar: una mención notifica siempre).
set -uo pipefail

REPO="${GITHUB_REPOSITORY:?falta GITHUB_REPOSITORY}"
RUN_URL="${RUN_URL:-}"
AHORA="$(date -u +%Y-%m-%dT%H:%MZ)"
ESPERA_REINTENTO="${ESPERA_REINTENTO:-20}"
AVISAR="${AVISAR:-}"

# nombre | dirección | condición jq que el cuerpo debe cumplir (además del 200)
OBJETIVOS=(
  "api PROD|https://api.aenergia.es/health|.entorno == \"produccion\""
  "app PROD|https://app.aenergia.es/api/version|(.build // \"\") != \"\""
  "api PRUEBAS|https://api-dev.aenergia.es/health|.entorno == \"pruebas\""
  "app PRUEBAS|https://app-dev.aenergia.es/api/version|(.build // \"\") != \"\""
)
if [ -n "${DIRECCION_FALSA:-}" ]; then
  OBJETIVOS+=("PRUEBA del vigilante|${DIRECCION_FALSA}|true")
fi

# leer URL CONDICION -> imprime "ok" o el motivo; rc 0 si está viva
leer() {
  local url="$1" cond="$2" cuerpo codigo t
  cuerpo="$(mktemp)"
  codigo="$(curl -sS -m 15 -o "$cuerpo" -w '%{http_code} %{time_total}' "$url" 2>/dev/null || true)"
  t="${codigo#* }"; codigo="${codigo%% *}"; codigo="${codigo:-000}"
  if [ "$codigo" != "200" ]; then
    rm -f "$cuerpo"; echo "HTTP ${codigo} (${t:-?} s)"; return 1
  fi
  if [ "$(jq -r "($cond) | tostring" "$cuerpo" 2>/dev/null)" != "true" ]; then
    rm -f "$cuerpo"; echo "HTTP 200 pero no cumple «${cond}» (${t} s)"; return 1
  fi
  rm -f "$cuerpo"; echo "ok (${t} s)"; return 0
}

CAIDOS=()
TABLA="| Qué | Dirección | Resultado |"$'\n'"|---|---|---|"
for o in "${OBJETIVOS[@]}"; do
  IFS='|' read -r nombre url cond <<<"$o"
  if r="$(leer "$url" "$cond")"; then
    TABLA+=$'\n'"| ${nombre} | ${url} | ${r} |"
  else
    sleep "$ESPERA_REINTENTO"
    if r2="$(leer "$url" "$cond")"; then
      TABLA+=$'\n'"| ${nombre} | ${url} | ${r2} — al reintento (1.ª: ${r}) |"
    else
      CAIDOS+=("$nombre")
      TABLA+=$'\n'"| ${nombre} | ${url} | **CAÍDO** — ${r} · reintento: ${r2} |"
    fi
  fi
done

echo "$TABLA"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && { echo "### Vigilante · ${AHORA}"; echo; echo "$TABLA"; } >>"$GITHUB_STEP_SUMMARY"

ABIERTA="$(gh issue list -R "$REPO" --label caida --state open --json number --jq '.[0].number // empty')"
LISTA="$(IFS=','; echo "${CAIDOS[*]:-}" | sed 's/,/, /g')"
MARCA="<!-- caidos: ${LISTA} -->"

if [ "${#CAIDOS[@]}" -gt 0 ]; then
  CUERPO="${MARCA}"$'\n'"**${LISTA}** no responde desde las **${AHORA}** (dos lecturas seguidas, separadas ${ESPERA_REINTENTO} s)."$'\n\n'"${TABLA}"$'\n\n'"Run: ${RUN_URL}"$'\n\n'"Esta issue se cierra sola cuando todo vuelve a responder. ${AVISAR}"
  if [ -z "$ABIERTA" ]; then
    gh label create caida -R "$REPO" --color B60205 --description "Una dirección de aEnergia no responde" --force >/dev/null
    url_issue="$(gh issue create -R "$REPO" --label caida --title "CAÍDO: ${LISTA}, desde ${AHORA}" --body "$CUERPO")"
    echo "::error::CAÍDO: ${LISTA}. Issue abierta: ${url_issue}"
  else
    # La última marca (cuerpo o último comentario que la lleve) dice qué estaba caído.
    previa="$(gh issue view "$ABIERTA" -R "$REPO" --json body,comments \
      --jq '[.body] + [.comments[].body] | map(select(test("<!-- caidos: "))) | last' \
      | sed -n 's/.*<!-- caidos: \(.*\) -->.*/\1/p' | head -1)"
    if [ "$previa" != "$LISTA" ]; then
      gh issue comment "$ABIERTA" -R "$REPO" --body "${MARCA}"$'\n'"Cambia lo caído a las **${AHORA}**: antes «${previa}», ahora **${LISTA}**."$'\n\n'"${TABLA}"$'\n\n'"Run: ${RUN_URL}" >/dev/null
    fi
    echo "::error::SIGUE CAÍDO: ${LISTA} (issue #${ABIERTA})."
  fi
  exit 1
fi

if [ -n "$ABIERTA" ]; then
  gh issue comment "$ABIERTA" -R "$REPO" --body "Todo vuelve a responder a las **${AHORA}**. ${AVISAR}"$'\n\n'"${TABLA}"$'\n\n'"Run: ${RUN_URL}" >/dev/null
  gh issue close "$ABIERTA" -R "$REPO" >/dev/null
  echo "Recuperado: issue #${ABIERTA} comentada y cerrada."
fi
echo "Todo responde."
