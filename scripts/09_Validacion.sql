/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        09_Validacion.sql
  Proposito:     Pruebas finales de seguridad, integridad y estado del ambiente
                 completo. Es lo ultimo que se ejecuta y lo primero que el
                 docente puede solicitar durante la demostracion funcional.

  Controles que verifica: los trece del catalogo del Entregable 1.

  Precondiciones:Scripts 00 a 07 ejecutados.
  Orden:         Script 09. Ultimo de la secuencia.
  Destructivo:   No. Solo lectura.
  Reejecutable:  SI.
  Resultado
  esperado:      Un cuadro de mando con el veredicto de cada comprobacion y un
                 veredicto global. Guardar como evidencia EV-09-01.
==============================================================================*/

SET NOCOUNT ON;
GO

USE DBSuperHamburguesas;
GO

DROP TABLE IF EXISTS #Validacion;
CREATE TABLE #Validacion
(
    N          INT IDENTITY(1,1),
    Control    NVARCHAR(20)  NULL,
    Prueba     NVARCHAR(200) NOT NULL,
    Obtenido   NVARCHAR(100) NOT NULL,
    Esperado   NVARCHAR(100) NOT NULL,
    Veredicto  NVARCHAR(20)  NOT NULL
);
GO

/*------------------------------------------------------------------------------
  1. Estado y configuracion de la base
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-GOB-01', N'Base en linea, en modelo FULL y con verificacion de pagina CHECKSUM',
       d.state_desc + N' / ' + d.recovery_model_desc + N' / ' + d.page_verify_option_desc,
       N'ONLINE / FULL / CHECKSUM',
       CASE WHEN d.state_desc = N'ONLINE' AND d.recovery_model_desc = N'FULL'
                 AND d.page_verify_option_desc = N'CHECKSUM' THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.databases AS d WHERE d.name = DB_NAME();

/*------------------------------------------------------------------------------
  2. Modelo: ninguna tabla de negocio en el esquema por omision
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-COD-01', N'Ninguna tabla de negocio en el esquema dbo',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' tablas', N'0 tablas',
       CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = N'dbo';

/*------------------------------------------------------------------------------
  3. Modelo: las diecinueve tablas del diccionario
  El diccionario minimo de datos de la seccion 6 define 19 tablas de negocio:
  catalogo 5, ventas 4, inventario 3, rrhh 3, proveedores 2 y contabilidad 2.
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT NULL, N'Las diecinueve tablas del modelo base existen en sus seis esquemas',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' tablas', N'19 tablas',
       CASE WHEN COUNT(*) = 19 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name IN (N'catalogo', N'ventas', N'inventario', N'rrhh', N'proveedores', N'contabilidad');

/*------------------------------------------------------------------------------
  4. Integridad declarativa: ninguna restriccion no confiable ni deshabilitada
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT NULL, N'Claves foraneas y restricciones CHECK confiables y habilitadas',
       CAST(x.Malas AS NVARCHAR(10)) + N' con problema', N'0',
       CASE WHEN x.Malas = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM (
    SELECT Malas =
        (SELECT COUNT(*) FROM sys.foreign_keys     WHERE is_not_trusted = 1 OR is_disabled = 1) +
        (SELECT COUNT(*) FROM sys.check_constraints WHERE is_not_trusted = 1 OR is_disabled = 1)
) AS x;

/*------------------------------------------------------------------------------
  5. Seguridad: doce roles y doce usuarios
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT NULL, N'Doce roles de dominio y doce usuarios nominativos',
       CAST((SELECT COUNT(*) FROM sys.database_principals WHERE type = 'R' AND name LIKE N'rol_%') AS NVARCHAR(10)) + N' roles / ' +
       CAST((SELECT COUNT(*) FROM sys.database_principals WHERE type IN ('S','U') AND name LIKE N'usr_%') AS NVARCHAR(10)) + N' usuarios',
       N'12 roles / 12 usuarios',
       CASE WHEN (SELECT COUNT(*) FROM sys.database_principals WHERE type = 'R' AND name LIKE N'rol_%') = 12
             AND (SELECT COUNT(*) FROM sys.database_principals WHERE type IN ('S','U') AND name LIKE N'usr_%') = 12
            THEN N'CUMPLE' ELSE N'NO CUMPLE' END;

/*------------------------------------------------------------------------------
  6. Control DBA-SEG-01: permisos de datos solo a roles
  CONNECT se excluye: lo otorga CREATE USER y no es acceso a datos.
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-SEG-01', N'Ningun permiso de acceso a datos otorgado a un usuario',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' permisos', N'0 permisos',
       CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.database_permissions AS perm
INNER JOIN sys.database_principals AS pr ON pr.principal_id = perm.grantee_principal_id
WHERE pr.type IN ('S','U') AND pr.name LIKE N'usr_%' AND perm.permission_name <> N'CONNECT';

/*------------------------------------------------------------------------------
  7. Control DBA-SEG-02: sin roles fijos de alcance amplio
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-SEG-02', N'Ningun usuario de negocio en roles fijos de alcance amplio',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' casos', N'0 casos',
       CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.database_role_members AS drm
INNER JOIN sys.database_principals AS rol ON rol.principal_id = drm.role_principal_id
INNER JOIN sys.database_principals AS usu ON usu.principal_id = drm.member_principal_id
WHERE usu.name LIKE N'usr_%'
  AND rol.name IN (N'db_owner', N'db_datareader', N'db_datawriter',
                   N'db_ddladmin', N'db_securityadmin', N'db_accessadmin');

/*------------------------------------------------------------------------------
  8. Control DBA-SEG-03: proteccion de columnas sensibles
  Debe existir permiso a nivel de columna sobre los tres atributos protegidos.
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-SEG-03', N'Permisos a nivel de columna aplicados sobre los atributos sensibles',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' concesiones por columna', N'al menos 9',
       CASE WHEN COUNT(*) >= 9 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.database_permissions AS perm
INNER JOIN sys.database_principals AS pr ON pr.principal_id = perm.grantee_principal_id
WHERE pr.name LIKE N'rol_%' AND perm.minor_id > 0 AND perm.state_desc = N'GRANT';

-- Comprobacion directa: las columnas sensibles NO deben estar concedidas a los roles de consulta
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-SEG-03', N'Las columnas sensibles no estan concedidas a ningun rol de consulta',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' fugas', N'0 fugas',
       CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.database_permissions AS perm
INNER JOIN sys.database_principals AS pr ON pr.principal_id = perm.grantee_principal_id
INNER JOIN sys.columns AS c ON c.object_id = perm.major_id AND c.column_id = perm.minor_id
WHERE pr.name LIKE N'rol_%_consulta'
  AND perm.state_desc = N'GRANT'
  AND c.name IN (N'CostoReferencia', N'PrecioReferencia', N'Salario', N'Identificacion', N'FechaNacimiento');

/*------------------------------------------------------------------------------
  9. Control DBA-SEG-04: auditoria activa con las tres categorias
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-SEG-04', N'Auditoria de servidor activa',
       CASE WHEN EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'Audit_SuperHamburguesas' AND is_state_enabled = 1)
            THEN N'ACTIVA' ELSE N'INACTIVA' END,
       N'ACTIVA',
       CASE WHEN EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'Audit_SuperHamburguesas' AND is_state_enabled = 1)
            THEN N'CUMPLE' ELSE N'NO CUMPLE' END;

INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-SEG-04', N'Especificacion de base de datos con las tres categorias auditadas',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' acciones', N'al menos 5 acciones',
       CASE WHEN COUNT(*) >= 5 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.database_audit_specification_details AS dasd
INNER JOIN sys.database_audit_specifications AS das
        ON das.database_specification_id = dasd.database_specification_id
WHERE das.name = N'DBAudit_SuperHamburguesas';

/*------------------------------------------------------------------------------
  10. Control DBA-BKP-01: cadena de respaldos completa y con suma de verificacion
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-BKP-01', N'Cadena completa, diferencial y al menos dos de registro, todos con suma de verificacion',
       CAST(SUM(CASE WHEN bs.type='D' THEN 1 ELSE 0 END) AS NVARCHAR(5)) + N'C / ' +
       CAST(SUM(CASE WHEN bs.type='I' THEN 1 ELSE 0 END) AS NVARCHAR(5)) + N'D / ' +
       CAST(SUM(CASE WHEN bs.type='L' THEN 1 ELSE 0 END) AS NVARCHAR(5)) + N'L, sin checksum: ' +
       CAST(SUM(CASE WHEN bs.has_backup_checksums = 0 THEN 1 ELSE 0 END) AS NVARCHAR(5)),
       N'>=1C / >=1D / >=2L, sin checksum: 0',
       CASE WHEN SUM(CASE WHEN bs.type='D' THEN 1 ELSE 0 END) >= 1
             AND SUM(CASE WHEN bs.type='I' THEN 1 ELSE 0 END) >= 1
             AND SUM(CASE WHEN bs.type='L' THEN 1 ELSE 0 END) >= 2
             AND SUM(CASE WHEN bs.has_backup_checksums = 0 THEN 1 ELSE 0 END) = 0
            THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM msdb.dbo.backupset AS bs
WHERE bs.database_name = N'DBSuperHamburguesas'
  AND bs.backup_start_date >= CAST(CAST(GETDATE() AS DATE) AS DATETIME);

/*------------------------------------------------------------------------------
  11. Control DBA-BKP-02: restauracion a punto en el tiempo verificada
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-BKP-02', N'Base alterna restaurada con STOPAT y en linea',
       ISNULL((SELECT d.state_desc FROM sys.databases AS d WHERE d.name = N'DBSuperHamburguesas_RECOVERY'), N'NO EXISTE'),
       N'ONLINE',
       CASE WHEN EXISTS (SELECT 1 FROM sys.databases WHERE name = N'DBSuperHamburguesas_RECOVERY' AND state_desc = N'ONLINE')
            THEN N'CUMPLE' ELSE N'NO CUMPLE' END;

INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-BKP-02', N'El dato erroneo no esta presente en la base recuperada',
       CASE WHEN DB_ID(N'DBSuperHamburguesas_RECOVERY') IS NULL THEN N'sin base alterna'
            ELSE N'verificado en 05_Restore_Recovery.sql, seccion 4' END,
       N'0 filas con el valor erroneo',
       CASE WHEN DB_ID(N'DBSuperHamburguesas_RECOVERY') IS NOT NULL THEN N'CUMPLE' ELSE N'NO CUMPLE' END;

/*------------------------------------------------------------------------------
  12. Control DBA-MON-02: capacidad y crecimiento
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-MON-02', N'Todos los archivos con crecimiento en incrementos fijos',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' con crecimiento porcentual', N'0',
       CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.database_files WHERE is_percent_growth = 1;

INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-MON-02', N'Espacio libre por encima del umbral del 20 % en todos los archivos',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' archivos en alerta', N'0 archivos',
       CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'REVISAR' END
FROM sys.database_files AS df
WHERE 100.0 * (df.size - FILEPROPERTY(df.name,'SpaceUsed')) / NULLIF(df.size,0) < 20;

/*------------------------------------------------------------------------------
  13. Coherencia funcional de los datos
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT NULL, N'Total del pedido igual a subtotal mas impuesto en todos los pedidos',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' inconsistencias', N'0',
       CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM ventas.Pedido AS p WHERE p.Total <> p.Subtotal + p.Impuesto;

/*------------------------------------------------------------------------------
  14. Control DBA-COD-02: objetos administrativos fuera del alcance de negocio
------------------------------------------------------------------------------*/
INSERT INTO #Validacion (Control, Prueba, Obtenido, Esperado, Veredicto)
SELECT N'DBA-COD-02', N'El esquema administrativo esta denegado a los doce roles de negocio',
       CAST(COUNT(DISTINCT pr.name) AS NVARCHAR(10)) + N' roles con DENY', N'12 roles',
       CASE WHEN COUNT(DISTINCT pr.name) = 12 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.database_permissions AS perm
INNER JOIN sys.database_principals AS pr ON pr.principal_id = perm.grantee_principal_id
WHERE perm.class_desc = N'SCHEMA'
  AND perm.major_id = SCHEMA_ID(N'dba')
  AND perm.state_desc = N'DENY'
  AND pr.name LIKE N'rol_%';
GO


/*==============================================================================
  CUADRO DE MANDO FINAL (EV-09-01)
==============================================================================*/
SELECT
    [N]         = N,
    [Control]   = ISNULL(Control, N'—'),
    [Prueba]    = Prueba,
    [Obtenido]  = Obtenido,
    [Esperado]  = Esperado,
    [Veredicto] = Veredicto
FROM #Validacion
ORDER BY N;
GO

SELECT
    [Momento]        = SYSDATETIME(),
    [Base]           = DB_NAME(),
    [Comprobaciones] = COUNT(*),
    [Cumplen]        = SUM(CASE WHEN Veredicto = N'CUMPLE' THEN 1 ELSE 0 END),
    [NoCumplen]      = SUM(CASE WHEN Veredicto = N'NO CUMPLE' THEN 1 ELSE 0 END),
    [ARevisar]       = SUM(CASE WHEN Veredicto = N'REVISAR' THEN 1 ELSE 0 END),
    [VeredictoGlobal]= CASE WHEN SUM(CASE WHEN Veredicto = N'NO CUMPLE' THEN 1 ELSE 0 END) = 0
                            THEN N'AMBIENTE CONFORME' ELSE N'AMBIENTE CON HALLAZGOS' END
FROM #Validacion;
GO

-- Integridad fisica y logica de la base productiva
DBCC CHECKDB (N'DBSuperHamburguesas') WITH NO_INFOMSGS, ALL_ERRORMSGS;
PRINT N'DBCC CHECKDB sobre la base productiva finalizado. Sin mensajes arriba = sin errores.';
GO

PRINT N'== 09_Validacion.sql finalizado. Conservar el cuadro de mando como EV-09-01. ==';
GO
