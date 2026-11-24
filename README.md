# vigilante

Vigila desde fuera las direcciones públicas de aEnergia y avisa si dejan de responder.

Corre en `ubuntu-latest` (GitHub Actions), **nunca en el servidor que vigila**: si el servidor cae,
el vigilante sigue en pie y avisa.

## Qué lee

Cada 5 minutos (GitHub no garantiza la hora exacta), y solo el código HTTP y un campo público:

| Qué | Dirección | Viva si |
|---|---|---|
| api PROD | `https://api.aenergia.es/health` | 200 y `entorno` = `produccion` |
| app PROD | `https://app.aenergia.es/api/version` | 200 y `build` no vacío |
| api PRUEBAS | `https://api-dev.aenergia.es/health` | 200 y `entorno` = `pruebas` |
| app PRUEBAS | `https://app-dev.aenergia.es/api/version` | 200 y `build` no vacío |

Una dirección cuenta como **caída** si falla dos veces seguidas (la lectura y un reintento a los 20 s).

## Cómo avisa

- Abre **una** issue con la etiqueta `caida`, «CAÍDO: <qué>, desde <hora UTC>», y el run acaba en
  **rojo**. Si la issue ya está abierta, no abre otra (comenta solo si cambia qué está caído).
- Cuando todo vuelve, comenta la hora y **cierra** la issue.

## Probarlo sin tirar nada

*Actions → vigilante → Run workflow*, con `direccion_falsa` = una dirección que no exista
(p. ej. `https://no-existe.invalid/health`). Dos ejecuciones: una sola issue y dos runs en rojo. Una
tercera con el campo vacío la comenta y la cierra.

```bash
gh workflow run vigilante.yml -R aenergia-platform/vigilante -f direccion_falsa=https://no-existe.invalid/health
gh workflow run vigilante.yml -R aenergia-platform/vigilante
```

## Mantenimiento

- **Latido:** los días 1 y 15, el job `latido` hace un commit en `LATIDO.md`. En un repo público,
  GitHub apaga el `schedule` tras 60 días sin actividad; el latido lo evita.
- **Sin secretos:** solo el `GITHUB_TOKEN` del propio run, para la issue.
