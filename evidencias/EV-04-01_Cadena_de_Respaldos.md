# EV-04-01 · Estrategia y cadena de respaldos

> **Proyecto 2 · Entregable 2 — DBSuperHamburguesas**
> Instancia `EXPRESS2022` · SQL Server 2022 16.0.1200.5 Express · Intercalación `Modern_Spanish_CI_AS`
> Capturado por Alejandro Josué Rodríguez Zamora · 22 de septiembre de 2026, 19:31


**Script:** `04_Backup.sql` · **Control:** DBA-BKP-01

## 1. Criticidad y objetivos de recuperación

| Campo | Valor |
|---|---|
| Base | DBSuperHamburguesas |
| Criticidad | Alta |
| RPO | 15 minutos |
| RTO | 120 minutos |
| Estrategia | Modelo completo. Respaldo completo diario, diferencial cada 6 horas y respaldo de registro cada 15 minutos. |

**Justificación del RPO.** Quince minutos es el volumen de pedidos que el personal del turno puede
reconstruir a partir de los comprobantes físicos. Más allá de ese punto la reconstrucción manual deja de
ser viable.

**Justificación del RTO.** Dos horas para que la recuperación quepa dentro de una jornada parcial y no
arrastre el turno siguiente. La base sostiene la toma y el cobro de pedidos: su indisponibilidad detiene
la atención e impide facturar.

Ambos valores quedan almacenados con su justificación en `dba.ObjetivoRecuperacion`.

## 2. Cadena producida

| Orden | Tipo | Inicio | Fin | Tamaño | Con suma de verificación | Dañado |
|---|---|---|---|---|---|---|
| 1 | COMPLETO | 19:31:54.000 | 19:31:54.000 | 19,77 MB | SÍ | NO |
| 2 | DIFERENCIAL | 19:31:54.000 | 19:31:54.000 | 1,21 MB | SÍ | NO |
| 3 | REGISTRO 01 | 19:31:54.000 | 19:31:54.000 | 0,08 MB | SÍ | NO |
| 4 | REGISTRO 02 | 19:31:58.000 | 19:31:58.000 | 0,08 MB | SÍ | NO |

## 3. Evolución del inventario durante la prueba

| Etapa | Ingredientes | Stock total | Stock mínimo | Stock máximo |
|---|---|---|---|---|
| 01 Estado inicial | 20 | 18 910,000 | 271,000 | 1 620,000 |
| 02 Después del cambio controlado 1 | 20 | 19 910,000 | 271,000 | 1 720,000 |
| 03 Después del cambio controlado 2 | 20 | 19 910,000 | 271,000 | 1 720,000 |
| 04 Último estado íntegro | 20 | 19 910,000 | 271,000 | 1 720,000 |
| 05 Estado alterado por el incidente | 20 | 0,000 | 0,000 | 0,000 |

## 4. Incidente lógico provocado

| Campo | Valor |
|---|---|
| Marca previa al incidente | 2026-09-22 19:31:56.153 |
| Filas alteradas | 20 |
| Stock antes | 19 910,000 |
| Stock después | 0,000 |
| Diagnóstico | Actualización masiva sin cláusula de filtro sobre `inventario.ExistenciaIngrediente` |

Es una transacción válida para el motor. Precisamente por eso ningún mecanismo de réplica la detendría, y
solo el respaldo permite revertirla. La marca temporal se registra en `dba.MarcaIncidente` en el momento
del daño, de modo que `05_Restore_Recovery.sql` no tenga que estimar la hora.

## 5. Control DBA-BKP-01

| Campo | Valor |
|---|---|
| Respaldos completos | 1 |
| Diferenciales | 1 |
| De registro | 2 |
| Sin suma de verificación | 0 |
| **Veredicto** | **CUMPLE** |

Espacio del registro de transacciones al cierre: 127,99 MB totales, 2,81 MB usados (2,20 %), razón de
espera `NOTHING`.

## 6. Correcciones aplicadas durante la ejecución

1. **Ruta sin separador final.** La primera corrida falló con error 3201, «Cannot open backup device
   `...\MSSQL\BackupDBSuperHamburguesas_FULL.bak`. Operating system error 5 (Acceso denegado)». Misma causa
   que en `03_Auditoria.sql`: `InstanceDefaultBackupPath` no incluye la barra final, de modo que el archivo
   apuntaba fuera de la carpeta de respaldos, donde la cuenta de servicio no tiene permiso de escritura.
2. **Guarda antes del incidente.** En esa misma corrida el script continuó pese a los errores y aplicó el
   incidente sin que existiera respaldo del cual revertirlo. Se agregó una guarda que consulta
   `msdb.dbo.backupset` y aborta si falta cualquiera de los tres tipos de respaldo. En la corrida definitiva
   la guarda reportó 1 completo, 1 diferencial y 1 de registro antes de permitir el incidente.
