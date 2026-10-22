# EV-07-01 · Medición de rendimiento antes y después del índice

> **Proyecto 2 · Entregable 2 — DBSuperHamburguesas**
> Instancia `EXPRESS2022` · SQL Server 2022 16.0.1200.5 Express
> Capturado por Alejandro Josué Rodríguez Zamora · 22 de septiembre de 2026

**Script:** `07_Rendimiento.sql`

## Caso de prueba

Consulta representativa del negocio: cierre comercial de un trimestre sobre `ventas.Pedido`, agrupado por
año y mes, con conteo de pedidos y suma de subtotal, impuesto y total. Columnas declaradas de forma
explícita, conforme a la disposición 9.2.2 del Entregable 1.

## Escenario ANTES

| Objeto | Filas totales | Índices no agrupados | Lectura |
|---|---|---|---|
| `ventas.Pedido` | 30 000 | 0 | Sin índice no agrupado, el predicado de fecha obliga a recorrer el índice agrupado completo |

## Intervención

Se crea el índice `IX_Pedido_EstadoFecha`, con clave `(EstadoPedidoID, FechaPedido)` y columnas incluidas
`(Subtotal, Impuesto, Total)`. Las columnas incluidas convierten la consulta en una lectura que se
resuelve dentro del propio índice, sin volver a la tabla.

## Resultado de la comparación

| Métrica | Antes | Después | Diferencia | Reducción | Comentario |
|---|---|---|---|---|---|
| **Lecturas lógicas** | 291 | 58 | 233 | **80,07 %** | Métrica principal: no depende de la memoria disponible ni de la carga del equipo |
| Tiempo de CPU (ms) | 7 | 5 | 2 | 28,57 % | Sensible a la carga del equipo |
| Tiempo transcurrido (ms) | 6 | 4 | 2 | 33,33 % | Sensible a la carga del equipo y a la memoria disponible |

La comparación se juzga por las lecturas lógicas. Los tiempos absolutos se reportan por completitud, pero
la medición se realiza en un equipo de escritorio con otras cargas y sobre una instancia Express con el
grupo de memoria intermedia limitado a 1 410 MB: no son extrapolables a producción.

## Uso real del índice

| Índice | Búsquedas | Recorridos | Búsquedas por clave | Escrituras | Lectura |
|---|---|---|---|---|---|
| `IX_Pedido_EstadoFecha` | 2 | 0 | 0 | 0 | El optimizador eligió búsqueda por rango sobre el índice nuevo, no recorrido |

## Costo del índice

| Índice | Espacio | Filas | Lectura |
|---|---|---|---|
| `IX_Pedido_EstadoFecha` | 1 448 KB | 30 000 | Costo en disco y en mantenimiento de cada escritura sobre la tabla |

Un índice no es gratuito: se paga en espacio y en cada inserción o actualización de `ventas.Pedido`. Se
justifica porque la consulta de cierre comercial es recurrente y la reducción de lecturas lógicas es de
cuatro quintas partes.

## Corrección aplicada durante la ejecución

1. **Error 2560.** `DBCC FREEPROCCACHE` recibía un `object_id`. La sentencia solo admite `plan_handle`,
   `sql_handle` o el nombre de un grupo de recursos. Se corrigió resolviendo el `plan_handle` desde
   `sys.dm_exec_procedure_stats`, con recorrido acotado y `sp_recompile` como red de seguridad.
2. **Lecturas lógicas en cero.** La medición leía `sys.dm_exec_sessions`, cuyos contadores solo se
   consolidan cuando la petición termina: dentro de la misma ejecución devuelve el mismo valor antes y
   después. Se corrigió leyendo `sys.dm_exec_requests`, que se actualiza mientras la petición corre.
