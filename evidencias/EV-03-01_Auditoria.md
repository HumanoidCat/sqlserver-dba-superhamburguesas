# EV-03-01 · Mecanismo de auditoría y eventos registrados

> **Proyecto 2 · Entregable 2 — DBSuperHamburguesas**
> Instancia `EXPRESS2022` · SQL Server 2022 16.0.1200.5 Express · Intercalación `Modern_Spanish_CI_AS`
> Capturado por Alejandro Josué Rodríguez Zamora · 22 de septiembre de 2026, 19:17


**Script:** `03_Auditoria.sql` · **Controles:** DBA-SEG-04, DBA-GOB-02

## 1. Acreditación del mecanismo nativo

| Campo | Valor |
|---|---|
| Edición | Express Edition (64-bit) |
| Versión mayor del motor | 16 |
| Soporta auditoría de servidor | 1 |
| Soporta auditoría de base de datos | 1 |
| Decisión | Mecanismo NATIVO. Sin excepción. |

La comprobación se hace contra la versión del motor y no contra el nombre de la edición. Microsoft Learn,
en *SQL Server Audit (Database Engine)*: «All editions of SQL Server support server level audits. In
SQL Server 2016 (13.x) with Service Pack 1 and later versions, all editions support database level audits.»
No se tramita excepción porque no existe limitación técnica.

## 2. Configuración vigente

| Campo | Valor |
|---|---|
| Auditoría de servidor | `Audit_SuperHamburguesas` |
| Estado | ACTIVA |
| Destino | FILE |
| Ante fallo | CONTINUE (decisión declarada en el encabezado del script) |
| Ruta del archivo | Carpeta de respaldo por defecto de la instancia, resuelta desde el catálogo |
| Tamaño máximo por archivo | 64 MB |
| Máximo de archivos | 24 |
| Retardo de cola | 1 000 ms |
| Especificación de base de datos | `DBAudit_SuperHamburguesas`, ACTIVA, 5 acciones |

## 3. Eventos registrados por categoría

| Categoría | Eventos | Primer evento | Último evento | Veredicto |
|---|---|---|---|---|
| 1. UPDATE sobre `rrhh.Empleado` | 6 | 2026-09-23 00:33:32.970 | 2026-09-23 01:17:15.395 | **CUMPLE** |
| 2. INSERT / UPDATE / DELETE sobre `contabilidad.MovimientoContable` | 10 | 2026-09-23 00:33:32.977 | 2026-09-23 01:17:15.399 | **CUMPLE** |
| 3. Cambio de membresía de rol | 19 | 2026-09-23 00:33:32.980 | 2026-09-23 01:17:15.400 | **CUMPLE** |

Cada evento registra los cuatro atributos que exige la sección 7.4 del enunciado: fecha y hora, usuario,
objeto y operación, además de la sentencia literal ejecutada.

## 4. Control DBA-SEG-04

| Campo | Valor |
|---|---|
| Mecanismo | SQL Server Audit nativo (server audit + database audit specification) |
| Excepción tramitada | No. No existe limitación técnica: Express soporta ambos niveles. |
| Categorías exigidas | 3 |
| Categorías con evidencia | 3 |
| Retención configurada | 24 archivos de 64 MB. Cubre los 12 meses del requisito 10.5.1 de PCI DSS v4.0. |
| **Veredicto** | **CUMPLE** |

## 5. Riesgo residual declarado

Un miembro de `sysadmin` puede desactivar la auditoría. Mitigación: la propia desactivación queda
registrada por el rastro antes de detenerse. Se acepta como riesgo residual inherente al modelo de
privilegios del motor.

## 6. Corrección aplicada durante la ejecución

La primera corrida devolvió cero eventos en las tres categorías y el control en NO CUMPLE. Causa:
`SERVERPROPERTY('InstanceDefaultBackupPath')` devuelve la carpeta **sin separador final**, de modo que la
concatenación producía un patrón de archivo inexistente y `sys.fn_get_audit_file` no encontraba nada.
La auditoría sí estaba grabando. Se corrigió resolviendo la ruta desde `sys.server_file_audits`.
