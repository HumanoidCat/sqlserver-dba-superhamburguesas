# EV-02-01 · Modelo de seguridad y mínimo privilegio

> **Proyecto 2 · Entregable 2 — DBSuperHamburguesas**
> Instancia `EXPRESS2022` · SQL Server 2022 16.0.1200.5 Express · Intercalación `Modern_Spanish_CI_AS`
> Capturado por Alejandro Josué Rodríguez Zamora · 22 de septiembre de 2026


**Script:** `02_Seguridad.sql` · **Controles:** DBA-SEG-01, DBA-SEG-02, DBA-SEG-03

## Resultado

| Medida | Valor obtenido |
|---|---|
| Roles de base de datos creados | 12 (consulta y gestión por cada uno de los seis dominios) |
| Usuarios nominativos creados | 12 |
| Membresías asignadas | 13 (una usuaria con doble rol, para demostrar acumulación) |
| Permisos concedidos | 101, todos al rol |
| Permisos concedidos directamente a un usuario | 0 |
| Denegaciones comprobadas rol × objeto | 60 |
| Concesiones a nivel de columna sobre atributos sensibles | 24 |
| Fugas de columnas sensibles hacia roles de consulta | 0 |
| Pruebas de autorización ejecutadas | 15 |
| Pruebas con el resultado esperado | 15 |

## Controles verificados

| Control | Comprobación | Veredicto |
|---|---|---|
| DBA-SEG-01 | Ningún permiso de acceso a datos otorgado directamente a un usuario | **CUMPLE** |
| DBA-SEG-02 | Ningún usuario de negocio en roles fijos de alcance amplio | **CUMPLE** |
| DBA-SEG-03 | Permisos a nivel de columna aplicados sobre los atributos sensibles (24 concesiones, se exigían al menos 9) | **CUMPLE** |
| DBA-SEG-03 | Las columnas sensibles no están concedidas a ningún rol de consulta | **CUMPLE** |

## Nota técnica sobre las pruebas positivas

Bajo permisos a nivel de columna, `SELECT COUNT(*)` falla con error 230 aunque el usuario tenga columnas
concedidas, porque el motor evalúa el asterisco contra el objeto completo. Las pruebas positivas cuentan
una columna concedida de forma explícita. El comportamiento no es un defecto del control: es la evidencia
de que el control opera a nivel de columna y no a nivel de tabla.

## Nota sobre los permisos CONNECT

`CREATE USER` otorga automáticamente `CONNECT` sobre la base a cada entidad creada. Esos 12 permisos
aparecen en el catálogo como concesiones directas a usuario y se excluyen de la comprobación de
DBA-SEG-01, que evalúa permisos de acceso a datos. El script los reporta por separado para que la
exclusión quede a la vista y no quede la impresión de un dato omitido.

## Registro

Los resultados de las 15 pruebas quedan almacenados en `dba.PruebaAutorizacion`, dentro de la propia base,
con la sentencia probada, el resultado esperado y el obtenido.
