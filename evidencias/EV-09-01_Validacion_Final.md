# EV-09-01 · Cuadro de mando de validación final

> **Proyecto 2 · Entregable 2 — DBSuperHamburguesas**
> Instancia `EXPRESS2022` · SQL Server 2022 16.0.1200.5 Express · Intercalación `Modern_Spanish_CI_AS`
> Capturado por Alejandro Josué Rodríguez Zamora · 22 de septiembre de 2026, 19:42:31

**Script:** `09_Validacion.sql` · **Alcance:** los trece controles del catálogo del Entregable 1

## Resultado por comprobación

| N.º | Control | Prueba | Obtenido | Esperado | Veredicto |
|---|---|---|---|---|---|
| 1 | DBA-GOB-01 | Base en línea, en modelo FULL y con verificación de página CHECKSUM | ONLINE / FULL / CHECKSUM | ONLINE / FULL / CHECKSUM | CUMPLE |
| 2 | DBA-COD-01 | Ninguna tabla de negocio en el esquema `dbo` | 0 tablas | 0 tablas | CUMPLE |
| 3 | — | Las diecinueve tablas del modelo base existen en sus seis esquemas | 19 tablas | 19 tablas | CUMPLE |
| 4 | — | Claves foráneas y restricciones CHECK confiables y habilitadas | 0 con problema | 0 | CUMPLE |
| 5 | — | Doce roles de dominio y doce usuarios nominativos | 12 roles / 12 usuarios | 12 roles / 12 usuarios | CUMPLE |
| 6 | DBA-SEG-01 | Ningún permiso de acceso a datos otorgado directamente a un usuario | 0 permisos | 0 permisos | CUMPLE |
| 7 | DBA-SEG-02 | Ningún usuario de negocio en roles fijos de alcance amplio | 0 casos | 0 casos | CUMPLE |
| 8 | DBA-SEG-03 | Permisos a nivel de columna aplicados sobre los atributos sensibles | 24 concesiones por columna | al menos 9 | CUMPLE |
| 9 | DBA-SEG-03 | Las columnas sensibles no están concedidas a ningún rol de consulta | 0 fugas | 0 fugas | CUMPLE |
| 10 | DBA-SEG-04 | Auditoría de servidor activa | ACTIVA | ACTIVA | CUMPLE |
| 11 | DBA-SEG-04 | Especificación de base de datos con las tres categorías | 5 acciones | al menos 5 acciones | CUMPLE |
| 12 | DBA-BKP-01 | Cadena completa, diferencial y al menos dos de registro, con suma de verificación | 1C / 1D / 2L, sin checksum: 0 | ≥1C / ≥1D / ≥2L, sin checksum: 0 | CUMPLE |
| 13 | DBA-BKP-02 | Base alterna restaurada con STOPAT y en línea | ONLINE | ONLINE | CUMPLE |
| 14 | DBA-BKP-02 | El dato erróneo no está presente en la base recuperada | verificado en `05_Restore_Recovery.sql`, sección 4 | 0 filas con el valor erróneo | CUMPLE |
| 15 | DBA-MON-02 | Todos los archivos con crecimiento en incrementos fijos | 0 con crecimiento porcentual | 0 | CUMPLE |
| 16 | DBA-MON-02 | Espacio libre por encima del umbral del 20 % en todos los archivos | 0 archivos en alerta | 0 archivos | CUMPLE |
| 17 | — | Total del pedido igual a subtotal más impuesto en todas las filas | 0 inconsistencias | 0 | CUMPLE |
| 18 | DBA-COD-02 | El esquema administrativo está denegado a los doce roles de dominio | 12 roles con DENY | 12 roles | CUMPLE |

## Veredicto global

| Momento | Base | Comprobaciones | Cumplen | No cumplen | A revisar | Veredicto |
|---|---|---|---|---|---|---|
| 2026-09-22 19:42:31 | DBSuperHamburguesas | 18 | 18 | 0 | 0 | **AMBIENTE CONFORME** |

## Integridad física y lógica

La sección final ejecuta `DBCC CHECKDB` sobre la base productiva con `NO_INFOMSGS` y `ALL_ERRORMSGS`.
La ausencia de mensajes equivale a la ausencia de errores de asignación y de consistencia.

## Corrección aplicada durante la ejecución

La corrida anterior devolvió un NO CUMPLE en la comprobación 3: obtenido 19 tablas contra un esperado de
18. Se contrastó contra el *Diccionario mínimo de datos* de la sección 6 del enunciado, que define
19 tablas de negocio: `catalogo` 5, `ventas` 4, `inventario` 3, `rrhh` 3, `proveedores` 2 y
`contabilidad` 2. El modelo implementado era correcto; el valor esperado del script de validación era el
equivocado. Se corrigió el esperado a 19 y la comprobación pasó a CUMPLE, con lo que el ambiente queda
conforme en las dieciocho comprobaciones.
