/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        04_Backup.sql
  Proposito:     Ejecutar la primera mitad de la cadena de recuperacion:
                 respaldo completo con suma de verificacion, cambios
                 controlados, diferencial, respaldo de registro, marca temporal
                 previa, simulacion del incidente logico y respaldo de registro
                 posterior (seccion 7.5 del entregable, pasos 1 a 8).

  Controles del Entregable 1 que implementa:
                 DBA-BKP-01  Cadena de respaldos con suma de verificacion y
                             verificacion diaria de ejecucion.
                 DBA-BKP-02  Base con verificacion de pagina activa, condicion
                             para que la suma de verificacion sea efectiva.

  Precondiciones:1) Scripts 00 a 03 ejecutados con exito.
                 2) La base esta en modelo FULL (verificado en EV-00-02).
                 3) La cuenta de servicio de SQL Server escribe en la carpeta
                    de respaldo por defecto de la instancia.
  Orden:         Script 04. Antes de 05_Restore_Recovery.sql.
  Destructivo:   SI, de forma controlada. La SECCION 8 altera
                 intencionalmente el inventario para simular el incidente
                 logico. Se gobierna con @EjecutarIncidente y el estado previo
                 queda respaldado en la cadena.
  Reejecutable:  SI. Las copias se sobrescriben con INIT.
  Resultado
  esperado:      Cuatro archivos de respaldo, la marca temporal registrada y
                 diez conjuntos de salida. Guardar como EV-04-01 a EV-04-06.

  ---------------------------------------------------------------------------
  DECISIONES DE IMPLEMENTACION
  ---------------------------------------------------------------------------
  Ruta parametrizada en un solo lugar
    La ruta se resuelve desde la instancia y se guarda en dba.ConfiguracionRespaldo,
    de donde la lee 05_Restore_Recovery.sql. No hay rutas personales en el codigo
    ni repeticion de literales entre scripts.

  Verificacion de pagina antes que suma de verificacion del respaldo
    La SECCION 0.3 comprueba que la base tenga PAGE_VERIFY CHECKSUM. Sin esa
    opcion el respaldo no puede verificar el contenido de las paginas: las
    incluye sin verificar y termina con exito, de modo que WITH CHECKSUM daria
    una falsa sensacion de control. Es la disposicion 6.4.1 del estandar.

  Por que el incidente va sobre el inventario
    El enunciado pide simular una actualizacion masiva incorrecta del inventario.
    Se altera StockActual de inventario.ExistenciaIngrediente, que es una tabla
    pequena y de estado, de modo que el dano sea inequivoco y facil de mostrar
    en la demostracion: todos los ingredientes quedan con el mismo valor absurdo.

  Dos respaldos de registro y no uno
    El primero cierra el tramo previo al incidente. El segundo, posterior al
    incidente, es el que contiene la transaccion danina y por lo tanto el unico
    que permite detenerse justo antes de ella con STOPAT. Sin ese segundo
    respaldo no existe recuperacion a un punto en el tiempo.
==============================================================================*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE DBSuperHamburguesas;
GO

/*==============================================================================
  SECCION 0 - PRECONDICIONES
==============================================================================*/
IF DB_NAME() <> N'DBSuperHamburguesas'
BEGIN
    RAISERROR(N'Este script debe ejecutarse sobre DBSuperHamburguesas.', 16, 1); RETURN;
END
IF (SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()) <> N'FULL'
BEGIN
    RAISERROR(N'La base no esta en modelo FULL. Sin el no hay cadena de registro ni PITR.', 16, 1); RETURN;
END
IF (SELECT page_verify_option_desc FROM sys.databases WHERE name = DB_NAME()) <> N'CHECKSUM'
BEGIN
    RAISERROR(N'La base no tiene verificacion de pagina CHECKSUM. WITH CHECKSUM no podria verificar las paginas.', 16, 1); RETURN;
END
PRINT N'Precondiciones verificadas: modelo FULL y verificacion de pagina CHECKSUM.';
GO


/*==============================================================================
  SECCION 1 - CONFIGURACION, CRITICIDAD Y OBJETIVOS DE RECUPERACION
==============================================================================*/
DROP TABLE IF EXISTS dba.ConfiguracionRespaldo;
CREATE TABLE dba.ConfiguracionRespaldo
(
    Clave NVARCHAR(50)  NOT NULL CONSTRAINT PK_ConfiguracionRespaldo PRIMARY KEY,
    Valor NVARCHAR(400) NOT NULL
);
GO

DECLARE @ruta NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(260));
/* La propiedad devuelve la carpeta SIN separador final. Sin esta normalizacion la
   concatenacion produce ...\MSSQL\BackupArchivo.bak, una ruta fuera de la carpeta
   de respaldo sobre la que la cuenta de servicio no tiene permiso de escritura. */
IF RIGHT(@ruta, 1) NOT IN (N'\', N'/') SET @ruta = @ruta + N'\';

INSERT INTO dba.ConfiguracionRespaldo (Clave, Valor)
VALUES (N'RutaRespaldo', @ruta),
       (N'ArchivoFull',  @ruta + N'DBSuperHamburguesas_FULL.bak'),
       (N'ArchivoDiff',  @ruta + N'DBSuperHamburguesas_DIFF.bak'),
       (N'ArchivoLog01', @ruta + N'DBSuperHamburguesas_LOG_01.trn'),
       (N'ArchivoLog02', @ruta + N'DBSuperHamburguesas_LOG_02.trn'),
       (N'BaseAlterna',  N'DBSuperHamburguesas_RECOVERY');
GO

-- EV-04-01: criticidad y objetivos de recuperacion, con justificacion por impacto
DROP TABLE IF EXISTS dba.ObjetivoRecuperacion;
CREATE TABLE dba.ObjetivoRecuperacion
(
    Base           SYSNAME        NOT NULL CONSTRAINT PK_ObjetivoRecuperacion PRIMARY KEY,
    Criticidad     NVARCHAR(20)   NOT NULL,
    RPO_Minutos    INT            NOT NULL,
    RTO_Minutos    INT            NOT NULL,
    Estrategia     NVARCHAR(400)  NOT NULL,
    Justificacion  NVARCHAR(1000) NOT NULL,
    Declarado      DATETIME2(0)   NOT NULL CONSTRAINT DF_ObjetivoRecuperacion_Declarado DEFAULT (SYSDATETIME()),
    CONSTRAINT CK_ObjetivoRecuperacion_RPO CHECK (RPO_Minutos > 0),
    CONSTRAINT CK_ObjetivoRecuperacion_RTO CHECK (RTO_Minutos > 0)
);
GO

INSERT INTO dba.ObjetivoRecuperacion (Base, Criticidad, RPO_Minutos, RTO_Minutos, Estrategia, Justificacion)
VALUES (N'DBSuperHamburguesas', N'Alta', 15, 120,
        N'Modelo completo. Respaldo completo diario, diferencial cada 6 horas y respaldo de registro cada 15 minutos.',
        N'La base soporta la toma y el cobro de pedidos. Su indisponibilidad detiene la atencion de cara al cliente e impide facturar, con perdida economica directa por cada hora sin servicio. La perdida maxima admisible se fija en 15 minutos porque es el volumen de pedidos que el personal puede reconstruir desde los comprobantes fisicos del turno; mas alla de ese punto la reconstruccion deja de ser viable. El tiempo de reparacion se fija en 2 horas para que la recuperacion quepa dentro de una jornada parcial y no arrastre el turno siguiente.');
GO

SELECT
    [Momento]       = SYSDATETIME(),
    [Base]          = Base,
    [Criticidad]    = Criticidad,
    [RPO]           = CAST(RPO_Minutos AS NVARCHAR(10)) + N' minutos',
    [RTO]           = CAST(RTO_Minutos AS NVARCHAR(10)) + N' minutos',
    [Estrategia]    = Estrategia,
    [Justificacion] = Justificacion
FROM dba.ObjetivoRecuperacion;
GO


/*==============================================================================
  SECCION 2 - TABLAS DE EVIDENCIA
==============================================================================*/
DROP TABLE IF EXISTS dba.EvidenciaInventario;
CREATE TABLE dba.EvidenciaInventario
(
    EvidenciaID   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EvidenciaInventario PRIMARY KEY,
    Momento       DATETIME2(0) NOT NULL CONSTRAINT DF_EvidenciaInventario_Momento DEFAULT (SYSDATETIME()),
    Etapa         NVARCHAR(60) NOT NULL,
    Ingredientes  INT NOT NULL,
    StockTotal    DECIMAL(18,3) NOT NULL,
    StockMinimoObs DECIMAL(18,3) NOT NULL,
    StockMaximoObs DECIMAL(18,3) NOT NULL
);
GO

DROP TABLE IF EXISTS dba.MarcaIncidente;
CREATE TABLE dba.MarcaIncidente
(
    MarcaID          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MarcaIncidente PRIMARY KEY,
    FechaHoraPrevia  DATETIME2(3) NOT NULL,
    Descripcion      NVARCHAR(300) NOT NULL,
    FilasAlteradas   INT NULL
);
GO

CREATE OR ALTER PROCEDURE dba.usp_CapturarInventario
    @pEtapa NVARCHAR(60)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dba.EvidenciaInventario (Etapa, Ingredientes, StockTotal, StockMinimoObs, StockMaximoObs)
    SELECT @pEtapa, COUNT(e.IngredienteID), SUM(e.StockActual), MIN(e.StockActual), MAX(e.StockActual)
    FROM inventario.ExistenciaIngrediente AS e;
END;
GO


/*==============================================================================
  SECCION 3 - PASO 2: RESPALDO COMPLETO CON SUMA DE VERIFICACION
==============================================================================*/
EXEC dba.usp_CapturarInventario @pEtapa = N'01 Estado inicial';
GO

DECLARE @f NVARCHAR(400) = (SELECT Valor FROM dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoFull');
DECLARE @sql NVARCHAR(MAX) = N'
BACKUP DATABASE DBSuperHamburguesas
TO DISK = ' + QUOTENAME(@f, '''') + N'
WITH INIT, CHECKSUM, STATS = 25,
     NAME = N''Full DBSuperHamburguesas - Proyecto 2'',
     DESCRIPTION = N''Respaldo completo, inicio de la cadena de recuperacion.'';';
EXEC sys.sp_executesql @sql;
PRINT N'Paso 2 completado: respaldo completo con suma de verificacion.';
GO


/*==============================================================================
  SECCION 4 - PASO 3: CAMBIOS CONTROLADOS (ANTES / DESPUES)
==============================================================================*/
-- Cambio legitimo de negocio: reposicion de inventario.
UPDATE inventario.ExistenciaIngrediente
   SET StockActual = StockActual + 100,
       FechaUltimaActualizacion = SYSDATETIME()
 WHERE IngredienteID % 2 = 0;

EXEC dba.usp_CapturarInventario @pEtapa = N'02 Despues del cambio controlado 1';
PRINT N'Paso 3 completado: cambio controlado aplicado y capturado.';
GO


/*==============================================================================
  SECCION 5 - PASO 4: RESPALDO DIFERENCIAL
==============================================================================*/
DECLARE @f NVARCHAR(400) = (SELECT Valor FROM dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoDiff');
DECLARE @sql NVARCHAR(MAX) = N'
BACKUP DATABASE DBSuperHamburguesas
TO DISK = ' + QUOTENAME(@f, '''') + N'
WITH DIFFERENTIAL, INIT, CHECKSUM, STATS = 25,
     NAME = N''Diferencial DBSuperHamburguesas - Proyecto 2'';';
EXEC sys.sp_executesql @sql;
PRINT N'Paso 4 completado: respaldo diferencial.';
GO


/*==============================================================================
  SECCION 6 - PASO 5: NUEVOS CAMBIOS Y RESPALDO DE REGISTRO 01
==============================================================================*/
INSERT INTO inventario.MovimientoInventario
    (IngredienteID, TipoMovimientoID, FechaMovimiento, Cantidad, CostoUnitario, Observacion)
SELECT TOP (50) i.IngredienteID, 1, SYSDATETIME(), 25.000, i.CostoReferencia,
       N'Ingreso por compra previo al respaldo de registro 01'
FROM catalogo.Ingrediente AS i
ORDER BY i.IngredienteID;

EXEC dba.usp_CapturarInventario @pEtapa = N'03 Despues del cambio controlado 2';
GO

DECLARE @f NVARCHAR(400) = (SELECT Valor FROM dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoLog01');
DECLARE @sql NVARCHAR(MAX) = N'
BACKUP LOG DBSuperHamburguesas
TO DISK = ' + QUOTENAME(@f, '''') + N'
WITH INIT, CHECKSUM, NAME = N''Log 01 previo al incidente - Proyecto 2'';';
EXEC sys.sp_executesql @sql;
PRINT N'Paso 5 completado: respaldo de registro 01, previo al incidente.';
GO


/*==============================================================================
  SECCION 7 - PASOS 6 Y 7: MARCA TEMPORAL Y ESTADO PREVIO AL INCIDENTE
  La marca es el punto de detencion que usara STOPAT. Se registra ANTES de
  provocar el dano y se deja una holgura de dos segundos para que la
  recuperacion no quede en el limite exacto de la transaccion.
==============================================================================*/
EXEC dba.usp_CapturarInventario @pEtapa = N'04 Ultimo estado integro';
GO

WAITFOR DELAY '00:00:02';
GO

INSERT INTO dba.MarcaIncidente (FechaHoraPrevia, Descripcion)
VALUES (SYSDATETIME(), N'Instante inmediatamente anterior a la actualizacion masiva incorrecta del inventario.');

SELECT
    [Momento]              = SYSDATETIME(),
    [MarcaPreviaIncidente] = CONVERT(NVARCHAR(30), FechaHoraPrevia, 121),
    [Descripcion]          = Descripcion,
    [Uso]                  = N'Valor que 05_Restore_Recovery.sql aplicara en la clausula STOPAT.'
FROM dba.MarcaIncidente;
GO

WAITFOR DELAY '00:00:02';
GO


/*==============================================================================
  SECCION 8 - PASO 7: INCIDENTE LOGICO (DESTRUCTIVO Y DELIBERADO)
  Actualizacion masiva incorrecta: se omite la clausula de filtro y todos los
  ingredientes quedan con la misma existencia. Es una transaccion valida para el
  motor, que es precisamente lo que hace que ningun mecanismo de replica la
  detenga y que solo el respaldo permita revertirla.
==============================================================================*/
/*------------------------------------------------------------------------------
  GUARDA DE SEGURIDAD
  El incidente solo se provoca si la cadena de respaldo existe de verdad. Sin
  respaldo completo, diferencial y de registro, el dano seria irreversible.
------------------------------------------------------------------------------*/
DECLARE @nFull INT = (SELECT COUNT(*) FROM msdb.dbo.backupset
                       WHERE database_name = N'DBSuperHamburguesas' AND type = 'D'
                         AND backup_finish_date > DATEADD(HOUR, -6, SYSDATETIME()));
DECLARE @nDiff INT = (SELECT COUNT(*) FROM msdb.dbo.backupset
                       WHERE database_name = N'DBSuperHamburguesas' AND type = 'I'
                         AND backup_finish_date > DATEADD(HOUR, -6, SYSDATETIME()));
DECLARE @nLog  INT = (SELECT COUNT(*) FROM msdb.dbo.backupset
                       WHERE database_name = N'DBSuperHamburguesas' AND type = 'L'
                         AND backup_finish_date > DATEADD(HOUR, -6, SYSDATETIME()));

SELECT [Respaldos completos] = @nFull, [Diferenciales] = @nDiff, [De registro] = @nLog;

IF @nFull = 0 OR @nDiff = 0 OR @nLog = 0
BEGIN
    RAISERROR(N'No existe la cadena de respaldo completa. El incidente NO se provoca: seria irreversible. Revise los errores de las secciones anteriores.', 16, 1);
    RETURN;
END

DECLARE @EjecutarIncidente BIT = 1;   -- 1 = provoca el incidente. Volver a 0 tras capturar la evidencia.

IF @EjecutarIncidente = 1
BEGIN
    UPDATE inventario.ExistenciaIngrediente
       SET StockActual = 0,
           FechaUltimaActualizacion = SYSDATETIME();

    UPDATE dba.MarcaIncidente
       SET FilasAlteradas = @@ROWCOUNT
     WHERE MarcaID = (SELECT MAX(MarcaID) FROM dba.MarcaIncidente);

    EXEC dba.usp_CapturarInventario @pEtapa = N'05 Estado alterado por el incidente';
    PRINT N'Paso 7: INCIDENTE LOGICO PROVOCADO. Inventario alterado de forma masiva.';
END
ELSE
    PRINT N'Paso 7 omitido: @EjecutarIncidente = 0.';
GO


/*==============================================================================
  SECCION 9 - PASO 8: RESPALDO DE REGISTRO 02, POSTERIOR AL INCIDENTE
  Indispensable: este tramo contiene la transaccion danina y es el unico que
  permite detener la recuperacion justo antes de ella.
==============================================================================*/
DECLARE @f NVARCHAR(400) = (SELECT Valor FROM dba.ConfiguracionRespaldo WHERE Clave = N'ArchivoLog02');
DECLARE @sql NVARCHAR(MAX) = N'
BACKUP LOG DBSuperHamburguesas
TO DISK = ' + QUOTENAME(@f, '''') + N'
WITH INIT, CHECKSUM, NAME = N''Log 02 posterior al incidente - Proyecto 2'';';
EXEC sys.sp_executesql @sql;
PRINT N'Paso 8 completado: respaldo de registro 02, posterior al incidente.';
GO


/*==============================================================================
  SECCION 10 - VERIFICACION Y EVIDENCIA
==============================================================================*/

-- EV-04-02: evolucion del inventario en las cinco etapas
SELECT
    [Etapa]         = Etapa,
    [FechaHora]     = Momento,
    [Ingredientes]  = Ingredientes,
    [StockTotal]    = StockTotal,
    [StockMinimo]   = StockMinimoObs,
    [StockMaximo]   = StockMaximoObs
FROM dba.EvidenciaInventario
ORDER BY EvidenciaID;
GO

-- EV-04-03: dano provocado
SELECT
    [Marca previa]     = CONVERT(NVARCHAR(30), m.FechaHoraPrevia, 121),
    [Filas alteradas]  = m.FilasAlteradas,
    [Stock antes]      = (SELECT StockTotal FROM dba.EvidenciaInventario WHERE Etapa = N'04 Ultimo estado integro'),
    [Stock despues]    = (SELECT StockTotal FROM dba.EvidenciaInventario WHERE Etapa = N'05 Estado alterado por el incidente'),
    [Diagnostico]      = N'Actualizacion masiva sin filtro sobre inventario.ExistenciaIngrediente.'
FROM dba.MarcaIncidente AS m
WHERE m.MarcaID = (SELECT MAX(MarcaID) FROM dba.MarcaIncidente);
GO

-- EV-04-04: historial de respaldos en msdb (se entrega tambien al frente de monitoreo)
SELECT
    [Base]          = bs.database_name,
    [Tipo]          = CASE bs.type WHEN 'D' THEN N'COMPLETO'
                                   WHEN 'I' THEN N'DIFERENCIAL'
                                   WHEN 'L' THEN N'REGISTRO' ELSE bs.type END,
    [Inicio]        = bs.backup_start_date,
    [Fin]           = bs.backup_finish_date,
    [SegundosDur]   = DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date),
    [TamanoMB]      = CAST(bs.backup_size / 1048576.0 AS DECIMAL(12,2)),
    [ConChecksum]   = CASE WHEN bs.has_backup_checksums = 1 THEN N'SI' ELSE N'NO' END,
    [Danado]        = CASE WHEN bs.is_damaged = 1 THEN N'SI' ELSE N'NO' END,
    [PrimerLSN]     = bs.first_lsn,
    [UltimoLSN]     = bs.last_lsn,
    [Archivo]       = mf.physical_device_name
FROM msdb.dbo.backupset AS bs
INNER JOIN msdb.dbo.backupmediafamily AS mf ON mf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'DBSuperHamburguesas'
ORDER BY bs.backup_start_date DESC;
GO

-- EV-04-05: control DBA-BKP-01
SELECT
    [Control]            = N'DBA-BKP-01 Cadena de respaldos con suma de verificacion',
    [Completos]          = SUM(CASE WHEN bs.type = 'D' THEN 1 ELSE 0 END),
    [Diferenciales]      = SUM(CASE WHEN bs.type = 'I' THEN 1 ELSE 0 END),
    [Registros]          = SUM(CASE WHEN bs.type = 'L' THEN 1 ELSE 0 END),
    [SinChecksum]        = SUM(CASE WHEN bs.has_backup_checksums = 0 THEN 1 ELSE 0 END),
    [Resultado]          = CASE WHEN SUM(CASE WHEN bs.type = 'D' THEN 1 ELSE 0 END) >= 1
                                 AND SUM(CASE WHEN bs.type = 'I' THEN 1 ELSE 0 END) >= 1
                                 AND SUM(CASE WHEN bs.type = 'L' THEN 1 ELSE 0 END) >= 2
                                 AND SUM(CASE WHEN bs.has_backup_checksums = 0 THEN 1 ELSE 0 END) = 0
                                THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM msdb.dbo.backupset AS bs
WHERE bs.database_name = N'DBSuperHamburguesas'
  AND bs.backup_start_date >= CAST(CAST(GETDATE() AS DATE) AS DATETIME);
GO

-- EV-04-06: uso del registro tras la cadena
SELECT
    [LogTotalMB]     = CAST(total_log_size_in_bytes / 1048576.0 AS DECIMAL(12,2)),
    [LogUsadoMB]     = CAST(used_log_space_in_bytes  / 1048576.0 AS DECIMAL(12,2)),
    [LogUsadoPct]    = CAST(used_log_space_in_percent AS DECIMAL(5,2)),
    [RazonEsperaLog] = (SELECT log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME())
FROM sys.dm_db_log_space_usage;
GO

PRINT N'== 04_Backup.sql finalizado. Conservar las salidas como EV-04-01 a EV-04-06. ==';
PRINT N'== Siguiente paso: 05_Restore_Recovery.sql ==';
GO
