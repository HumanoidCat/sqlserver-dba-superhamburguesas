# EV-00-01 · Diagnóstico de la instancia SQL Server

| Campo | Valor |
|---|---|
| Fecha y hora de ejecución | 2026-08-29 00:09:02.890 |
| Script ejecutado | `00_Diagnostico_Instancia.sql` |
| Ejecutado por | `ALEJANDRO\Alejandro` (miembro de sysadmin) |

## 1. Identificación de la instancia

| Propiedad | Valor |
|---|---|
| Servidor | ALEJANDRO |
| Instancia | EXPRESS2022 |
| Edición | **Express Edition (64-bit)** |
| Versión del producto | 16.0.1190.2 |
| Nivel | RTM (RTM-GDR, KB5102334) |
| Producto | Microsoft SQL Server 2022 |
| Collation | Modern_Spanish_CI_AS |

## 2. Modo de autenticación

| Propiedad | Valor |
|---|---|
| `IsIntegratedSecurityOnly` | 0 |
| Modo | **Mixto (SQL Server y Windows)** |
| Consecuencia | La instancia admite los 12 logins SQL exigidos por la sección 7.2. No se requiere cambio de configuración ni reinicio del servicio. |

## 3. Disponibilidad de SQL Server Audit

> **Corrección del 29/08/2026 (hallazgo H-01 de la auditoría documental).** La primera versión de esta evidencia concluyó que Express no soporta SQL Server Audit y activó un mecanismo alternativo por *triggers*. **Esa conclusión era incorrecta** y quedó derivada de la salida del script de diagnóstico, que aplicaba un criterio obsoleto basado en el nombre de la edición.

### Situación real, verificada contra la documentación oficial

Microsoft Learn, *SQL Server Audit (Database Engine)*:

> "All editions of SQL Server support server level audits. In SQL Server 2016 (13.x) with Service Pack 1 and later versions, all editions support database level audits. Before SQL Server 2016 (13.x), database level auditing was limited to Enterprise, Developer, and Evaluation editions."

La tabla de ediciones de SQL Server 2022, sección *Security*, confirma para las cinco ediciones —Enterprise, Standard, Web, Express with Advanced Services y Express—:

| Característica | Enterprise | Standard | Web | Express Adv. | Express |
|---|---|---|---|---|---|
| Server audit | Yes | Yes | Yes | Yes | Yes |
| Database audit | Yes | Yes | Yes | Yes | Yes |

La instancia auditada es SQL Server 2022, versión de producto **16.0.1190.2** (versión mayor 16 ≥ 13), por lo que **cumple la condición de disponibilidad de auditoría a nivel de base de datos**.

### Decisión adoptada

Se emplea el **mecanismo nativo SQL Server Audit**, tal como lo solicita de primera instancia la sección 7.4 del enunciado. **No se tramita excepción**, porque no existe limitación técnica que la justifique.

| Categoría exigida por la sección 7.4 | Implementación nativa |
|---|---|
| `UPDATE` sobre `rrhh.Empleado` | `DATABASE AUDIT SPECIFICATION` con acción `UPDATE ON OBJECT::rrhh.Empleado` |
| `INSERT` / `UPDATE` / `DELETE` sobre `contabilidad.MovimientoContable` | `DATABASE AUDIT SPECIFICATION` con las tres acciones sobre el objeto |
| Cambios de membresía de roles de base de datos | Grupo de acción `DATABASE_ROLE_MEMBER_CHANGE_GROUP` |

La consulta del registro se realiza con `sys.fn_get_audit_file`. En SQL Server 2022 esa función exige el permiso **`VIEW SERVER SECURITY AUDIT`**; en SQL Server 2019 y anteriores exigía `CONTROL SERVER`.

### Lección registrada para el informe

La disponibilidad de una característica **no debe inferirse del nombre de la edición**. SQL Server 2016 SP1 reasignó a todas las ediciones un conjunto amplio de características que antes eran exclusivas de Enterprise —entre ellas la auditoría a nivel de base de datos, *Row-Level Security*, *Dynamic Data Masking* y *Always Encrypted*—. El criterio correcto es consultar la tabla de ediciones de la versión concreta y comprobarlo funcionalmente contra el motor.

## 4. Rutas por defecto de la instancia

| Propiedad | Valor |
|---|---|
| Ruta de datos | `C:\Program Files\Microsoft SQL Server\MSSQL16.EXPRESS2022\MSSQL\DATA\` |
| Ruta de log | `C:\Program Files\Microsoft SQL Server\MSSQL16.EXPRESS2022\MSSQL\DATA\` |
| Ruta de respaldo | `C:\Program Files\Microsoft SQL Server\MSSQL16.EXPRESS2022\MSSQL\Backup\` |

`00_CreateDatabase.sql` toma estas rutas mediante `SERVERPROPERTY`, por lo que ninguna ruta queda incrustada en el código fuente.

## 5. Estado previo

La consulta sobre `sys.databases` devolvió **cero filas**: ni `DBSuperHamburguesas` ni `DBSuperHamburguesas_RECOVERY` existían al momento del diagnóstico. El ambiente parte de cero y la ejecución es reproducible desde el script 00.

---

## Restricciones de Express Edition aplicables al proyecto

Se documentan aquí porque condicionan varias secciones del entregable y deben aparecer declaradas en el informe técnico, no descubrirse durante la defensa.

| # | Restricción de Express | Sección afectada | Tratamiento adoptado |
|---|---|---|---|
| 1 | ~~Sin SQL Server Audit~~ **No aplica** | 7.4 Auditoría | Corregido: Express **sí** soporta *server audit* y *database audit*. Se usa el mecanismo nativo. |
| 2 | Sin SQL Server Agent | 7.5 Respaldo | La periodicidad se declara en el estándar y se implementa con el Programador de tareas de Windows invocando `sqlcmd`; se documenta como control compensatorio |
| 3 | Sin compresión de respaldos | 7.5 Respaldo | Se documenta el impacto en tiempo y espacio; no afecta la validez de la cadena FULL/DIFF/LOG |
| 4 | Sin Transparent Data Encryption ni cifrado de respaldo | 7.3 / E1 dominio 2 | El estándar del Entregable 1 define **cuándo** aplica el cifrado; el Entregable 2 declara que la edición no permite demostrarlo y aplica control compensatorio de acceso al sistema de archivos |
| 5 | Límite de 10 GB por base de datos | 7.1 Dimensionamiento | El dimensionamiento previsto (256 MB de datos) está muy por debajo del techo; se declara el límite como restricción de capacidad |
| 6 | Límite de **1 410 MB** de memoria para el *buffer pool* y menor entre 1 socket o 4 núcleos | 7.6 Monitoreo y caso de rendimiento | Se declara al interpretar las métricas: las lecturas físicas serán proporcionalmente más altas que en una edición sin tope de memoria |

**No afectadas por Express** — y son el 82,5 % de la rúbrica (incluida ya la auditoría nativa): SQL Server Audit (servidor y base de datos), modelo de recuperación FULL, respaldos FULL/DIFF/LOG, restauración a un punto en el tiempo con `STOPAT`, `DBCC CHECKDB`, roles y permisos a nivel de columna, `EXECUTE AS`, esquemas, restricciones y vistas de administración dinámica. La estrategia del proyecto se mantiene íntegra.
