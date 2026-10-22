/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        05_Restore_Recovery.sql
  Proposito:     Completar la cadena de recuperacion: restaurar sobre una base
                 alterna aplicando completo, diferencial y registro, detener la
                 recuperacion en la marca previa al incidente con STOPAT,
                 validar los datos, comprobar la integridad y medir el tiempo
                 real contra el objetivo declarado (seccion 7.5, pasos 9 y 10).

  Controles del Entregable 1 que implementa:
                 DBA-BKP-02  Prueba de restauracion sobre base alterna, con
                             tiempo medido y comparado contra el RTO.

  Precondiciones:1) 04_Backup.sql ejecutado por completo, con el incidente
                    provocado y el respaldo de registro 02 tomado.
                 2) Existen dba.ConfiguracionRespaldo y dba.MarcaIncidente.
  Orden:         Script 05. Despues de 04_Backup.sql.
  Destructivo:   SI sobre la base alterna DBSuperHamburguesas_RECOVERY, que se
                 elimina y se reconstruye. NUNCA toca la base productiva.
  Reejecutable:  SI.
  Resultado
  esperado:      Base alterna restaurada al instante previo al incidente, con
                 el inventario intacto. Ocho conjuntos de salida. Guardar como
                 EV-05-01 a EV-05-06.

  ---------------------------------------------------------------------------
  DECISIONES DE IMPLEMENTACION
  ---------------------------------------------------------------------------
  Restauracion sobre base alterna
    El enunciado lo exige y la razon es practica: restaurar sobre la base
    productiva destruiria el ambiente de demostracion y haria imposible mostrar
    el contraste entre el estado danado y el estado recuperado. Con base alterna
    ambos estados coexisten y pueden compararse en la misma consulta.

  Por que el STOPAT va en el ultimo respaldo de registro
    La cadena se aplica completa y sin recuperar hasta el ultimo tramo. El
    registro 01 es anterior al incidente, de modo que se aplica entero. El
    registro 02 contiene la transaccion danina, y es en ese tramo donde la
    recuperacion debe detenerse en la marca registrada por 04_Backup.sql.

  RESTORE VERIFYONLY como control complementario
    Se ejecuta antes de la restauracion real, pero se declara de forma expresa
    que no la sustituye: comprueba que el conjunto de respaldo es legible y que
    las sumas de verificacion cuadran, no que los datos sean recuperables. La
    prueba valida es la restauracion completa de la SECCION 3.

  Medicion del tiempo
    Se cronometra desde el inicio de la primera sentencia de restauracion hasta
    que la base alterna queda en linea, y se compara con el RTO declarado en
    dba.ObjetivoRecuperacion. Si lo excediera, la SECCION 6 lo registra como
    hallazgo en lugar de ocultarlo.
==============================================================================*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE master;
GO

/*==============================================================================
  SECCION 0 - PRECONDICIONES Y RECUPERACION DE PARAMETROS
==============================================================================*/
IF DB_ID(N'DBSuperHamburguesas') IS NULL
BEGIN
    RAISERROR(N'No existe la base productiva DBSuperHamburguesas.', 16, 1); RETURN;
END
IF NOT EXISTS (SELECT 1 FROM DBSuperHamburguesas.dba.MarcaIncidente)
BEGIN
    RAISERROR(N'No hay marca temporal registrada. Ejecute 04_Backup.sql antes de este script.', 16, 1); RETURN;
END
GO

-- EV-05-01: parametros de la restauracion
SELECT
    [Momento]        = SYSDATETIME(),
    [MarcaSTOPAT]    = CONVERT(NVARCHAR(30), m.FechaHoraPrevia, 121),
    [FilasAlteradas] = m.FilasAlteradas,
    [BaseAlterna]    = (SELECT Valor FROM DBSuperHamburguesas.dba.ConfiguracionRespaldo WHERE Clave = N'BaseAlterna'),
    [Cadena]         = N'FULL (NORECOVERY) -> DIFF (NORECOVERY) -> LOG 01 (NORECOVERY) -> LOG 02 (STOPAT, RECOVERY)'
FROM DBSuperHamburguesas.dba.MarcaIncidente AS m
WHERE m.MarcaID = (SELECT MAX(MarcaID) FROM DBSuperHamburguesas.dba.MarcaIncidente);
GO


/*==============================================================================
  SECCION 1 - CONTROL COMPLEMENTARIO: LEGIBILIDAD DE LOS RESPALDOS
  No sustituye la restauracion real. Se ejecuta para dejar constancia de que la
  cadena es legible antes de intentar aplicarla.
==============================================================================*/
DECLARE @full NVARCHAR(400) = (SELECT Valor FROM DBSuperHamburguesas.dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoFull');
DECLARE @diff NVARCHAR(400) = (SELECT Valor FROM DBSuperHamburguesas.dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoDiff');
DECLARE @l01  NVARCHAR(400) = (SELECT Valor FROM DBSuperHamburguesas.dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoLog01');
DECLARE @l02  NVARCHAR(400) = (SELECT Valor FROM DBSuperHamburguesas.dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoLog02');
DECLARE @sql  NVARCHAR(MAX);

SET @sql = N'RESTORE VERIFYONLY FROM DISK = ' + QUOTENAME(@full,'''') + N' WITH CHECKSUM;'; EXEC sys.sp_executesql @sql;
SET @sql = N'RESTORE VERIFYONLY FROM DISK = ' + QUOTENAME(@diff,'''') + N' WITH CHECKSUM;'; EXEC sys.sp_executesql @sql;
SET @sql = N'RESTORE VERIFYONLY FROM DISK = ' + QUOTENAME(@l01 ,'''') + N' WITH CHECKSUM;'; EXEC sys.sp_executesql @sql;
SET @sql = N'RESTORE VERIFYONLY FROM DISK = ' + QUOTENAME(@l02 ,'''') + N' WITH CHECKSUM;'; EXEC sys.sp_executesql @sql;
PRINT N'Los cuatro conjuntos de respaldo son legibles. Esto NO sustituye la restauracion.';
GO


/*==============================================================================
  SECCION 2 - PREPARACION DE LA BASE ALTERNA (DESTRUCTIVO SOBRE LA ALTERNA)
==============================================================================*/
DECLARE @RecrearBaseAlterna BIT = 1;

IF @RecrearBaseAlterna = 1 AND DB_ID(N'DBSuperHamburguesas_RECOVERY') IS NOT NULL
BEGIN
    ALTER DATABASE DBSuperHamburguesas_RECOVERY SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DBSuperHamburguesas_RECOVERY;
    PRINT N'Base alterna previa eliminada.';
END
GO


/*==============================================================================
  SECCION 3 - RESTAURACION DE LA CADENA CON PUNTO EN EL TIEMPO
==============================================================================*/
DECLARE @inicio DATETIME2(3) = SYSDATETIME();

DECLARE @full NVARCHAR(400) = (SELECT Valor FROM DBSuperHamburguesas.dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoFull');
DECLARE @diff NVARCHAR(400) = (SELECT Valor FROM DBSuperHamburguesas.dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoDiff');
DECLARE @l01  NVARCHAR(400) = (SELECT Valor FROM DBSuperHamburguesas.dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoLog01');
DECLARE @l02  NVARCHAR(400) = (SELECT Valor FROM DBSuperHamburguesas.dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoLog02');
DECLARE @ruta NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));
DECLARE @stop NVARCHAR(30)  = CONVERT(NVARCHAR(30),
        (SELECT TOP (1) FechaHoraPrevia FROM DBSuperHamburguesas.dba.MarcaIncidente ORDER BY MarcaID DESC), 121);
DECLARE @sql  NVARCHAR(MAX);

-- 3.1  Completo, sin recuperar, reubicando los archivos hacia la base alterna
SET @sql = N'
RESTORE DATABASE DBSuperHamburguesas_RECOVERY
FROM DISK = ' + QUOTENAME(@full,'''') + N'
WITH NORECOVERY, REPLACE, STATS = 25,
     MOVE N''DBSuperHamburguesas_Data'' TO ' + QUOTENAME(@ruta + N'DBSuperHamburguesas_RECOVERY.mdf','''') + N',
     MOVE N''DBSuperHamburguesas_Log''  TO ' + QUOTENAME(@ruta + N'DBSuperHamburguesas_RECOVERY.ldf','''') + N';';
EXEC sys.sp_executesql @sql;
PRINT N'3.1 Completo restaurado, sin recuperar.';

-- 3.2  Diferencial, sin recuperar
SET @sql = N'RESTORE DATABASE DBSuperHamburguesas_RECOVERY FROM DISK = ' + QUOTENAME(@diff,'''') + N' WITH NORECOVERY, STATS = 25;';
EXEC sys.sp_executesql @sql;
PRINT N'3.2 Diferencial aplicado, sin recuperar.';

-- 3.3  Registro 01 completo, sin recuperar: es anterior al incidente
SET @sql = N'RESTORE LOG DBSuperHamburguesas_RECOVERY FROM DISK = ' + QUOTENAME(@l01,'''') + N' WITH NORECOVERY;';
EXEC sys.sp_executesql @sql;
PRINT N'3.3 Registro 01 aplicado, sin recuperar.';

-- 3.4  Registro 02 con STOPAT: contiene el incidente, hay que detenerse antes
SET @sql = N'RESTORE LOG DBSuperHamburguesas_RECOVERY FROM DISK = ' + QUOTENAME(@l02,'''') + N'
WITH RECOVERY, STOPAT = ' + QUOTENAME(@stop,'''') + N';';
EXEC sys.sp_executesql @sql;
PRINT N'3.4 Registro 02 aplicado con STOPAT = ' + @stop + N'. Base recuperada.';

-- Tiempo real de recuperacion
DECLARE @seg INT = DATEDIFF(SECOND, @inicio, SYSDATETIME());
IF OBJECT_ID(N'tempdb..##TiempoRecuperacion') IS NOT NULL DROP TABLE ##TiempoRecuperacion;
CREATE TABLE ##TiempoRecuperacion (Inicio DATETIME2(3), Fin DATETIME2(3), Segundos INT, MarcaSTOPAT NVARCHAR(30));
INSERT INTO ##TiempoRecuperacion VALUES (@inicio, SYSDATETIME(), @seg, @stop);
GO


/*==============================================================================
  SECCION 4 - VALIDACION FUNCIONAL DE LOS DATOS (EV-05-02)
  El dato erroneo no debe estar presente y el dato valido si.
==============================================================================*/
SELECT
    [Ambito]            = N'PRODUCTIVA (danada)',
    [Ingredientes]      = COUNT(e.IngredienteID),
    [StockTotal]        = SUM(e.StockActual),
    [ConStockEnCero]    = SUM(CASE WHEN e.StockActual = 0 THEN 1 ELSE 0 END)
FROM DBSuperHamburguesas.inventario.ExistenciaIngrediente AS e
UNION ALL
SELECT
    N'RECUPERADA (a punto en el tiempo)',
    COUNT(r.IngredienteID),
    SUM(r.StockActual),
    SUM(CASE WHEN r.StockActual = 0 THEN 1 ELSE 0 END)
FROM DBSuperHamburguesas_RECOVERY.inventario.ExistenciaIngrediente AS r;
GO

-- Veredicto de la validacion funcional
DECLARE @ceroProd INT = (SELECT COUNT(*) FROM DBSuperHamburguesas.inventario.ExistenciaIngrediente WHERE StockActual = 0);
DECLARE @ceroReco INT = (SELECT COUNT(*) FROM DBSuperHamburguesas_RECOVERY.inventario.ExistenciaIngrediente WHERE StockActual = 0);
DECLARE @totalReco DECIMAL(18,3) = (SELECT SUM(StockActual) FROM DBSuperHamburguesas_RECOVERY.inventario.ExistenciaIngrediente);

SELECT
    [Prueba]                  = N'El dato erroneo NO esta presente en la base recuperada',
    [CeroEnProductiva]        = @ceroProd,
    [CeroEnRecuperada]        = @ceroReco,
    [StockTotalRecuperado]    = @totalReco,
    [Resultado]               = CASE WHEN @ceroProd > 0 AND @ceroReco = 0 AND @totalReco > 0
                                     THEN N'CUMPLE' ELSE N'NO CUMPLE' END;
GO

-- Comparacion contra la etapa capturada antes del incidente
SELECT
    [Etapa]                = e.Etapa,
    [StockTotalRegistrado] = e.StockTotal,
    [StockTotalRecuperado] = (SELECT SUM(r.StockActual) FROM DBSuperHamburguesas_RECOVERY.inventario.ExistenciaIngrediente AS r),
    [Coinciden]            = CASE WHEN e.StockTotal =
                                  (SELECT SUM(r.StockActual) FROM DBSuperHamburguesas_RECOVERY.inventario.ExistenciaIngrediente AS r)
                                  THEN N'SI' ELSE N'Revisar: puede diferir por transacciones intermedias' END
FROM DBSuperHamburguesas.dba.EvidenciaInventario AS e
WHERE e.Etapa = N'04 Ultimo estado integro';
GO


/*==============================================================================
  SECCION 5 - INTEGRIDAD DE LA BASE RESTAURADA (EV-05-03)
==============================================================================*/
DBCC CHECKDB (N'DBSuperHamburguesas_RECOVERY') WITH NO_INFOMSGS, ALL_ERRORMSGS;
PRINT N'DBCC CHECKDB finalizado. Sin mensajes por encima de esta linea = sin errores de integridad.';
GO


/*==============================================================================
  SECCION 6 - TIEMPO REAL CONTRA EL OBJETIVO DECLARADO (EV-05-04)
==============================================================================*/
DECLARE @rto INT = (SELECT RTO_Minutos FROM DBSuperHamburguesas.dba.ObjetivoRecuperacion WHERE Base = N'DBSuperHamburguesas');
DECLARE @seg INT = (SELECT Segundos FROM ##TiempoRecuperacion);

SELECT
    [Inicio restauracion]  = t.Inicio,
    [Fin restauracion]     = t.Fin,
    [MarcaSTOPAT aplicada] = t.MarcaSTOPAT,
    [TiempoRealSegundos]   = t.Segundos,
    [TiempoRealMinutos]    = CAST(t.Segundos / 60.0 AS DECIMAL(10,2)),
    [RTO declarado (min)]  = @rto,
    [Margen (min)]         = CAST(@rto - (t.Segundos / 60.0) AS DECIMAL(10,2)),
    [Resultado]            = CASE WHEN (t.Segundos / 60.0) <= @rto
                                  THEN N'CUMPLE: dentro del objetivo'
                                  ELSE N'HALLAZGO: excede el RTO. Requiere accion correctiva con plazo.' END
FROM ##TiempoRecuperacion AS t;
GO

-- Control DBA-BKP-02
DECLARE @ceroReco INT = (SELECT COUNT(*) FROM DBSuperHamburguesas_RECOVERY.inventario.ExistenciaIngrediente WHERE StockActual = 0);
DECLARE @rto2 INT = (SELECT RTO_Minutos FROM DBSuperHamburguesas.dba.ObjetivoRecuperacion WHERE Base = N'DBSuperHamburguesas');
DECLARE @seg2 INT = (SELECT Segundos FROM ##TiempoRecuperacion);

SELECT
    [Control]              = N'DBA-BKP-02 Prueba de restauracion con tiempo medido',
    [SobreBaseAlterna]     = N'SI',
    [PuntoEnElTiempo]      = N'SI, con STOPAT',
    [DatoErroneoAusente]   = CASE WHEN @ceroReco = 0 THEN N'SI' ELSE N'NO' END,
    [IntegridadVerificada] = N'SI, DBCC CHECKDB en la seccion 5',
    [TiempoMedidoVsRTO]    = CAST(@seg2/60.0 AS DECIMAL(10,2)) + 0.0,
    [Resultado]            = CASE WHEN @ceroReco = 0 AND (@seg2/60.0) <= @rto2
                                  THEN N'CUMPLE' ELSE N'REVISAR' END;
GO


/*==============================================================================
  SECCION 7 - CADENA UTILIZADA (EV-05-05)
==============================================================================*/
SELECT
    [Orden]       = ROW_NUMBER() OVER (ORDER BY bs.backup_start_date),
    [Tipo]        = CASE bs.type WHEN 'D' THEN N'1 COMPLETO'
                                 WHEN 'I' THEN N'2 DIFERENCIAL'
                                 WHEN 'L' THEN N'3 REGISTRO' END,
    [Inicio]      = bs.backup_start_date,
    [Fin]         = bs.backup_finish_date,
    [PrimerLSN]   = bs.first_lsn,
    [UltimoLSN]   = bs.last_lsn,
    [ConChecksum] = CASE WHEN bs.has_backup_checksums = 1 THEN N'SI' ELSE N'NO' END,
    [Archivo]     = mf.physical_device_name,
    [Aplicado]    = N'SI'
FROM msdb.dbo.backupset AS bs
INNER JOIN msdb.dbo.backupmediafamily AS mf ON mf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'DBSuperHamburguesas'
  AND bs.backup_start_date >= CAST(CAST(GETDATE() AS DATE) AS DATETIME)
ORDER BY bs.backup_start_date;
GO

-- EV-05-06: historial de restauracion
SELECT
    [BaseDestino]   = rh.destination_database_name,
    [FechaRestauro] = rh.restore_date,
    [Tipo]          = CASE rh.restore_type WHEN 'D' THEN N'COMPLETO'
                                           WHEN 'I' THEN N'DIFERENCIAL'
                                           WHEN 'L' THEN N'REGISTRO' ELSE rh.restore_type END,
    [StopAt]        = rh.stop_at,
    [Usuario]       = rh.user_name
FROM msdb.dbo.restorehistory AS rh
WHERE rh.destination_database_name = N'DBSuperHamburguesas_RECOVERY'
ORDER BY rh.restore_date;
GO

PRINT N'== 05_Restore_Recovery.sql finalizado. Conservar las salidas como EV-05-01 a EV-05-06. ==';
PRINT N'== Siguiente paso: 06_Monitoreo.sql ==';
GO
