/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        00_Diagnostico_Instancia.sql
  Proposito:     Paso 0. Levantar la linea base de la INSTANCIA antes de crear
                 la base de datos. El resultado condiciona dos decisiones de
                 diseno del entregable:
                   (a) Si la edicion soporta SQL Server Audit (seccion 7.4).
                   (b) Si la instancia admite logins SQL (seccion 7.2, 12 logins).
  Precondiciones:Conexion a la instancia con una cuenta miembro de sysadmin.
                 NO requiere que exista DBSuperHamburguesas.
  Orden:         Se ejecuta ANTES de 00_CreateDatabase.sql.
  Destructivo:   No. Solo lectura de catalogos del sistema.
  Resultado
  esperado:      Cinco conjuntos de resultados. Guardar la salida completa como
                 evidencia EV-00-01 en /Entregable2/evidencias.
==============================================================================*/

SET NOCOUNT ON;
GO

/*------------------------------------------------------------------------------
  1. Identificacion de la instancia
  Interpretacion: 'Edicion' decide el mecanismo de auditoria.
                  Developer / Enterprise  -> SQL Server Audit completo.
                  Standard                -> solo auditoria a nivel de servidor.
                  Express / Web           -> sin SQL Server Audit -> alternativa
                                             justificada con triggers DML.
------------------------------------------------------------------------------*/
SELECT
    [Momento]            = SYSDATETIME(),
    [Servidor]           = CAST(SERVERPROPERTY('MachineName')      AS NVARCHAR(128)),
    [Instancia]          = CAST(SERVERPROPERTY('InstanceName')     AS NVARCHAR(128)),
    [Edicion]            = CAST(SERVERPROPERTY('Edition')          AS NVARCHAR(128)),
    [Version]            = CAST(SERVERPROPERTY('ProductVersion')   AS NVARCHAR(128)),
    [NivelProducto]      = CAST(SERVERPROPERTY('ProductLevel')     AS NVARCHAR(128)),
    [ActualizacionAcum]  = CAST(SERVERPROPERTY('ProductUpdateLevel') AS NVARCHAR(128)),
    [Collation]          = CAST(SERVERPROPERTY('Collation')        AS NVARCHAR(128)),
    [VersionCompleta]    = @@VERSION;
GO

/*------------------------------------------------------------------------------
  2. Modo de autenticacion
  Interpretacion: SoloWindowsAuth = 1 impide crear los 12 logins SQL exigidos
                  por la seccion 7.2. En ese caso hay que pasar la instancia a
                  modo mixto (SQL Server and Windows Authentication) desde
                  SSMS > Propiedades del servidor > Seguridad, y REINICIAR el
                  servicio. La correccion debe quedar documentada como decision
                  de configuracion, no como un paso oculto.
------------------------------------------------------------------------------*/
SELECT
    [SoloWindowsAuth]    = CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS INT),
    [ModoAutenticacion]  = CASE CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS INT)
                                WHEN 1 THEN N'Solo Windows -> REQUIERE cambio a modo mixto'
                                ELSE        N'Modo mixto -> apto para logins SQL'
                           END,
    [CuentaActual]       = SUSER_SNAME(),
    [EsSysadmin]         = IS_SRVROLEMEMBER('sysadmin');
GO

/*------------------------------------------------------------------------------
  3. Disponibilidad de SQL Server Audit
  CORRECCION (auditoria documental del 29/08/2026, hallazgo H-01):
  la version anterior de este script daba por no disponible SQL Server Audit en
  Express. Es INCORRECTO. Microsoft Learn, "SQL Server Audit (Database Engine)":
  "All editions of SQL Server support server level audits. In SQL Server 2016
  (13.x) with Service Pack 1 and later versions, all editions support database
  level audits."
  La tabla de ediciones de SQL Server 2022 confirma "Server audit: Yes" y
  "Database audit: Yes" para las cinco ediciones, Express incluida.
  En consecuencia se emplea el mecanismo NATIVO y no se tramita excepcion.
  Esta consulta comprueba la disponibilidad real contra el motor, no contra el
  nombre de la edicion.
------------------------------------------------------------------------------*/
DECLARE @edicion  NVARCHAR(128) = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128));
DECLARE @mayor    INT = CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)), 4) AS INT);

SELECT
    [Edicion]              = @edicion,
    [VersionMayor]         = @mayor,
    [SoportaServerAudit]   = 1,
    [SoportaDatabaseAudit] = CASE WHEN @mayor >= 13 THEN 1 ELSE 0 END,
    [MecanismoAdoptado]    = CASE
                               WHEN @mayor >= 13
                                 THEN N'SQL Server Audit nativo: SERVER AUDIT + DATABASE AUDIT SPECIFICATION.'
                               ELSE N'Motor anterior a 2016: evaluar alternativa con triggers y tramitar excepcion.'
                             END,
    [Fundamento]           = N'Microsoft Learn: todas las ediciones soportan auditoria de servidor; desde 2016 SP1 tambien de base de datos.';
GO

-- Comprobacion funcional: los objetos de auditoria deben poder crearse y
-- consultarse. Si estas vistas responden, la caracteristica esta operativa.
SELECT
    [VistaCatalogo]  = N'sys.server_audits',
    [AuditoriasHoy]  = COUNT(*)
FROM sys.server_audits
UNION ALL
SELECT N'sys.server_file_audits', COUNT(*) FROM sys.server_file_audits
UNION ALL
SELECT N'sys.database_audit_specifications', COUNT(*) FROM sys.database_audit_specifications;
GO

-- Permiso necesario para leer el archivo de auditoria en SQL Server 2022:
-- VIEW SERVER SECURITY AUDIT (en 2019 y anteriores era CONTROL SERVER).
SELECT
    [PermisoLecturaAudit] = N'VIEW SERVER SECURITY AUDIT',
    [LoTiene]             = HAS_PERMS_BY_NAME(NULL, NULL, 'VIEW SERVER SECURITY AUDIT');
GO


/*------------------------------------------------------------------------------
  4. Rutas por defecto de la instancia
  Interpretacion: 00_CreateDatabase.sql toma estas rutas de forma dinamica para
                  no incrustar rutas personales en el codigo fuente.
------------------------------------------------------------------------------*/
SELECT
    [RutaDatosPorDefecto] = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260)),
    [RutaLogPorDefecto]   = CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS NVARCHAR(260)),
    [RutaBackupInstancia] = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(260));
GO

/*------------------------------------------------------------------------------
  5. Estado previo: la base no debe existir todavia
  Interpretacion: si devuelve filas, 00_CreateDatabase.sql debe ejecutarse con
                  conocimiento de causa (contiene un bloque DROP condicional
                  marcado como destructivo).
------------------------------------------------------------------------------*/
SELECT
    [BaseExistente]   = name,
    [Estado]          = state_desc,
    [ModeloRecuperac] = recovery_model_desc,
    [Compatibilidad]  = compatibility_level,
    [FechaCreacion]   = create_date
FROM sys.databases
WHERE name IN (N'DBSuperHamburguesas', N'DBSuperHamburguesas_RECOVERY');
GO

PRINT N'== 00_Diagnostico_Instancia.sql finalizado. Conservar la salida como evidencia EV-00-01. ==';
GO
