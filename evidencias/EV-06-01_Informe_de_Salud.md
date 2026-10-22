# EV-06-01 · Informe de salud de la base

> **Proyecto 2 · Entregable 2 — DBSuperHamburguesas**
> Instancia `EXPRESS2022` · SQL Server 2022 16.0.1200.5 Express · Intercalación `Modern_Spanish_CI_AS`
> Capturado por Alejandro Josué Rodríguez Zamora · 22 de septiembre de 2026, 19:32


**Script:** `06_Monitoreo.sql` · **Controles:** DBA-MON-01, DBA-MON-02

## 1. Estado y configuración

| Campo | Valor | Lectura |
|---|---|---|
| Estado | ONLINE | Normal |
| Modelo de recuperación | FULL | Permite recuperación a un punto en el tiempo |
| Verificación de página | CHECKSUM | La verificación de los respaldos comprueba páginas de verdad |
| Nivel de compatibilidad | 160 | Corresponde a SQL Server 2022 |
| Intercalación | Modern_Spanish_CI_AS | Conforme al estándar |
| AutoShrink | OFF | Correcto |
| RCSI | ON | — |
| Razón de espera del registro | NOTHING | El registro se puede reutilizar |

## 2. Archivos y capacidad

| Archivo | Tipo | Tamaño | Usado | Libre | Libre % | Crecimiento | Incremento |
|---|---|---|---|---|---|---|---|
| DBSuperHamburguesas_Data | ROWS | 256,00 MB | 19,38 MB | 236,63 MB | 92,43 % | FIJO | 64 MB |
| DBSuperHamburguesas_Log | LOG | 128,00 MB | 2,84 MB | 125,16 MB | 97,78 % | FIJO | 32 MB |

Margen suficiente en ambos y crecimiento en incrementos fijos, nunca por porcentaje.

## 3. Registro de transacciones

| Total | Usado | Usado % | Razón de espera | Lectura |
|---|---|---|---|---|
| 127,99 MB | 2,84 MB | 2,22 % | NOTHING | Por debajo del 50 %: la cadena de respaldo de registro está corriendo y liberando espacio. Sin acción. |

## 4. Concurrencia

| Señal | Valor |
|---|---|
| Sesiones activas | 3, todas del propio entorno de trabajo, ninguna con espera |
| Transacciones abiertas | 0 |
| Bloqueos en espera | 0 |

## 5. Vigencia de los respaldos

| Tipo | Último respaldo | Antigüedad | Frecuencia exigida | Lectura |
|---|---|---|---|---|
| COMPLETO | 19:31:54 | 1 min | 1 440 min (diario) | Dentro de la frecuencia declarada |
| DIFERENCIAL | 19:31:54 | 1 min | 360 min (cada 6 h) | Dentro de la frecuencia declarada |
| REGISTRO | 19:31:58 | 1 min | 15 min | Dentro de la frecuencia declarada |

## 6. Índices existentes

Siete índices agrupados de clave primaria, uno por tabla con actividad: `ventas.PedidoDetalle` (75 000
filas), `ventas.Pedido` (30 000), `ventas.Cliente` (1 500), `inventario.MovimientoInventario` (40),
`inventario.ExistenciaIngrediente` (20), `ventas.EstadoPedido` (4) e `inventario.TipoMovimientoInventario` (3).

## 7. Controles

| Control | Comprobación | Valor | Veredicto |
|---|---|---|---|
| DBA-MON-01 | Línea base documentada e interpretada | 7 bloques, 7 con interpretación | **CUMPLE** |
| DBA-MON-02 | Vigilancia de capacidad con umbral del 20 % | 0 archivos en alerta, 0 con crecimiento porcentual | **CUMPLE** |

Cada una de las seis señales del informe tiene una acción asociada. Una métrica que no cambia ninguna
decisión no entra al informe de salud.
