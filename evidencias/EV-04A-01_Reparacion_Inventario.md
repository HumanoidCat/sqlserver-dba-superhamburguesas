# EV-04A-01 · Reparación del inventario tras el incidente sin respaldo

> **Proyecto 2 · Entregable 2 — DBSuperHamburguesas**
> Instancia `EXPRESS2022` · SQL Server 2022 16.0.1200.5 Express · Intercalación `Modern_Spanish_CI_AS`
> Capturado por Alejandro Josué Rodríguez Zamora · 22 de septiembre de 2026, 19:31


**Script:** `04a_Reparar_Inventario.sql`

## Contexto

En la primera corrida de `04_Backup.sql` los respaldos no se escribieron y el script continuó hasta
aplicar el incidente deliberado. `inventario.ExistenciaIngrediente` quedó con `StockActual = 0` en las 20
filas, sin respaldo del cual revertirlo.

## Cómo se reparó

El sembrado original de `01_Modelo.sql`, sección 5.5, es determinista: `StockActual` se calcula a partir
del `IngredienteID`. Se recalculó con la misma expresión, dentro de una transacción y con verificación de
que ninguna fila quedara fuera de las restricciones de la tabla. No se tocó ninguna otra columna ni tabla.

## Resultado

| Etapa | Ingredientes | Stock total | Filas en cero | Veredicto |
|---|---|---|---|---|
| Antes de reparar | 20 | 0,000 | 20 | — |
| Después de reparar | 20 | 18 910,000 | 0 | **CUMPLE** |

## Contraste con la evidencia previa

| Etapa registrada | Stock total registrado | Stock actual tras reparar | ¿Coincide? |
|---|---|---|---|
| 01 Estado inicial | 18 910,000 | 18 910,000 | **SÍ** |

El total coincide exactamente con el capturado antes del daño, lo que confirma que la tabla volvió a su
estado original y no a una aproximación.
