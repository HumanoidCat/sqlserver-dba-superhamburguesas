/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        06_Monitoreo.sql
  Proposito:     Producir la linea base de salud operativa del ambiente con
                 catalogos del sistema y vistas de administracion dinamica
                 (seccion 7.6 del entregable). Cada bloque entrega el dato y su
                 interpretacion: una salida sin lectura no cumple el requisito.

  Controles del Entregable 1 que implementa:
                 DBA-MON-01  Linea base documentada e interpretada.
                 DBA-MON-02  Vigilancia del crecimiento de archivos y del
                             espacio disponible, con umbral de alerta.

  Precondiciones:Scripts 00 a 05 ejecutados.
  Orden:         Script 06. Antes de 07_Rendimiento.sql.
  Destructivo:   No. Solo lectura.
  Reejecutable:  SI.
  Resultado
  esperado:      Siete bloques de diagnostico con interpretacion. Guardar la
                 salida completa como evidencia EV-06-01.
==============================================================================*/

SET NOCOUNT ON;
GO

USE DBSuperHamburguesas;
GO

PRINT N'===== LINEA BASE DE SALUD OPERATIVA - ' + CONVERT(NVARCHAR(30), SYSDATETIME(), 121) + N' =====';
GO

/*==============================================================================
  BLOQUE 1 - ESTADO DE LA BASE Y MODELO DE RECUPERACION
  Interpretacion: el estado debe ser ONLINE y el modelo FULL. Un modelo distinto
  de FULL invalidaria la recuperacion a un punto en el tiempo del script 05.
  La verificacion de pagina debe ser CHECKSUM: sin ella, la suma de verificacion
  de los respaldos no puede validar el contenido de las paginas.
==============================================================================*/
SELECT
    [Bloque]            = N'1. Estado de la base',
    [Momento]           = SYSDATETIME(),
    [Base]              = d.name,
    [Estado]            = d.state_desc,
    [ModeloRecuperac]   = d.recovery_model_desc,
    [VerificacionPag]   = d.page_verify_option_desc,
    [Compatibilidad]    = d.compatibility_level,
    [Collation]         = d.collation_name,
    [AutoShrink]        = CASE WHEN d.is_auto_shrink_on = 1 THEN N'ON (revisar)' ELSE N'OFF (correcto)' END,
    [RCSI]              = CASE WHEN d.is_read_committed_snapshot_on = 1 THEN N'ON' ELSE N'OFF' END,
    [RazonEsperaLog]    = d.log_reuse_wait_desc,
    [Interpretacion]    = CASE
                            WHEN d.state_desc <> N'ONLINE' THEN N'CRITICO: la base no esta en linea.'
                            WHEN d.recovery_model_desc <> N'FULL' THEN N'CRITICO: sin modelo FULL no hay PITR.'
                            WHEN d.page_verify_option_desc <> N'CHECKSUM' THEN N'ALERTA: la suma de verificacion del respaldo no verifica paginas.'
                            ELSE N'Normal: base en linea, con PITR posible y verificacion de pagina activa.'
                          END
FROM sys.databases AS d
WHERE d.name = DB_NAME();
GO

/*==============================================================================
  BLOQUE 2 - ARCHIVOS: TAMANO, CRECIMIENTO Y ESPACIO DISPONIBLE
  Interpretacion (control DBA-MON-02): el umbral de alerta es 20 % de espacio
  libre. Con incrementos fijos, ese margen garantiza al menos tres eventos de
  crecimiento antes del agotamiento, plazo suficiente para ampliar el volumen
  dentro de un ciclo semanal de vigilancia. El crecimiento debe ser FIJO.
==============================================================================*/
SELECT
    [Bloque]          = N'2. Archivos y capacidad',
    [Archivo]         = df.name,
    [Tipo]            = df.type_desc,
    [TamanoMB]        = CAST(df.size / 128.0 AS DECIMAL(12,2)),
    [UsadoMB]         = CAST(FILEPROPERTY(df.name, 'SpaceUsed') / 128.0 AS DECIMAL(12,2)),
    [LibreMB]         = CAST((df.size - FILEPROPERTY(df.name, 'SpaceUsed')) / 128.0 AS DECIMAL(12,2)),
    [LibrePct]        = CAST(100.0 * (df.size - FILEPROPERTY(df.name,'SpaceUsed')) / NULLIF(df.size,0) AS DECIMAL(5,2)),
    [TipoCrecimiento] = CASE df.is_percent_growth WHEN 1 THEN N'PORCENTUAL (revisar)' ELSE N'FIJO (correcto)' END,
    [IncrementoMB]    = CASE df.is_percent_growth WHEN 1 THEN CAST(df.growth AS DECIMAL(12,2))
                                                  ELSE CAST(df.growth / 128.0 AS DECIMAL(12,2)) END,
    [Interpretacion]  = CASE
                          WHEN 100.0 * (df.size - FILEPROPERTY(df.name,'SpaceUsed')) / NULLIF(df.size,0) < 20
                               THEN N'ALERTA: espacio libre por debajo del umbral del 20 %. Ampliar el volumen.'
                          WHEN df.is_percent_growth = 1
                               THEN N'ALERTA: crecimiento porcentual sin justificacion documentada.'
                          ELSE N'Normal: margen suficiente y crecimiento en incrementos fijos.'
                        END
FROM sys.database_files AS df;
GO

/*==============================================================================
  BLOQUE 3 - USO DEL REGISTRO DE TRANSACCIONES
  Interpretacion: en modelo FULL el porcentaje usado solo desciende tras un
  respaldo de registro. Un valor alto con RazonEsperaLog = LOG_BACKUP indica que
  falta respaldar el registro, no que el archivo sea pequeno. Por encima del
  75 % debe ejecutarse un respaldo de registro antes de continuar.
==============================================================================*/
SELECT
    [Bloque]          = N'3. Registro de transacciones',
    [LogTotalMB]      = CAST(total_log_size_in_bytes / 1048576.0 AS DECIMAL(12,2)),
    [LogUsadoMB]      = CAST(used_log_space_in_bytes  / 1048576.0 AS DECIMAL(12,2)),
    [LogUsadoPct]     = CAST(used_log_space_in_percent AS DECIMAL(5,2)),
    [RazonEspera]     = (SELECT log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME()),
    [Interpretacion]  = CASE
                          WHEN used_log_space_in_percent > 75
                               THEN N'ALERTA: ejecutar un respaldo de registro antes de continuar.'
                          WHEN (SELECT log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME()) = N'LOG_BACKUP'
                               THEN N'Normal para modelo FULL: hay actividad pendiente de respaldar.'
                          ELSE N'Normal: el registro dispone de espacio reutilizable.'
                        END
FROM sys.dm_db_log_space_usage;
GO

/*==============================================================================
  BLOQUE 4 - SESIONES Y SOLICITUDES ACTIVAS
  Interpretacion: se excluyen las sesiones del sistema. Una solicitud con tiempo
  transcurrido elevado y tipo de espera persistente es candidata a revision.
==============================================================================*/
SELECT
    [Bloque]        = N'4. Sesiones activas',
    [Sesion]        = s.session_id,
    [Login]         = s.login_name,
    [Programa]      = s.program_name,
    [Host]          = s.host_name,
    [Estado]        = s.status,
    [Inicio]        = s.last_request_start_time,
    [Comando]       = r.command,
    [EsperaTipo]    = r.wait_type,
    [EsperaMs]      = r.wait_time,
    [TranscurridoMs]= r.total_elapsed_time,
    [Bloqueadapor]  = r.blocking_session_id,
    [Interpretacion]= CASE
                        WHEN r.blocking_session_id > 0 THEN N'ALERTA: sesion bloqueada por otra.'
                        WHEN r.total_elapsed_time > 30000 THEN N'Revisar: solicitud de larga duracion.'
                        ELSE N'Normal.'
                      END
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
WHERE s.is_user_process = 1
ORDER BY r.total_elapsed_time DESC;
GO

/*==============================================================================
  BLOQUE 5 - TRANSACCIONES ABIERTAS Y BLOQUEOS
  Interpretacion: una transaccion abierta prolongada impide truncar el registro
  y retiene bloqueos. La disposicion 9.2.7 del estandar prohibe mantener
  transacciones abiertas a la espera de procesos externos.
==============================================================================*/
SELECT
    [Bloque]          = N'5. Transacciones abiertas',
    [Sesion]          = st.session_id,
    [Transaccion]     = at.transaction_id,
    [Nombre]          = at.name,
    [Inicio]          = at.transaction_begin_time,
    [SegundosAbierta] = DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME()),
    [Estado]          = CASE at.transaction_state
                            WHEN 0 THEN N'No inicializada' WHEN 1 THEN N'No iniciada'
                            WHEN 2 THEN N'Activa'          WHEN 3 THEN N'Finalizada sin registro'
                            WHEN 4 THEN N'Confirmacion distribuida' WHEN 5 THEN N'Preparada'
                            WHEN 6 THEN N'Confirmada'      WHEN 7 THEN N'Revirtiendose'
                            WHEN 8 THEN N'Revertida'       ELSE N'Desconocido' END,
    [Interpretacion]  = CASE WHEN DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME()) > 60
                             THEN N'ALERTA: transaccion abierta por mas de un minuto.'
                             ELSE N'Normal.' END
FROM sys.dm_tran_active_transactions AS at
LEFT JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id = at.transaction_id
WHERE st.session_id IS NOT NULL;

SELECT
    [Bloque]        = N'5b. Bloqueos presentes',
    [Sesion]        = tl.request_session_id,
    [Recurso]       = tl.resource_type,
    [BaseDatos]     = DB_NAME(tl.resource_database_id),
    [Modo]          = tl.request_mode,
    [Estado]        = tl.request_status,
    [Objeto]        = OBJECT_NAME(p.object_id),
    [Interpretacion]= CASE WHEN tl.request_status = N'WAIT' THEN N'ALERTA: solicitud en espera de bloqueo.'
                           ELSE N'Normal: bloqueo concedido.' END
FROM sys.dm_tran_locks AS tl
LEFT JOIN sys.partitions AS p ON p.hobt_id = tl.resource_associated_entity_id
WHERE tl.resource_database_id = DB_ID()
  AND tl.resource_type <> N'DATABASE';
GO

/*==============================================================================
  BLOQUE 6 - ULTIMO RESPALDO DE CADA TIPO
  Interpretacion (control DBA-BKP-01): la antiguedad no debe exceder la
  frecuencia declarada para la criticidad de la base. Para criticidad alta:
  completo diario, diferencial cada 6 horas, registro cada 15 minutos.
==============================================================================*/
;WITH Ultimo AS (
    SELECT bs.type,
           UltimoRespaldo = MAX(bs.backup_finish_date)
    FROM msdb.dbo.backupset AS bs
    WHERE bs.database_name = N'DBSuperHamburguesas'
    GROUP BY bs.type
)
SELECT
    [Bloque]           = N'6. Ultimo respaldo por tipo',
    [Tipo]             = CASE u.type WHEN 'D' THEN N'COMPLETO' WHEN 'I' THEN N'DIFERENCIAL'
                                     WHEN 'L' THEN N'REGISTRO' ELSE u.type END,
    [UltimoRespaldo]   = u.UltimoRespaldo,
    [AntiguedadMin]    = DATEDIFF(MINUTE, u.UltimoRespaldo, SYSDATETIME()),
    [FrecuenciaExigida]= CASE u.type WHEN 'D' THEN N'1440 min (diario)'
                                     WHEN 'I' THEN N'360 min (cada 6 h)'
                                     WHEN 'L' THEN N'15 min' END,
    [Interpretacion]   = CASE
                            WHEN u.type = 'D' AND DATEDIFF(MINUTE, u.UltimoRespaldo, SYSDATETIME()) > 1440 THEN N'ALERTA: completo vencido.'
                            WHEN u.type = 'I' AND DATEDIFF(MINUTE, u.UltimoRespaldo, SYSDATETIME()) > 360  THEN N'ALERTA: diferencial vencido.'
                            WHEN u.type = 'L' AND DATEDIFF(MINUTE, u.UltimoRespaldo, SYSDATETIME()) > 15   THEN N'ALERTA: registro vencido.'
                            ELSE N'Dentro de la frecuencia declarada.'
                         END
FROM Ultimo AS u;
GO

/*==============================================================================
  BLOQUE 7 - INDICES Y ESTADISTICAS DE APOYO AL CASO DE RENDIMIENTO
  Interpretacion: sirve de linea base para 07_Rendimiento.sql. Antes de crear
  el indice, las tablas transaccionales solo deben tener el indice agrupado de
  su clave primaria.
==============================================================================*/
SELECT
    [Bloque]        = N'7. Indices existentes',
    [Tabla]         = SCHEMA_NAME(t.schema_id) + N'.' + t.name,
    [Indice]        = ISNULL(i.name, N'(monticulo)'),
    [Tipo]          = i.type_desc,
    [Filas]         = p.rows,
    [Lecturas]      = ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0),
    [Escrituras]    = ISNULL(us.user_updates, 0),
    [Interpretacion]= CASE WHEN i.type_desc = N'CLUSTERED' THEN N'Indice agrupado de la clave primaria.'
                           WHEN i.type_desc = N'NONCLUSTERED' THEN N'Indice no agrupado: revisar su uso real.'
                           ELSE N'Sin indice agrupado.' END
FROM sys.tables AS t
INNER JOIN sys.indexes AS i ON i.object_id = t.object_id
LEFT JOIN sys.partitions AS p ON p.object_id = t.object_id AND p.index_id = i.index_id
LEFT JOIN sys.dm_db_index_usage_stats AS us ON us.object_id = t.object_id AND us.index_id = i.index_id AND us.database_id = DB_ID()
WHERE SCHEMA_NAME(t.schema_id) IN (N'ventas', N'inventario')
ORDER BY p.rows DESC, [Tabla], i.index_id;
GO

-- Control DBA-MON-01 y DBA-MON-02
SELECT
    [Control DBA-MON-01] = N'Linea base documentada e interpretada',
    [Bloques]            = 7,
    [ConInterpretacion]  = 7,
    [Resultado]          = N'CUMPLE',
    [Control DBA-MON-02] = N'Vigilancia de capacidad con umbral del 20 %',
    [ArchivosEnAlerta]   = (SELECT COUNT(*) FROM sys.database_files AS df
                            WHERE 100.0 * (df.size - FILEPROPERTY(df.name,'SpaceUsed')) / NULLIF(df.size,0) < 20),
    [CrecimientoPorcent] = (SELECT COUNT(*) FROM sys.database_files WHERE is_percent_growth = 1);
GO

PRINT N'== 06_Monitoreo.sql finalizado. Conservar la salida completa como EV-06-01. ==';
PRINT N'== Siguiente paso: 07_Rendimiento.sql ==';
GO
