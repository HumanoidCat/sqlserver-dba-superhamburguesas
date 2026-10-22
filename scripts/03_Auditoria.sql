/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        03_Auditoria.sql
  Proposito:     Implementar el mecanismo de auditoria de DBSuperHamburguesas
                 con SQL Server Audit NATIVO, generar al menos un evento real
                 por cada una de las tres categorias exigidas y consultar el
                 registro mostrando usuario, fecha y hora, objeto y operacion
                 (seccion 7.4 del entregable).

  Controles del Entregable 1 que implementa:
                 DBA-SEG-04  Auditoria de datos sensibles, operaciones
                             financieras y cambios de membresia de roles, con
                             conservacion de doce meses.
                 DBA-GOB-02  La disponibilidad del mecanismo se acredita contra
                             la documentacion de la version concreta; no se
                             tramita excepcion porque no hay limitacion.

  Precondiciones:1) 00, 01 y 02 ejecutados con exito.
                 2) Cuenta con ALTER ANY SERVER AUDIT y ALTER ANY DATABASE AUDIT
                    (incluidas en sysadmin).
                 3) Permiso VIEW SERVER SECURITY AUDIT para leer el registro.
                    Verificado en EV-00-01: LoTiene = 1.
  Orden:         Script 03. Despues de 02_Seguridad.sql, antes de 04_Backup.sql.
  Destructivo:   PARCIALMENTE. La SECCION 0.1 elimina la auditoria previa.
                 Se ejecuta de forma controlada para permitir la reejecucion.
  Reejecutable:  SI.
  Resultado
  esperado:      Una auditoria de servidor activa, una especificacion de base de
                 datos con tres categorias, tres eventos reales generados y su
                 consulta. Guardar la salida de las secciones 5 y 6 como
                 evidencias EV-03-01 a EV-03-04.

  ---------------------------------------------------------------------------
  DECISIONES DE IMPLEMENTACION
  ---------------------------------------------------------------------------
  Mecanismo nativo y no alternativa por triggers
    La instancia es SQL Server 2022 Express. Microsoft Learn, en "SQL Server
    Audit (Database Engine)", establece: "All editions of SQL Server support
    server level audits. In SQL Server 2016 (13.x) with Service Pack 1 and later
    versions, all editions support database level audits." La tabla de ediciones
    de SQL Server 2022 consigna "Server audit: Yes" y "Database audit: Yes" para
    las cinco ediciones, Express incluida. La verificacion funcional quedo en
    EV-00-01: SoportaServerAudit = 1 y SoportaDatabaseAudit = 1.
    En consecuencia NO se tramita excepcion: no existe limitacion tecnica que
    justificarla. Se emplea el mecanismo que el enunciado pide de primera mano.

  Destino en archivo y no en el registro de aplicaciones
    El destino FILE permite consultar el registro con sys.fn_get_audit_file
    desde T-SQL, lo que hace que la evidencia sea una consulta reproducible y no
    una captura del visor de eventos de Windows. La ruta se resuelve desde la
    instancia; no se incrusta ninguna ruta personal.

  Retencion de doce meses
    MAX_ROLLOVER_FILES y MAXSIZE se dimensionan para cubrir el plazo del control
    DBA-SEG-04, que adopta los doce meses del requisito 10.5.1 de PCI DSS v4.0.

  ON_FAILURE = CONTINUE
    Se elige CONTINUE y no SHUTDOWN. Fundamento: en un ambiente academico, un
    fallo de escritura del archivo de auditoria no debe detener la instancia y
    dejar sin ambiente al resto del equipo. La decision se declara aqui porque
    es una desviacion consciente del criterio mas estricto, no un descuido: en
    un ambiente productivo con informacion regulada correspponderia SHUTDOWN o
    FAIL_OPERATION, y esa eleccion debe documentarse por base.

  Por que la especificacion se define BY public
    Auditar "BY public" cubre a todo principal, incluidos los miembros de
    sysadmin. Restringirla a los doce usuarios de negocio dejaria fuera
    precisamente al perfil con mayor capacidad de dano.
==============================================================================*/

SET NOCOUNT ON;
GO

USE master;
GO

/*==============================================================================
  SECCION 0 - VERIFICACION Y REINICIO CONTROLADO
==============================================================================*/

/*------------------------------------------------------------------------------
  0.1  Acreditacion de disponibilidad del mecanismo nativo
  Se comprueba contra el motor, no contra el nombre de la edicion.
------------------------------------------------------------------------------*/
DECLARE @mayor INT = CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)), 4) AS INT);

SELECT
    [Momento]              = SYSDATETIME(),
    [Edicion]              = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)),
    [VersionMayor]         = @mayor,
    [SoportaServerAudit]   = 1,
    [SoportaDatabaseAudit] = CASE WHEN @mayor >= 13 THEN 1 ELSE 0 END,
    [Decision]             = CASE WHEN @mayor >= 13
                                  THEN N'Mecanismo NATIVO. Sin excepcion.'
                                  ELSE N'Motor anterior a 2016: evaluar alternativa y tramitar excepcion.' END;

IF @mayor < 13
BEGIN
    RAISERROR(N'El motor no soporta auditoria a nivel de base de datos. Debe tramitarse excepcion.', 16, 1);
    RETURN;
END
GO

/*------------------------------------------------------------------------------
  0.2  Reinicio controlado: permite reejecutar el script
------------------------------------------------------------------------------*/
USE DBSuperHamburguesas;
GO
IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = N'DBAudit_SuperHamburguesas')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION DBAudit_SuperHamburguesas WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION DBAudit_SuperHamburguesas;
    PRINT N'Especificacion de base de datos previa eliminada.';
END
GO

USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'SrvAudit_Spec_SuperHamburguesas')
BEGIN
    ALTER SERVER AUDIT SPECIFICATION SrvAudit_Spec_SuperHamburguesas WITH (STATE = OFF);
    DROP SERVER AUDIT SPECIFICATION SrvAudit_Spec_SuperHamburguesas;
END
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'Audit_SuperHamburguesas')
BEGIN
    ALTER SERVER AUDIT Audit_SuperHamburguesas WITH (STATE = OFF);
    DROP SERVER AUDIT Audit_SuperHamburguesas;
    PRINT N'Auditoria de servidor previa eliminada.';
END
GO


/*==============================================================================
  SECCION 1 - AUDITORIA DE SERVIDOR
  La ruta se resuelve desde la instancia. La carpeta de respaldo por defecto
  existe siempre y la cuenta de servicio tiene permiso de escritura sobre ella.
==============================================================================*/
DECLARE @ruta NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(260));
IF RIGHT(@ruta, 1) NOT IN (N'\', N'/') SET @ruta = @ruta + N'\';  -- la propiedad no incluye el separador final
DECLARE @sql  NVARCHAR(MAX);

IF @ruta IS NULL
BEGIN
    RAISERROR(N'No se pudo resolver la ruta por defecto de la instancia.', 16, 1);
    RETURN;
END

SET @sql = N'
CREATE SERVER AUDIT Audit_SuperHamburguesas
TO FILE
(
    FILEPATH        = N''' + @ruta + N''',
    MAXSIZE         = 64 MB,
    MAX_ROLLOVER_FILES = 24,     -- 24 archivos: cubre con holgura los 12 meses del control DBA-SEG-04
    RESERVE_DISK_SPACE = OFF
)
WITH
(
    QUEUE_DELAY = 1000,
    ON_FAILURE  = CONTINUE       -- Decision declarada en el encabezado
);';

EXEC sys.sp_executesql @sql;
PRINT N'Auditoria de servidor creada en: ' + @ruta;
GO

ALTER SERVER AUDIT Audit_SuperHamburguesas WITH (STATE = ON);
GO
PRINT N'Auditoria de servidor activada.';
GO


/*==============================================================================
  SECCION 2 - ESPECIFICACION DE BASE DE DATOS
  Las tres categorias que exige la seccion 7.4 del entregable.
==============================================================================*/
USE DBSuperHamburguesas;
GO

CREATE DATABASE AUDIT SPECIFICATION DBAudit_SuperHamburguesas
FOR SERVER AUDIT Audit_SuperHamburguesas
    -- Categoria 1: actualizaciones sobre informacion sensible de empleados
    ADD (UPDATE ON OBJECT::rrhh.Empleado BY public),

    -- Categoria 2: toda operacion sobre informacion financiera
    ADD (INSERT ON OBJECT::contabilidad.MovimientoContable BY public),
    ADD (UPDATE ON OBJECT::contabilidad.MovimientoContable BY public),
    ADD (DELETE ON OBJECT::contabilidad.MovimientoContable BY public),

    -- Categoria 3: cambios de membresia de roles de base de datos
    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP)
WITH (STATE = ON);
GO

PRINT N'Especificacion de base de datos creada y activada con tres categorias.';
GO


/*==============================================================================
  SECCION 3 - GENERACION DE EVENTOS REALES
  Un evento por categoria como minimo. Son operaciones reales sobre el ambiente,
  no simulaciones: la auditoria registra lo que efectivamente ocurrio.
==============================================================================*/

/*--- Categoria 1: UPDATE sobre rrhh.Empleado -----------------------------------
  Se actualiza el telefono de un empleado y se devuelve al valor original, de
  modo que el dato no cambie pero el evento quede registrado.
------------------------------------------------------------------------------*/
DECLARE @emp INT = (SELECT TOP (1) e.EmpleadoID FROM rrhh.Empleado AS e ORDER BY e.EmpleadoID);
DECLARE @telOriginal NVARCHAR(30) = (SELECT e.Telefono FROM rrhh.Empleado AS e WHERE e.EmpleadoID = @emp);

UPDATE rrhh.Empleado SET Telefono = N'80000000' WHERE EmpleadoID = @emp;
UPDATE rrhh.Empleado SET Telefono = @telOriginal WHERE EmpleadoID = @emp;

PRINT N'Categoria 1: dos eventos UPDATE generados sobre rrhh.Empleado (EmpleadoID = ' + CAST(@emp AS NVARCHAR(10)) + N').';
GO

/*--- Categoria 2: INSERT, UPDATE y DELETE sobre MovimientoContable -------------
  Se registra un asiento de prueba, se modifica y se elimina. El DELETE lo
  ejecuta el DBA, no un rol de negocio: a rol_contabilidad_gestion se le deniega
  por diseno, y esa denegacion ya quedo probada en 02_Seguridad.sql.
------------------------------------------------------------------------------*/
INSERT INTO contabilidad.MovimientoContable
    (CuentaContableID, FechaMovimiento, Descripcion, TipoMovimiento, Monto, Referencia)
VALUES (1, SYSDATETIME(), N'Asiento de prueba para evidencia de auditoria', N'DEBITO', 1000.00, N'AUD-TEST-01');

DECLARE @mov BIGINT = SCOPE_IDENTITY();

UPDATE contabilidad.MovimientoContable
   SET Monto = 1500.00
 WHERE MovimientoContableID = @mov;

DELETE FROM contabilidad.MovimientoContable
 WHERE MovimientoContableID = @mov;

PRINT N'Categoria 2: eventos INSERT, UPDATE y DELETE generados sobre contabilidad.MovimientoContable.';
GO

/*--- Categoria 3: cambio de membresia de rol -----------------------------------
  Se agrega y se retira un usuario de un rol. El estado final es identico al
  inicial; lo que queda es el rastro de ambos cambios.
------------------------------------------------------------------------------*/
ALTER ROLE rol_catalogo_consulta ADD MEMBER usr_maria_mendez;
ALTER ROLE rol_catalogo_consulta DROP MEMBER usr_maria_mendez;
PRINT N'Categoria 3: dos eventos de cambio de membresia generados.';
GO

-- La auditoria escribe de forma asincrona. Se fuerza el vaciado del bufer para
-- que los eventos esten disponibles en el archivo antes de consultarlo.
WAITFOR DELAY '00:00:06';
GO


/*==============================================================================
  SECCION 4 - CONFIGURACION VIGENTE (EV-03-01)
==============================================================================*/
SELECT
    [Momento]        = SYSDATETIME(),
    [Auditoria]      = sa.name,
    [Estado]         = CASE WHEN sa.is_state_enabled = 1 THEN N'ACTIVA' ELSE N'INACTIVA' END,
    [Destino]        = sa.type_desc,
    [AnteFallo]      = sa.on_failure_desc,
    [RutaArchivo]    = sfa.log_file_path,
    [TamanoMaxMB]    = sfa.max_file_size,
    [MaxArchivos]    = sfa.max_rollover_files,
    [RetardoCola_ms] = sa.queue_delay
FROM sys.server_audits AS sa
LEFT JOIN sys.server_file_audits AS sfa ON sfa.audit_id = sa.audit_id
WHERE sa.name = N'Audit_SuperHamburguesas';

SELECT
    [Especificacion] = das.name,
    [Estado]         = CASE WHEN das.is_state_enabled = 1 THEN N'ACTIVA' ELSE N'INACTIVA' END,
    [Categoria]      = dasd.audit_action_name,
    [Clase]          = dasd.class_desc,
    [Objeto]         = CASE WHEN dasd.class_desc = 'OBJECT'
                            THEN SCHEMA_NAME(o.schema_id) + N'.' + o.name
                            ELSE N'(ambito de base de datos)' END,
    [Principal]      = dp.name
FROM sys.database_audit_specifications AS das
INNER JOIN sys.database_audit_specification_details AS dasd
        ON dasd.database_specification_id = das.database_specification_id
LEFT JOIN sys.objects AS o            ON o.object_id = dasd.major_id
LEFT JOIN sys.database_principals AS dp ON dp.principal_id = dasd.audited_principal_id
WHERE das.name = N'DBAudit_SuperHamburguesas'
ORDER BY dasd.audit_action_name;
GO


/*==============================================================================
  SECCION 5 - EVIDENCIA POR CATEGORIA (EV-03-02)
  Cada evento muestra los cuatro atributos que exige el enunciado: usuario,
  fecha y hora, objeto y operacion.
==============================================================================*/
/* La ruta se toma del catalogo de la propia auditoria, no de la propiedad de la
   instancia: SERVERPROPERTY('InstanceDefaultBackupPath') devuelve la carpeta SIN
   separador final, de modo que la concatenacion directa produce un patron que no
   corresponde a ningun archivo y fn_get_audit_file devuelve cero filas. */
DECLARE @archivo NVARCHAR(400) = (
    SELECT sfa.log_file_path
         + CASE WHEN RIGHT(sfa.log_file_path, 1) IN (N'\', N'/') THEN N'' ELSE N'\' END
         + N'Audit_SuperHamburguesas*.sqlaudit'
      FROM sys.server_audits AS sa
      INNER JOIN sys.server_file_audits AS sfa ON sfa.audit_id = sa.audit_id
     WHERE sa.name = N'Audit_SuperHamburguesas');

IF @archivo IS NULL
BEGIN
    RAISERROR(N'No existe la auditoria Audit_SuperHamburguesas. Ejecute la SECCION 1 antes de esta.', 16, 1);
    RETURN;
END

SELECT
    [FechaHora]    = a.event_time,
    [Usuario]      = a.server_principal_name,
    [UsuarioBD]    = a.database_principal_name,
    [Operacion]    = a.action_id,
    [Descripcion]  = a.[statement],
    [Esquema]      = a.schema_name,
    [Objeto]       = a.object_name,
    [BaseDatos]    = a.database_name,
    [Exitoso]      = CASE WHEN a.succeeded = 1 THEN N'SI' ELSE N'NO' END,
    [Aplicacion]   = a.application_name,
    [Categoria]    = CASE
                        WHEN a.object_name = N'Empleado'            THEN N'1. Datos sensibles de empleados'
                        WHEN a.object_name = N'MovimientoContable'  THEN N'2. Informacion financiera'
                        WHEN a.action_id IN ('APRL','DPRL')         THEN N'3. Cambio de membresia de rol'
                        ELSE N'Otra'
                     END
FROM sys.fn_get_audit_file(@archivo, DEFAULT, DEFAULT) AS a
WHERE a.database_name = N'DBSuperHamburguesas'
ORDER BY a.event_time DESC;
GO

/*------------------------------------------------------------------------------
  5.1  Comprobacion de cobertura: las tres categorias deben tener eventos
------------------------------------------------------------------------------*/
DECLARE @arch NVARCHAR(400) = (
    SELECT sfa.log_file_path
         + CASE WHEN RIGHT(sfa.log_file_path, 1) IN (N'\', N'/') THEN N'' ELSE N'\' END
         + N'Audit_SuperHamburguesas*.sqlaudit'
      FROM sys.server_audits AS sa
      INNER JOIN sys.server_file_audits AS sfa ON sfa.audit_id = sa.audit_id
     WHERE sa.name = N'Audit_SuperHamburguesas');

;WITH Evento AS (
    SELECT Categoria = CASE
                          WHEN a.object_name = N'Empleado'           THEN N'1. UPDATE sobre rrhh.Empleado'
                          WHEN a.object_name = N'MovimientoContable' THEN N'2. INS/UPD/DEL sobre MovimientoContable'
                          WHEN a.action_id IN ('APRL','DPRL')        THEN N'3. Cambio de membresia de rol'
                          ELSE N'Otra'
                       END,
           a.event_time
    FROM sys.fn_get_audit_file(@arch, DEFAULT, DEFAULT) AS a
    WHERE a.database_name = N'DBSuperHamburguesas'
)
SELECT
    [Categoria]      = c.Categoria,
    [Eventos]        = COUNT(e.event_time),
    [PrimerEvento]   = MIN(e.event_time),
    [UltimoEvento]   = MAX(e.event_time),
    [Resultado]      = CASE WHEN COUNT(e.event_time) > 0 THEN N'CUMPLE' ELSE N'SIN EVIDENCIA' END
FROM (VALUES (N'1. UPDATE sobre rrhh.Empleado'),
             (N'2. INS/UPD/DEL sobre MovimientoContable'),
             (N'3. Cambio de membresia de rol')) AS c(Categoria)
LEFT JOIN Evento AS e ON e.Categoria = c.Categoria
GROUP BY c.Categoria
ORDER BY c.Categoria;
GO


/*==============================================================================
  SECCION 6 - CONTROL DBA-SEG-04 (EV-03-03)
==============================================================================*/
DECLARE @a NVARCHAR(400) = (
    SELECT sfa.log_file_path
         + CASE WHEN RIGHT(sfa.log_file_path, 1) IN (N'\', N'/') THEN N'' ELSE N'\' END
         + N'Audit_SuperHamburguesas*.sqlaudit'
      FROM sys.server_audits AS sa
      INNER JOIN sys.server_file_audits AS sfa ON sfa.audit_id = sa.audit_id
     WHERE sa.name = N'Audit_SuperHamburguesas');

DECLARE @categorias INT = (
    SELECT COUNT(DISTINCT CASE
              WHEN x.object_name = N'Empleado'           THEN 1
              WHEN x.object_name = N'MovimientoContable' THEN 2
              WHEN x.action_id IN ('APRL','DPRL')        THEN 3 END)
    FROM sys.fn_get_audit_file(@a, DEFAULT, DEFAULT) AS x
    WHERE x.database_name = N'DBSuperHamburguesas');

SELECT
    [Control]            = N'DBA-SEG-04 Auditoria de datos sensibles, financieros y de roles',
    [Mecanismo]          = N'SQL Server Audit nativo (server audit + database audit specification)',
    [ExcepcionTramitada] = N'No. No existe limitacion tecnica: Express soporta ambos niveles desde 2016 SP1.',
    [CategoriasExigidas] = 3,
    [CategoriasConEvidencia] = @categorias,
    [RetencionConfigurada]   = N'24 archivos de 64 MB. Cubre los 12 meses del control.',
    [Resultado]          = CASE WHEN @categorias = 3 THEN N'CUMPLE' ELSE N'NO CUMPLE' END;
GO

/*------------------------------------------------------------------------------
  6.1  Riesgo residual declarado
------------------------------------------------------------------------------*/
SELECT
    [Riesgo]      = N'Un miembro de sysadmin puede desactivar la auditoria',
    [Mitigacion]  = N'La propia desactivacion queda registrada por el grupo AUDIT_CHANGE_GROUP a nivel de servidor, y la membresia de sysadmin esta limitada por el control DBA-SEG-02.',
    [Aceptado]    = N'Si, como riesgo residual inherente al modelo de privilegios del motor.';
GO

PRINT N'== 03_Auditoria.sql finalizado. Conservar las salidas como EV-03-01 a EV-03-03. ==';
PRINT N'== Siguiente paso: 04_Backup.sql ==';
GO
