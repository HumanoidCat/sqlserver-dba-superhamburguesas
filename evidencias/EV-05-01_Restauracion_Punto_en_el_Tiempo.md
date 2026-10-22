# EV-05-01 · Acta de prueba de restauración a un punto en el tiempo

> **Proyecto 2 · Entregable 2 — DBSuperHamburguesas**
> Instancia `EXPRESS2022` · SQL Server 2022 16.0.1200.5 Express · Intercalación `Modern_Spanish_CI_AS`
> Capturado por Alejandro Josué Rodríguez Zamora · 22 de septiembre de 2026, 19:35


**Script:** `05_Restore_Recovery.sql` · **Control:** DBA-BKP-02

## 1. Parámetros de la restauración

| Campo | Valor |
|---|---|
| Marca de detención aplicada | 2026-09-22 19:31:56.153 |
| Filas alteradas por el incidente | 20 |
| Base de destino | `DBSuperHamburguesas_RECOVERY` (base alterna) |
| Cadena aplicada | COMPLETO (NORECOVERY) → DIFERENCIAL (NORECOVERY) → REGISTRO 01 (NORECOVERY) → REGISTRO 02 (STOPAT, RECOVERY) |

La base productiva no se toca en ningún momento de la prueba.

## 2. Comparación entre la base dañada y la recuperada

| Ámbito | Ingredientes | Stock total | Filas con stock en cero |
|---|---|---|---|
| PRODUCTIVA (dañada) | 20 | 0,000 | 20 |
| RECUPERADA (a punto en el tiempo) | 20 | 19 910,000 | 0 |

## 3. Prueba del dato

| Prueba | Cero en productiva | Cero en recuperada | Stock total recuperado | Veredicto |
|---|---|---|---|---|
| El dato erróneo NO está presente en la base recuperada | 20 | 0 | 19 910,000 | **CUMPLE** |

| Etapa de referencia | Stock total registrado | Stock total recuperado | ¿Coinciden? |
|---|---|---|---|
| 04 Último estado íntegro | 19 910,000 | 19 910,000 | **SÍ** |

La verificación no es que la restauración haya terminado sin error, sino que el dato afectado aparece en
la base recuperada con su valor previo al incidente.

## 4. Tiempo de recuperación medido

| Campo | Valor |
|---|---|
| Inicio de la restauración | 19:35:30.003 |
| Fin de la restauración | 19:35:30.683 |
| Tiempo real | 0,68 s |
| RTO declarado | 120 minutos |
| **Resultado** | **CUMPLE: dentro del objetivo** |

## 5. Control DBA-BKP-02

| Campo | Valor |
|---|---|
| Sobre base alterna | SÍ |
| Punto en el tiempo | SÍ, con STOPAT |
| Dato erróneo ausente | SÍ |
| Integridad verificada | SÍ, `DBCC CHECKDB` en la sección 5 |
| Tiempo medido contra RTO | Dentro del objetivo |
| **Veredicto** | **CUMPLE** |

## 6. Detalle de los archivos aplicados

| Orden | Tipo | Primer LSN | Último LSN | Con suma de verificación | Aplicado |
|---|---|---|---|---|---|
| 1 | COMPLETO | 42000000469900001 | 42000000470200001 | SÍ | SÍ |
| 2 | DIFERENCIAL | 42000000474500001 | 42000000474800001 | SÍ | SÍ |
| 3 | REGISTRO 01 | 42000000469900001 | 42000000476200001 | SÍ | SÍ |
| 4 | REGISTRO 02 | 42000000476200001 | 42000000479400001 | SÍ | SÍ |

El registro 01 es íntegramente anterior al incidente y se aplica completo. El registro 02 contiene el
incidente, por eso es el único que lleva la detención en la marca.
