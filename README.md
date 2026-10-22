# Administración de SQL Server · DBSuperHamburguesas

Implementación completa del trabajo de un DBA sobre una base de datos de negocio
en **Microsoft SQL Server 2022**: modelo físico, seguridad por roles y por
columna, auditoría, cadena de respaldos, restauración a un punto en el tiempo,
monitoreo, rendimiento y una validación final automatizada.

El proyecto tiene dos partes:

1. **Estándar técnico** (`docs/Entregable1_Estandar_SQLServer.pdf`): un catálogo de
   controles de administración de SQL Server (gobierno, codificación, seguridad,
   respaldos y monitoreo), cada uno con su código (`DBA-SEG-01`, `DBA-BKP-02`…).
2. **Implementación** (`scripts/`): los scripts T-SQL que aplican esos controles
   a la base `DBSuperHamburguesas` y las evidencias de su ejecución (`evidencias/`).

## Qué incluye

| Área | Contenido |
|---|---|
| Modelo | 6 esquemas de negocio (catálogo, inventario, proveedores, ventas, contabilidad, RR. HH.) y un esquema administrativo, con PK, FK, CHECK, UNIQUE, DEFAULT y datos de prueba reproducibles |
| Seguridad | 12 roles de dominio y 12 usuarios nominativos, mínimo privilegio, permisos a nivel de columna sobre datos sensibles y `DENY` al esquema administrativo |
| Auditoría | SQL Server Audit de servidor y de base de datos |
| Respaldos | Cadena completa + diferencial + registro, con `CHECKSUM` |
| Recuperación | Restauración a un punto en el tiempo (`STOPAT`) en una base alterna |
| Monitoreo | Informe de salud, crecimiento de archivos y umbrales de espacio libre |
| Rendimiento | Medición de una consulta antes y después de un índice justificado, con la reducción en números |
| Validación | `09_Validacion.sql`: 18 comprobaciones contra el catálogo de controles y `DBCC CHECKDB`. Resultado: **18 de 18 conformes** |

## Orden de ejecución

```
scripts/00_Diagnostico_Instancia.sql   Diagnóstico de la instancia
scripts/00_CreateDatabase.sql          Creación de la base
scripts/01_Modelo.sql                  Esquemas, tablas y datos de prueba
scripts/02_Seguridad.sql               Logins, roles, usuarios y permisos
scripts/03_Auditoria.sql               SQL Server Audit
scripts/04_Backup.sql                  Cadena de respaldos
scripts/04a_Reparar_Inventario.sql     Corrección de datos (incidente simulado)
scripts/05_Restore_Recovery.sql        Restauración a un punto en el tiempo
scripts/06_Monitoreo.sql               Informe de salud
scripts/07_Rendimiento.sql             Rendimiento
scripts/09_Validacion.sql              Cuadro de mando de validación final
```

Probado en SQL Server 2022 Express con SSMS. Los respaldos y la auditoría usan
la ruta de respaldo predeterminada de la instancia, sin rutas fijas.

> Las credenciales de los logins son académicas y no corresponden a ningún sistema real.

## Documentación

- `docs/Informe_Tecnico_Entregable2.pdf`: informe técnico de la implementación
- `docs/Runbook_Operacion.pdf`: procedimientos de operación
- `docs/Matriz_Seguridad.pdf` y `docs/Matriz_Trazabilidad.pdf`
- `evidencias/`: la salida de cada script, con fecha y hora

---

Proyecto académico del curso Bases de Datos III (TIIT3175.2), Universidad Invenio, 2026.
Equipo: Alejandro Rodríguez Zamora, Avril Madrigal Elizondo, Luis Alejandro Luna García y César Andrés Ubau Calvo.
