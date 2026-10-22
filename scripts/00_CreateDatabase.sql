/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        00_CreateDatabase.sql
  Proposito:     Crear y configurar la base DBSuperHamburguesas con criterios
                 explicitos de tamano inicial, archivos, crecimiento y modelo
                 de recuperacion (seccion 7.1 del entregable).
  Precondiciones:1) 00_Diagnostico_Instancia.sql ejecutado y su salida guardada.
                 2) Cuenta miembro de sysadmin.
                 3) Espacio libre en disco >= 1 GB en la ruta de datos de la
                    instancia.
  Orden:         Script 00. Se ejecuta despues del diagnostico y antes de
                 01_Modelo.sql.
  Destructivo:   PARCIALMENTE. La SECCION 1 elimina la base si ya existe y solo
                 debe habilitarse en el ambiente de pruebas. Viene desactivada.
  Resultado
  esperado:      Base creada, RECOVERY FULL, PAGE_VERIFY CHECKSUM y cuatro
                 conjuntos de verificacion al final. Guardar la salida de la
                 SECCION 4 como evidencia EV-00-02.

  ---------------------------------------------------------------------------
  DECISIONES DE DIMENSIONAMIENTO (justificacion requerida por la seccion 7.1)
  ---------------------------------------------------------------------------
  Archivo de datos (DBSuperHamburguesas_Data)
    Tamano inicial 256 MB. El modelo tiene 18 tablas y la carga sintetica
    prevista (aprox. 2.000 clientes, 50.000 pedidos, 150.000 lineas de detalle
    y 100.000 movimientos de inventario) se estima entre 70 y 110 MB con sus
    indices. Preasignar 256 MB cubre esa carga mas el margen de crecimiento del
    caso de rendimiento sin provocar autocrecimientos durante la carga masiva,
    que es cuando el autocrecimiento mas dana el desempeno.
    Crecimiento 64 MB FIJO. Se descarta el crecimiento porcentual porque su
    incremento es compuesto: sobre una base grande genera saltos cada vez
    mayores, impredecibles para la planificacion de capacidad. Un incremento
    fijo mantiene el costo de cada evento de crecimiento constante y acotado.

  Archivo de log (DBSuperHamburguesas_Log)
    Tamano inicial 128 MB. La base opera en modelo FULL, por lo que el log
    retiene todas las transacciones hasta el siguiente BACKUP LOG. La operacion
    de mayor consumo prevista es la actualizacion masiva de inventario que se
    simula como incidente logico en 05_Restore_Recovery.sql; 128 MB la absorben
    sin autocrecimiento.
    Crecimiento 32 MB FIJO. Cada autocrecimiento del log crea un nuevo bloque
    de VLF; incrementos pequenos y frecuentes fragmentan el log y degradan el
    tiempo de recuperacion. 32 MB equilibra numero de VLF y frecuencia de
    crecimiento.

  Modelo de recuperacion FULL
    Exigido por la seccion 7.5: sin FULL no existe cadena de log y por lo tanto
    no es posible la recuperacion a un punto en el tiempo con STOPAT, que es el
    componente principal del entregable. Implica el compromiso operativo de
    ejecutar BACKUP LOG periodicamente; si no se hace, el log crece sin limite.
==============================================================================*/

SET NOCOUNT ON;
GO

/*==============================================================================
  SECCION 1 - REINICIO DEL AMBIENTE (DESTRUCTIVO - DESACTIVADO)
  Descomentar UNICAMENTE para reconstruir el ambiente de pruebas desde cero.
  Elimina la base y todos sus datos.
==============================================================================*/
/*
IF DB_ID(N'DBSuperHamburguesas') IS NOT NULL
BEGIN
    ALTER DATABASE DBSuperHamburguesas SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DBSuperHamburguesas;
    PRINT N'AVISO: base DBSuperHamburguesas eliminada.';
END
GO
*/

/*==============================================================================
  SECCION 2 - CREACION DE LA BASE
  Las rutas se resuelven desde la instancia (InstanceDefaultDataPath /
  InstanceDefaultLogPath). No se incrusta ninguna ruta personal en el codigo,
  conforme a la seccion 9 del entregable.
==============================================================================*/
DECLARE @rutaDatos NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));
DECLARE @rutaLog   NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS NVARCHAR(260));
DECLARE @sql       NVARCHAR(MAX);

-- Guardas previas. Van en el MISMO lote que la creacion: un GO intermedio
-- haria que el lote siguiente se ejecutara igual y la guarda no serviria.
IF DB_ID(N'DBSuperHamburguesas') IS NOT NULL
BEGIN
    RAISERROR(N'La base DBSuperHamburguesas ya existe. Revise la SECCION 1 antes de continuar.', 16, 1);
    RETURN;
END

IF @rutaDatos IS NULL OR @rutaLog IS NULL
BEGIN
    RAISERROR(N'No se pudieron resolver las rutas por defecto de la instancia.', 16, 1);
    RETURN;
END

SET @sql = N'
CREATE DATABASE DBSuperHamburguesas
ON PRIMARY
(
    NAME       = N''DBSuperHamburguesas_Data'',
    FILENAME   = N''' + @rutaDatos + N'DBSuperHamburguesas_Data.mdf'',
    SIZE       = 256MB,
    FILEGROWTH = 64MB
)
LOG ON
(
    NAME       = N''DBSuperHamburguesas_Log'',
    FILENAME   = N''' + @rutaLog + N'DBSuperHamburguesas_Log.ldf'',
    SIZE       = 128MB,
    FILEGROWTH = 32MB
);';

EXEC sys.sp_executesql @sql;

PRINT N'Base DBSuperHamburguesas creada en: ' + @rutaDatos;
GO

/*==============================================================================
  SECCION 3 - CONFIGURACION DE LA BASE
==============================================================================*/

-- Modelo de recuperacion FULL: habilita la cadena de log y el PITR (7.5).
ALTER DATABASE DBSuperHamburguesas SET RECOVERY FULL;
GO

-- Deteccion de corrupcion de paginas. Es la contraparte del WITH CHECKSUM que
-- usan los respaldos en 04_Backup.sql; sin esta opcion el CHECKSUM del respaldo
-- no puede validar lo que no se calculo al escribir.
ALTER DATABASE DBSuperHamburguesas SET PAGE_VERIFY CHECKSUM;
GO

-- AUTO_SHRINK OFF: la reduccion automatica fragmenta indices y provoca ciclos
-- de reduccion/crecimiento. La gestion de espacio es una decision del DBA.
ALTER DATABASE DBSuperHamburguesas SET AUTO_SHRINK OFF;
GO

-- AUTO_CLOSE OFF: evita el costo de abrir y cerrar la base en cada conexion,
-- necesario porque las pruebas de seguridad abren muchas sesiones cortas.
ALTER DATABASE DBSuperHamburguesas SET AUTO_CLOSE OFF;
GO

-- Estadisticas automaticas: sostienen el caso de rendimiento de 07.
ALTER DATABASE DBSuperHamburguesas SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE DBSuperHamburguesas SET AUTO_UPDATE_STATISTICS ON;
GO

-- Aislamiento de instantanea confirmada: reduce bloqueos de lectura durante las
-- pruebas de monitoreo de 06 sin cambiar la semantica de las escrituras.
ALTER DATABASE DBSuperHamburguesas SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO

-- Propietario explicito. Evita que la base quede a nombre del usuario que la
-- creo, lo que rompe la separacion de funciones exigida en 7.2.
ALTER AUTHORIZATION ON DATABASE::DBSuperHamburguesas TO sa;
GO

/*==============================================================================
  SECCION 4 - VERIFICACION Y EVIDENCIA (EV-00-02)
  Conservar la salida completa con fecha y hora.
==============================================================================*/

-- 4.1 Estado, compatibilidad y modelo de recuperacion
SELECT
    [Momento]           = SYSDATETIME(),
    [Base]              = name,
    [Estado]            = state_desc,
    [ModeloRecuperac]   = recovery_model_desc,
    [Compatibilidad]    = compatibility_level,
    [Collation]         = collation_name,
    [VerificacionPagina]= page_verify_option_desc,
    [AutoShrink]        = is_auto_shrink_on,
    [AutoClose]         = is_auto_close_on,
    [RCSI]              = is_read_committed_snapshot_on,
    [Propietario]       = SUSER_SNAME(owner_sid),
    [FechaCreacion]     = create_date
FROM sys.databases
WHERE name = N'DBSuperHamburguesas';
GO

-- 4.2 Archivos, tamano, crecimiento y espacio utilizado
USE DBSuperHamburguesas;
GO
SELECT
    [Archivo]           = df.name,
    [Tipo]              = df.type_desc,
    [RutaFisica]        = df.physical_name,
    [TamanoMB]          = CAST(df.size / 128.0 AS DECIMAL(12,2)),
    [UsadoMB]           = CAST(FILEPROPERTY(df.name, 'SpaceUsed') / 128.0 AS DECIMAL(12,2)),
    [LibreMB]           = CAST((df.size - FILEPROPERTY(df.name, 'SpaceUsed')) / 128.0 AS DECIMAL(12,2)),
    [PorcentajeUso]     = CAST(100.0 * FILEPROPERTY(df.name, 'SpaceUsed') / NULLIF(df.size, 0) AS DECIMAL(5,2)),
    [TipoCrecimiento]   = CASE df.is_percent_growth WHEN 1 THEN N'PORCENTUAL' ELSE N'FIJO (MB)' END,
    [IncrementoMB]      = CASE df.is_percent_growth
                              WHEN 1 THEN CAST(df.growth AS DECIMAL(12,2))
                              ELSE CAST(df.growth / 128.0 AS DECIMAL(12,2))
                          END,
    [TamanoMaximo]      = CASE df.max_size
                              WHEN -1 THEN N'Sin limite'
                              WHEN  0 THEN N'Sin crecimiento'
                              ELSE CAST(CAST(df.max_size / 128.0 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N' MB'
                          END
FROM sys.database_files AS df;
GO

-- 4.3 Uso del log de transacciones (linea base antes de cualquier carga)
SELECT
    [LogTotalMB]        = CAST(total_log_size_in_bytes / 1048576.0 AS DECIMAL(12,2)),
    [LogUsadoMB]        = CAST(used_log_space_in_bytes  / 1048576.0 AS DECIMAL(12,2)),
    [LogUsadoPct]       = CAST(used_log_space_in_percent AS DECIMAL(5,2))
FROM sys.dm_db_log_space_usage;
GO

-- 4.4 Motivo de retencion del log. En una base FULL recien creada el valor
-- esperado es NOTHING; pasara a LOG_BACKUP en cuanto haya actividad, lo que
-- confirma que la cadena de log esta activa.
SELECT
    [Base]              = name,
    [RazonEsperaLog]    = log_reuse_wait_desc
FROM sys.databases
WHERE name = N'DBSuperHamburguesas';
GO

PRINT N'== 00_CreateDatabase.sql finalizado. Continuar con 01_Modelo.sql. ==';
GO
