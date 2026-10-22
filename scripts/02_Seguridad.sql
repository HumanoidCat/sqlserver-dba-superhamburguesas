/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        02_Seguridad.sql
  Proposito:     Implementar el control de acceso de DBSuperHamburguesas:
                 12 roles de base de datos, 12 logins, 12 usuarios, la matriz
                 completa de permisos con restricciones a nivel de columna, los
                 tres casos de proteccion de informacion sensible y las doce
                 pruebas de autorizacion (seccion 7.2 y 7.3 del entregable).

  Controles del Entregable 1 que implementa:
                 DBA-SEG-01  Permisos asignados por rol, nunca a usuarios.
                 DBA-SEG-02  Sin roles fijos de alcance amplio para negocio.
                 DBA-SEG-03  Proteccion de columnas sensibles con permiso a
                             nivel de columna y prueba permitida/denegada.
                 DBA-COD-01  Objetos calificados por esquema; sin SELECT *.

  Precondiciones:1) 00_CreateDatabase.sql y 01_Modelo.sql ejecutados con exito.
                 2) La instancia admite autenticacion de SQL Server (modo mixto).
                    Verificado en EV-00-01: IsIntegratedSecurityOnly = 0.
                 3) Cuenta con permisos para crear logins (sysadmin o
                    securityadmin) y usuarios en la base.
  Orden:         Script 02. Despues de 01_Modelo.sql, antes de 03_Auditoria.sql.
  Destructivo:   PARCIALMENTE. La SECCION 0.1 elimina usuarios, roles y logins
                 previos. Viene DESACTIVADA.
  Reejecutable:  SI. Roles, logins y usuarios se crean solo si no existen, y las
                 concesiones son idempotentes. La tabla de pruebas se recrea en
                 cada ejecucion, de modo que la evidencia corresponde siempre a
                 la corrida mas reciente.
  Resultado
  esperado:      12 roles, 12 logins, 12 usuarios y 47 concesiones aplicadas.
                 La SECCION 6 ejecuta 12 pruebas de autorizacion y la SECCION 7
                 imprime cinco conjuntos de verificacion. Guardar la salida de
                 las secciones 6 y 7 como evidencias EV-02-01 a EV-02-03.

  ---------------------------------------------------------------------------
  DECISIONES DE IMPLEMENTACION
  ---------------------------------------------------------------------------
  Permisos solo a roles
    Ninguna concesion tiene como beneficiario un usuario. La SECCION 7.3
    comprueba esta condicion de forma programatica sobre sys.database_permissions
    y falla de forma visible si aparece cualquier excepcion.

  Restricciones por columna en lugar de la tabla completa
    Donde la matriz del enunciado excluye un atributo, el permiso se otorga con
    GRANT SELECT ON OBJECT::tabla(lista de columnas). Otorgar la tabla completa
    y confiar en que la aplicacion no consulte la columna excluida no es un
    control: es una convencion. El motor debe denegar el acceso.
    Consecuencia conocida y deseada: un SELECT * sobre esas tablas falla para el
    rol restringido. Esa es justamente la demostracion del control, y coincide
    con la prohibicion de SELECT * de la disposicion 9.2.2 del estandar.

  Ausencia deliberada de DELETE
    La matriz prohibe DELETE en la mayoria de las tablas por diseno del negocio:
    el catalogo se desactiva con su bandera, los movimientos de inventario no
    admiten ni UPDATE ni DELETE para preservar el historial, y los movimientos
    contables no admiten DELETE para mantener la trazabilidad financiera. No es
    una omision: es el control, y se prueba en la SECCION 6.

  Denegacion del esquema administrativo
    Los doce roles de negocio reciben DENY sobre el esquema dba. Una sola
    sentencia por rol cubre todos los objetos administrativos presentes y
    futuros, incluido el registro de auditoria que crea 03_Auditoria.sql.

  El permiso CONNECT y el control DBA-SEG-01
    CREATE USER otorga CONNECT al usuario de forma automatica. Ese permiso no es
    una concesion de acceso a datos: es la condicion para abrir sesion, y sin el
    ningun control podria probarse. La verificacion del control lo excluye y lo
    reporta por separado, de modo que el conteo de doce quede explicado y no
    parezca un incumplimiento encubierto.

  Por que las pruebas no usan COUNT(*)
    Con permisos otorgados a nivel de columna, COUNT(*) y SELECT * fallan con el
    error 230 aunque el rol tenga autorizadas todas las columnas que necesita:
    el motor evalua el permiso contra el objeto completo, no contra el conjunto
    de columnas que la consulta llegaria a leer. Las pruebas positivas nombran
    por tanto columnas concretas. Esto no es un rodeo para que la prueba pase:
    es exactamente el comportamiento que hace efectivo el control de la
    disposicion 5.3.3 y coincide con la prohibicion de SELECT * de la 9.2.2.

  Credenciales academicas
    Las contrasenas son unicamente academicas, se declaran en una variable al
    inicio y no corresponden a credenciales reales de ninguna persona ni sistema.
    CHECK_POLICY queda activo para cumplir la disposicion 5.1.2 del estandar.
==============================================================================*/

SET NOCOUNT ON;
GO

USE DBSuperHamburguesas;
GO

/*==============================================================================
  SECCION 0 - GUARDAS Y REINICIO
==============================================================================*/

/*------------------------------------------------------------------------------
  0.1  REINICIO DE SEGURIDAD (DESTRUCTIVO - DESACTIVADO)
  Elimina usuarios, roles y logins del proyecto. Descomentar solo para
  reconstruir la capa de seguridad desde cero.
------------------------------------------------------------------------------*/
/*
USE DBSuperHamburguesas;
DECLARE @sqlDrop NVARCHAR(MAX) = N'';
SELECT @sqlDrop = @sqlDrop + N'DROP USER ' + QUOTENAME(dp.name) + N';' + CHAR(10)
FROM sys.database_principals AS dp
WHERE dp.type IN ('S','U') AND dp.name LIKE N'usr_%';
SELECT @sqlDrop = @sqlDrop + N'DROP ROLE ' + QUOTENAME(dp.name) + N';' + CHAR(10)
FROM sys.database_principals AS dp
WHERE dp.type = 'R' AND dp.name LIKE N'rol_%';
EXEC sys.sp_executesql @sqlDrop;
GO
USE master;
DECLARE @sqlLogin NVARCHAR(MAX) = N'';
SELECT @sqlLogin = @sqlLogin + N'DROP LOGIN ' + QUOTENAME(sp.name) + N';' + CHAR(10)
FROM sys.server_principals AS sp
WHERE sp.type = 'S' AND sp.name LIKE N'usr_%';
EXEC sys.sp_executesql @sqlLogin;
GO
USE DBSuperHamburguesas;
GO
*/

/*------------------------------------------------------------------------------
  0.2  Verificacion de precondiciones
------------------------------------------------------------------------------*/
IF DB_NAME() <> N'DBSuperHamburguesas'
BEGIN
    RAISERROR(N'Este script debe ejecutarse sobre DBSuperHamburguesas.', 16, 1);
    RETURN;
END

IF NOT EXISTS (SELECT 1 FROM sys.tables AS t
               INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
               WHERE s.name = N'catalogo' AND t.name = N'Hamburguesa')
BEGIN
    RAISERROR(N'El modelo no existe. Ejecute 01_Modelo.sql antes de este script.', 16, 1);
    RETURN;
END

IF CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS INT) = 1
BEGIN
    RAISERROR(N'La instancia esta en modo solo Windows. Habilite el modo mixto y reinicie el servicio.', 16, 1);
    RETURN;
END
PRINT N'Precondiciones verificadas.';
GO


/*==============================================================================
  SECCION 1 - ROLES DE BASE DE DATOS
  Dos perfiles por dominio. Cada rol declara por escrito lo que habilita.
==============================================================================*/

-- catalogo: productos, ingredientes, recetas e impuestos.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_catalogo_consulta' AND type = 'R')
    CREATE ROLE rol_catalogo_consulta;    -- Lectura del catalogo. SIN costo de ingrediente.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_catalogo_gestion' AND type = 'R')
    CREATE ROLE rol_catalogo_gestion;     -- Mantenimiento del catalogo. CON costo. Sin DELETE salvo relaciones.
GO

-- ventas: clientes, pedidos y detalle.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_ventas_consulta' AND type = 'R')
    CREATE ROLE rol_ventas_consulta;      -- Lectura del proceso comercial y del catalogo vendible.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_ventas_gestion' AND type = 'R')
    CREATE ROLE rol_ventas_gestion;       -- Registro y modificacion de pedidos. Sin DELETE.
GO

-- inventario: existencias y movimientos.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_inventario_consulta' AND type = 'R')
    CREATE ROLE rol_inventario_consulta;  -- Lectura de existencias y movimientos. SIN costo de ingrediente.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_inventario_gestion' AND type = 'R')
    CREATE ROLE rol_inventario_gestion;   -- Ajuste de existencias y registro de movimientos. Historial inmutable.
GO

-- rrhh: personal.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_rrhh_consulta' AND type = 'R')
    CREATE ROLE rol_rrhh_consulta;        -- Lectura limitada. SIN identificacion, fecha de nacimiento ni salario.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_rrhh_gestion' AND type = 'R')
    CREATE ROLE rol_rrhh_gestion;         -- Administracion de personal, incluido salario. Sin DELETE.
GO

-- proveedores: abastecimiento.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_proveedores_consulta' AND type = 'R')
    CREATE ROLE rol_proveedores_consulta; -- Lectura. SIN precio de referencia ni costo de ingrediente.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_proveedores_gestion' AND type = 'R')
    CREATE ROLE rol_proveedores_gestion;  -- Administracion del abastecimiento, incluido el precio negociado.
GO

-- contabilidad: cuentas y movimientos financieros.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_contabilidad_consulta' AND type = 'R')
    CREATE ROLE rol_contabilidad_consulta;-- Lectura del catalogo contable y sus movimientos.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'rol_contabilidad_gestion' AND type = 'R')
    CREATE ROLE rol_contabilidad_gestion; -- Registro contable. Sin DELETE por trazabilidad financiera.
GO

PRINT N'Doce roles de dominio creados.';
GO


/*==============================================================================
  SECCION 2 - LOGINS Y USUARIOS
  Doce cuentas nominativas segun la lista de la seccion 7.2 del entregable.
  Credenciales exclusivamente academicas.
==============================================================================*/

USE master;
GO

DECLARE @clave SYSNAME = N'Inv3nio$Proy2#2026';   -- Clave academica comun. No corresponde a ninguna credencial real.
DECLARE @sql   NVARCHAR(MAX) = N'';

;WITH Persona(Usuario, Nombre, Apellido) AS (
    SELECT N'usr_ana_rodriguez',       N'Ana',      N'Rodriguez'  UNION ALL
    SELECT N'usr_andres_rodriguez',    N'Andres',   N'Rodriguez'  UNION ALL
    SELECT N'usr_carlos_castro',       N'Carlos',   N'Castro'     UNION ALL
    SELECT N'usr_daniela_delgado',     N'Daniela',  N'Delgado'    UNION ALL
    SELECT N'usr_esteban_vargas',      N'Esteban',  N'Vargas'     UNION ALL
    SELECT N'usr_fernanda_mora',       N'Fernanda', N'Mora'       UNION ALL
    SELECT N'usr_gabriela_gonzalez',   N'Gabriela', N'Gonzalez'   UNION ALL
    SELECT N'usr_jose_jimenez',        N'Jose',     N'Jimenez'    UNION ALL
    SELECT N'usr_laura_solano',        N'Laura',    N'Solano'     UNION ALL
    SELECT N'usr_luis_solano',         N'Luis',     N'Solano'     UNION ALL
    SELECT N'usr_maria_mendez',        N'Maria',    N'Mendez'     UNION ALL
    SELECT N'usr_mauricio_mendez',     N'Mauricio', N'Mendez'
)
SELECT @sql = @sql +
    N'IF SUSER_ID(' + QUOTENAME(p.Usuario, '''') + N') IS NULL ' +
    N'CREATE LOGIN ' + QUOTENAME(p.Usuario) +
    N' WITH PASSWORD = ' + QUOTENAME(@clave, '''') +
    N', DEFAULT_DATABASE = DBSuperHamburguesas' +
    N', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;' + CHAR(10)
FROM Persona AS p;

EXEC sys.sp_executesql @sql;
PRINT N'Doce logins creados o ya existentes.';
GO

USE DBSuperHamburguesas;
GO

DECLARE @sqlU NVARCHAR(MAX) = N'';
;WITH Persona(Usuario) AS (
    SELECT N'usr_ana_rodriguez'     UNION ALL SELECT N'usr_andres_rodriguez' UNION ALL
    SELECT N'usr_carlos_castro'     UNION ALL SELECT N'usr_daniela_delgado'  UNION ALL
    SELECT N'usr_esteban_vargas'    UNION ALL SELECT N'usr_fernanda_mora'    UNION ALL
    SELECT N'usr_gabriela_gonzalez' UNION ALL SELECT N'usr_jose_jimenez'     UNION ALL
    SELECT N'usr_laura_solano'      UNION ALL SELECT N'usr_luis_solano'      UNION ALL
    SELECT N'usr_maria_mendez'      UNION ALL SELECT N'usr_mauricio_mendez'
)
SELECT @sqlU = @sqlU +
    N'IF DATABASE_PRINCIPAL_ID(' + QUOTENAME(p.Usuario, '''') + N') IS NULL ' +
    N'CREATE USER ' + QUOTENAME(p.Usuario) + N' FOR LOGIN ' + QUOTENAME(p.Usuario) + N';' + CHAR(10)
FROM Persona AS p;

EXEC sys.sp_executesql @sqlU;
PRINT N'Doce usuarios de base de datos creados.';
GO

/*------------------------------------------------------------------------------
  2.1  Membresias
  Gabriela Gonzalez pertenece a DOS roles, conforme a la lista del enunciado.
------------------------------------------------------------------------------*/
ALTER ROLE rol_catalogo_consulta     ADD MEMBER usr_ana_rodriguez;
ALTER ROLE rol_catalogo_gestion      ADD MEMBER usr_andres_rodriguez;
ALTER ROLE rol_ventas_consulta       ADD MEMBER usr_carlos_castro;
ALTER ROLE rol_ventas_gestion        ADD MEMBER usr_daniela_delgado;
ALTER ROLE rol_inventario_consulta   ADD MEMBER usr_esteban_vargas;
ALTER ROLE rol_inventario_gestion    ADD MEMBER usr_fernanda_mora;
ALTER ROLE rol_rrhh_consulta         ADD MEMBER usr_gabriela_gonzalez;
ALTER ROLE rol_catalogo_consulta     ADD MEMBER usr_gabriela_gonzalez;   -- segundo rol
ALTER ROLE rol_rrhh_gestion          ADD MEMBER usr_jose_jimenez;
ALTER ROLE rol_proveedores_consulta  ADD MEMBER usr_laura_solano;
ALTER ROLE rol_proveedores_gestion   ADD MEMBER usr_luis_solano;
ALTER ROLE rol_contabilidad_consulta ADD MEMBER usr_maria_mendez;
ALTER ROLE rol_contabilidad_gestion  ADD MEMBER usr_mauricio_mendez;
GO

PRINT N'Membresias asignadas.';
GO


/*==============================================================================
  SECCION 3 - DENEGACION DEL ESQUEMA ADMINISTRATIVO
  Los roles de negocio no deben alcanzar los objetos administrativos, presentes
  ni futuros, incluido el registro de auditoria de 03_Auditoria.sql.
==============================================================================*/
DENY SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dba TO
    rol_catalogo_consulta,     rol_catalogo_gestion,
    rol_ventas_consulta,       rol_ventas_gestion,
    rol_inventario_consulta,   rol_inventario_gestion,
    rol_rrhh_consulta,         rol_rrhh_gestion,
    rol_proveedores_consulta,  rol_proveedores_gestion,
    rol_contabilidad_consulta, rol_contabilidad_gestion;
GO

PRINT N'Esquema administrativo denegado a los doce roles de negocio.';
GO


/*==============================================================================
  SECCION 4 - MATRIZ DE PERMISOS
  Implementa literalmente la matriz de la seccion 7.2 del entregable.
  Toda tabla no listada para un rol queda sin acceso: no hay permisos implicitos.
==============================================================================*/

/*--------------------------------------------------------------
  4.1  Dominio catalogo
--------------------------------------------------------------*/
-- Consulta: todas las columnas salvo el costo del ingrediente.
GRANT SELECT ON OBJECT::catalogo.Hamburguesa         TO rol_catalogo_consulta;
GRANT SELECT ON OBJECT::catalogo.Ingrediente
      (IngredienteID, Nombre, UnidadMedida, Activo)  TO rol_catalogo_consulta;  -- CASO 1: sin CostoReferencia
GRANT SELECT ON OBJECT::catalogo.RecetaHamburguesa   TO rol_catalogo_consulta;
GRANT SELECT ON OBJECT::catalogo.TipoImpuesto        TO rol_catalogo_consulta;
GRANT SELECT ON OBJECT::catalogo.HamburguesaImpuesto TO rol_catalogo_consulta;

-- Gestion: incluye el costo. Sin DELETE en las entidades principales.
GRANT SELECT, INSERT, UPDATE         ON OBJECT::catalogo.Hamburguesa         TO rol_catalogo_gestion;
GRANT SELECT, INSERT, UPDATE         ON OBJECT::catalogo.Ingrediente         TO rol_catalogo_gestion;
GRANT SELECT, INSERT, UPDATE, DELETE ON OBJECT::catalogo.RecetaHamburguesa   TO rol_catalogo_gestion;
GRANT SELECT, INSERT, UPDATE         ON OBJECT::catalogo.TipoImpuesto        TO rol_catalogo_gestion;
GRANT SELECT, INSERT, UPDATE, DELETE ON OBJECT::catalogo.HamburguesaImpuesto TO rol_catalogo_gestion;
GO

/*--------------------------------------------------------------
  4.2  Dominio ventas
--------------------------------------------------------------*/
GRANT SELECT ON OBJECT::ventas.Cliente       TO rol_ventas_consulta;
GRANT SELECT ON OBJECT::ventas.EstadoPedido  TO rol_ventas_consulta;
GRANT SELECT ON OBJECT::ventas.Pedido        TO rol_ventas_consulta;
GRANT SELECT ON OBJECT::ventas.PedidoDetalle TO rol_ventas_consulta;
-- Dependencia entre dominios, concedida de forma explicita y acotada.
GRANT SELECT ON OBJECT::catalogo.Hamburguesa TO rol_ventas_consulta;
GRANT SELECT ON OBJECT::catalogo.TipoImpuesto TO rol_ventas_consulta;

GRANT SELECT, INSERT, UPDATE ON OBJECT::ventas.Cliente       TO rol_ventas_gestion;
GRANT SELECT                 ON OBJECT::ventas.EstadoPedido  TO rol_ventas_gestion;  -- catalogo de control
GRANT SELECT, INSERT, UPDATE ON OBJECT::ventas.Pedido        TO rol_ventas_gestion;  -- cancelar por estado, no borrar
GRANT SELECT, INSERT, UPDATE ON OBJECT::ventas.PedidoDetalle TO rol_ventas_gestion;
GRANT SELECT ON OBJECT::catalogo.Hamburguesa  TO rol_ventas_gestion;                 -- no modifica catalogo
GRANT SELECT ON OBJECT::catalogo.TipoImpuesto TO rol_ventas_gestion;
GO

/*--------------------------------------------------------------
  4.3  Dominio inventario
--------------------------------------------------------------*/
GRANT SELECT ON OBJECT::inventario.ExistenciaIngrediente     TO rol_inventario_consulta;
GRANT SELECT ON OBJECT::inventario.TipoMovimientoInventario  TO rol_inventario_consulta;
GRANT SELECT ON OBJECT::inventario.MovimientoInventario      TO rol_inventario_consulta;
GRANT SELECT ON OBJECT::catalogo.Ingrediente
      (IngredienteID, Nombre, UnidadMedida, Activo)          TO rol_inventario_consulta;  -- CASO 1

GRANT SELECT, INSERT, UPDATE ON OBJECT::inventario.ExistenciaIngrediente    TO rol_inventario_gestion;
GRANT SELECT                 ON OBJECT::inventario.TipoMovimientoInventario TO rol_inventario_gestion;
GRANT SELECT, INSERT         ON OBJECT::inventario.MovimientoInventario     TO rol_inventario_gestion;  -- historial inmutable
GRANT SELECT                 ON OBJECT::catalogo.Ingrediente                TO rol_inventario_gestion;  -- con costo, sin modificar
GO

/*--------------------------------------------------------------
  4.4  Dominio rrhh
--------------------------------------------------------------*/
GRANT SELECT ON OBJECT::rrhh.Departamento TO rol_rrhh_consulta;
GRANT SELECT ON OBJECT::rrhh.Puesto       TO rol_rrhh_consulta;
-- CASO 2: identifica al trabajador y sus datos laborales, sin los tres atributos sensibles.
GRANT SELECT ON OBJECT::rrhh.Empleado
      (EmpleadoID, Nombre, Apellido, Telefono, Correo, FechaIngreso,
       DepartamentoID, PuestoID, Estado)  TO rol_rrhh_consulta;

GRANT SELECT, INSERT, UPDATE ON OBJECT::rrhh.Departamento TO rol_rrhh_gestion;
GRANT SELECT, INSERT, UPDATE ON OBJECT::rrhh.Puesto       TO rol_rrhh_gestion;
GRANT SELECT, INSERT, UPDATE ON OBJECT::rrhh.Empleado     TO rol_rrhh_gestion;  -- todas las columnas, incluido Salario
GO

/*--------------------------------------------------------------
  4.5  Dominio proveedores
--------------------------------------------------------------*/
GRANT SELECT ON OBJECT::proveedores.Proveedor TO rol_proveedores_consulta;
-- CASO 3: sabe quien suministra que, pero no el precio negociado.
GRANT SELECT ON OBJECT::proveedores.ProveedorIngrediente
      (ProveedorID, IngredienteID, TiempoEntregaDias)   TO rol_proveedores_consulta;
GRANT SELECT ON OBJECT::catalogo.Ingrediente
      (IngredienteID, Nombre, UnidadMedida, Activo)     TO rol_proveedores_consulta;  -- CASO 1

GRANT SELECT, INSERT, UPDATE         ON OBJECT::proveedores.Proveedor            TO rol_proveedores_gestion;
GRANT SELECT, INSERT, UPDATE, DELETE ON OBJECT::proveedores.ProveedorIngrediente TO rol_proveedores_gestion;
GRANT SELECT                         ON OBJECT::catalogo.Ingrediente             TO rol_proveedores_gestion;
GO

/*--------------------------------------------------------------
  4.6  Dominio contabilidad
--------------------------------------------------------------*/
GRANT SELECT ON OBJECT::contabilidad.CuentaContable     TO rol_contabilidad_consulta;
GRANT SELECT ON OBJECT::contabilidad.MovimientoContable TO rol_contabilidad_consulta;

GRANT SELECT, INSERT, UPDATE ON OBJECT::contabilidad.CuentaContable     TO rol_contabilidad_gestion;
GRANT SELECT, INSERT, UPDATE ON OBJECT::contabilidad.MovimientoContable TO rol_contabilidad_gestion;  -- sin DELETE
GO

PRINT N'Matriz de permisos aplicada.';
GO


/*==============================================================================
  SECCION 5 - TABLA DE RESULTADOS DE PRUEBA
  Las pruebas de la SECCION 6 registran aqui su resultado, de modo que la
  evidencia sea una consulta y no una lectura manual de mensajes.
==============================================================================*/
DROP TABLE IF EXISTS dba.PruebaAutorizacion;
GO
CREATE TABLE dba.PruebaAutorizacion
(
    PruebaID       INT IDENTITY(1,1) NOT NULL,
    Momento        DATETIME2(0) NOT NULL
        CONSTRAINT DF_PruebaAutorizacion_Momento DEFAULT (SYSDATETIME()),
    Tipo           NVARCHAR(10) NOT NULL,
    Usuario        SYSNAME NOT NULL,
    Operacion      NVARCHAR(300) NOT NULL,
    Esperado       NVARCHAR(20) NOT NULL,
    Obtenido       NVARCHAR(20) NOT NULL,
    NumeroError    INT NULL,
    MensajeError   NVARCHAR(2000) NULL,
    Veredicto      AS (CASE WHEN Esperado = Obtenido THEN N'CUMPLE' ELSE N'NO CUMPLE' END),

    CONSTRAINT PK_PruebaAutorizacion PRIMARY KEY (PruebaID),
    CONSTRAINT CK_PruebaAutorizacion_Tipo CHECK (Tipo IN (N'POSITIVA', N'NEGATIVA'))
);
GO


/*==============================================================================
  SECCION 6 - DOCE PRUEBAS DE AUTORIZACION
  Seis positivas y seis negativas. Cada bloque suplanta el contexto del usuario,
  intenta la operacion, captura el resultado real y revierte el contexto.
  Las negativas capturan el numero y el texto del error devuelto por el motor.
==============================================================================*/

/*--- POSITIVA 1: consulta de catalogo accede a los ingredientes sin el costo ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_ana_rodriguez';
    DECLARE @p1 INT = (SELECT COUNT(i.IngredienteID) FROM catalogo.Ingrediente AS i);
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'POSITIVA', N'usr_ana_rodriguez',
            N'SELECT COUNT(IngredienteID) FROM catalogo.Ingrediente (columnas autorizadas)', N'PERMITIDO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'POSITIVA', N'usr_ana_rodriguez',
            N'SELECT COUNT(IngredienteID) FROM catalogo.Ingrediente (columnas autorizadas)', N'PERMITIDO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- NEGATIVA 1 (CASO 1): consulta de catalogo NO ve el costo de referencia ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_ana_rodriguez';
    DECLARE @n1 DECIMAL(12,4) = (SELECT TOP (1) CostoReferencia FROM catalogo.Ingrediente ORDER BY IngredienteID);
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'NEGATIVA', N'usr_ana_rodriguez',
            N'SELECT CostoReferencia FROM catalogo.Ingrediente', N'DENEGADO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'NEGATIVA', N'usr_ana_rodriguez',
            N'SELECT CostoReferencia FROM catalogo.Ingrediente', N'DENEGADO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- POSITIVA 2 (CASO 1): gestion de catalogo SI consulta el costo ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_andres_rodriguez';
    DECLARE @p2 DECIMAL(12,4) = (SELECT TOP (1) CostoReferencia FROM catalogo.Ingrediente ORDER BY IngredienteID);
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'POSITIVA', N'usr_andres_rodriguez',
            N'SELECT CostoReferencia FROM catalogo.Ingrediente', N'PERMITIDO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'POSITIVA', N'usr_andres_rodriguez',
            N'SELECT CostoReferencia FROM catalogo.Ingrediente', N'PERMITIDO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- NEGATIVA 2: gestion de catalogo NO puede eliminar hamburguesas ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_andres_rodriguez';
    DELETE FROM catalogo.Hamburguesa WHERE HamburguesaID = -1;   -- no afecta filas; se prueba el permiso
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'NEGATIVA', N'usr_andres_rodriguez',
            N'DELETE FROM catalogo.Hamburguesa', N'DENEGADO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'NEGATIVA', N'usr_andres_rodriguez',
            N'DELETE FROM catalogo.Hamburguesa', N'DENEGADO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- POSITIVA 3: consulta de ventas lee pedidos y el catalogo vendible ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_carlos_castro';
    DECLARE @p3 INT = (SELECT COUNT(*) FROM ventas.Pedido AS p
                       INNER JOIN ventas.PedidoDetalle AS d ON d.PedidoID = p.PedidoID
                       INNER JOIN catalogo.Hamburguesa AS h ON h.HamburguesaID = d.HamburguesaID);
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'POSITIVA', N'usr_carlos_castro',
            N'SELECT con union de ventas.Pedido, PedidoDetalle y catalogo.Hamburguesa', N'PERMITIDO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'POSITIVA', N'usr_carlos_castro',
            N'SELECT con union de ventas.Pedido, PedidoDetalle y catalogo.Hamburguesa', N'PERMITIDO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- NEGATIVA 3: consulta de ventas NO puede modificar pedidos ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_carlos_castro';
    UPDATE ventas.Pedido SET EstadoPedidoID = 4 WHERE PedidoID = -1;
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'NEGATIVA', N'usr_carlos_castro',
            N'UPDATE ventas.Pedido', N'DENEGADO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'NEGATIVA', N'usr_carlos_castro',
            N'UPDATE ventas.Pedido', N'DENEGADO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- NEGATIVA 4: gestion de inventario NO puede alterar el historial ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_fernanda_mora';
    UPDATE inventario.MovimientoInventario SET Cantidad = 1 WHERE MovimientoInventarioID = -1;
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'NEGATIVA', N'usr_fernanda_mora',
            N'UPDATE inventario.MovimientoInventario', N'DENEGADO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'NEGATIVA', N'usr_fernanda_mora',
            N'UPDATE inventario.MovimientoInventario', N'DENEGADO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- POSITIVA 4: gestion de inventario SI ajusta existencias ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_fernanda_mora';
    UPDATE inventario.ExistenciaIngrediente
       SET FechaUltimaActualizacion = FechaUltimaActualizacion
     WHERE IngredienteID = -1;
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'POSITIVA', N'usr_fernanda_mora',
            N'UPDATE inventario.ExistenciaIngrediente', N'PERMITIDO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'POSITIVA', N'usr_fernanda_mora',
            N'UPDATE inventario.ExistenciaIngrediente', N'PERMITIDO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- POSITIVA 5 (CASO 2): consulta de rrhh identifica al trabajador ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_gabriela_gonzalez';
    DECLARE @p5n NVARCHAR(100), @p5a NVARCHAR(100), @p5f DATE;
    SELECT TOP (1) @p5n = e.Nombre, @p5a = e.Apellido, @p5f = e.FechaIngreso
    FROM rrhh.Empleado AS e ORDER BY e.EmpleadoID;
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'POSITIVA', N'usr_gabriela_gonzalez',
            N'SELECT Nombre, Apellido, FechaIngreso FROM rrhh.Empleado', N'PERMITIDO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'POSITIVA', N'usr_gabriela_gonzalez',
            N'SELECT Nombre, Apellido, FechaIngreso FROM rrhh.Empleado', N'PERMITIDO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- NEGATIVA 5 (CASO 2): consulta de rrhh NO visualiza el salario ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_gabriela_gonzalez';
    DECLARE @n5 DECIMAL(14,2) = (SELECT TOP (1) Salario FROM rrhh.Empleado ORDER BY EmpleadoID);
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'NEGATIVA', N'usr_gabriela_gonzalez',
            N'SELECT Salario FROM rrhh.Empleado', N'DENEGADO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'NEGATIVA', N'usr_gabriela_gonzalez',
            N'SELECT Salario FROM rrhh.Empleado', N'DENEGADO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- POSITIVA 6 (CASO 2): gestion de rrhh SI accede al salario ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_jose_jimenez';
    DECLARE @p6 DECIMAL(14,2) = (SELECT TOP (1) Salario FROM rrhh.Empleado ORDER BY EmpleadoID);
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'POSITIVA', N'usr_jose_jimenez',
            N'SELECT Salario FROM rrhh.Empleado', N'PERMITIDO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'POSITIVA', N'usr_jose_jimenez',
            N'SELECT Salario FROM rrhh.Empleado', N'PERMITIDO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- NEGATIVA 6 (CASO 3): consulta de proveedores NO ve el precio negociado ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_laura_solano';
    DECLARE @n6 DECIMAL(12,4) = (SELECT TOP (1) PrecioReferencia FROM proveedores.ProveedorIngrediente
                                 ORDER BY ProveedorID, IngredienteID);
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'NEGATIVA', N'usr_laura_solano',
            N'SELECT PrecioReferencia FROM proveedores.ProveedorIngrediente', N'DENEGADO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'NEGATIVA', N'usr_laura_solano',
            N'SELECT PrecioReferencia FROM proveedores.ProveedorIngrediente', N'DENEGADO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- EXTRA (CASO 3): gestion de proveedores SI consulta el precio negociado ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_luis_solano';
    DECLARE @p7 DECIMAL(12,4) = (SELECT TOP (1) PrecioReferencia FROM proveedores.ProveedorIngrediente
                                 ORDER BY ProveedorID, IngredienteID);
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'POSITIVA', N'usr_luis_solano',
            N'SELECT PrecioReferencia FROM proveedores.ProveedorIngrediente', N'PERMITIDO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'POSITIVA', N'usr_luis_solano',
            N'SELECT PrecioReferencia FROM proveedores.ProveedorIngrediente', N'PERMITIDO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- EXTRA: contabilidad de gestion NO puede eliminar movimientos ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_mauricio_mendez';
    DELETE FROM contabilidad.MovimientoContable WHERE MovimientoContableID = -1;
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'NEGATIVA', N'usr_mauricio_mendez',
            N'DELETE FROM contabilidad.MovimientoContable', N'DENEGADO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'NEGATIVA', N'usr_mauricio_mendez',
            N'DELETE FROM contabilidad.MovimientoContable', N'DENEGADO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO

/*--- EXTRA: ningun rol de negocio alcanza el esquema administrativo ---*/
BEGIN TRY
    EXECUTE AS USER = 'usr_maria_mendez';
    DECLARE @n8 INT = (SELECT COUNT(*) FROM dba.PruebaAutorizacion);
    REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido)
    VALUES (N'NEGATIVA', N'usr_maria_mendez',
            N'SELECT sobre el esquema administrativo dba', N'DENEGADO', N'PERMITIDO');
END TRY
BEGIN CATCH
    IF SESSION_USER <> ORIGINAL_LOGIN() REVERT;
    INSERT INTO dba.PruebaAutorizacion (Tipo, Usuario, Operacion, Esperado, Obtenido, NumeroError, MensajeError)
    VALUES (N'NEGATIVA', N'usr_maria_mendez',
            N'SELECT sobre el esquema administrativo dba', N'DENEGADO', N'DENEGADO',
            ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH
GO


/*==============================================================================
  SECCION 7 - VERIFICACION Y EVIDENCIA
==============================================================================*/

-- 7.1  EV-02-01: resultado de las pruebas de autorizacion
SELECT
    [Momento]   = Momento,
    [Tipo]      = Tipo,
    [Usuario]   = Usuario,
    [Operacion] = Operacion,
    [Esperado]  = Esperado,
    [Obtenido]  = Obtenido,
    [Veredicto] = Veredicto,
    [NumError]  = NumeroError,
    [Mensaje]   = LEFT(MensajeError, 160)
FROM dba.PruebaAutorizacion
ORDER BY PruebaID;

SELECT
    [Resumen]        = N'Pruebas de autorizacion',
    [Positivas]      = SUM(CASE WHEN Tipo = N'POSITIVA' THEN 1 ELSE 0 END),
    [Negativas]      = SUM(CASE WHEN Tipo = N'NEGATIVA' THEN 1 ELSE 0 END),
    [Cumplen]        = SUM(CASE WHEN Veredicto = N'CUMPLE' THEN 1 ELSE 0 END),
    [NoCumplen]      = SUM(CASE WHEN Veredicto = N'NO CUMPLE' THEN 1 ELSE 0 END),
    [Resultado]      = CASE WHEN SUM(CASE WHEN Veredicto = N'NO CUMPLE' THEN 1 ELSE 0 END) = 0
                            THEN N'TODAS CUMPLEN' ELSE N'REVISAR' END
FROM dba.PruebaAutorizacion;
GO

-- 7.2  EV-02-02: matriz de permisos efectiva, con columnas cuando aplica
SELECT
    [Rol]       = pr.name,
    [Ambito]    = perm.class_desc,
    [Esquema]   = CASE perm.class_desc
                      WHEN 'SCHEMA'           THEN SCHEMA_NAME(perm.major_id)
                      WHEN 'OBJECT_OR_COLUMN' THEN SCHEMA_NAME(o.schema_id)
                      ELSE N'(base de datos)' END,
    [Objeto]    = CASE perm.class_desc
                      WHEN 'SCHEMA'           THEN N'(todo el esquema)'
                      WHEN 'OBJECT_OR_COLUMN' THEN o.name
                      ELSE N'-' END,
    [Permiso]   = perm.permission_name,
    [Estado]    = perm.state_desc,
    [Columna]   = ISNULL(c.name, N'(todas las autorizadas)')
FROM sys.database_permissions AS perm
INNER JOIN sys.database_principals AS pr ON pr.principal_id = perm.grantee_principal_id
LEFT JOIN sys.objects AS o ON o.object_id = perm.major_id AND perm.class_desc = 'OBJECT_OR_COLUMN'
LEFT JOIN sys.columns AS c ON c.object_id = perm.major_id AND c.column_id = perm.minor_id
                          AND perm.class_desc = 'OBJECT_OR_COLUMN' AND perm.minor_id > 0
WHERE pr.name LIKE N'rol_%'
ORDER BY pr.name, perm.class_desc, [Esquema], [Objeto], perm.permission_name, c.name;
GO

-- 7.3  Control DBA-SEG-01: ningun permiso otorgado directamente a un usuario
-- CONNECT se excluye de forma deliberada: SQL Server lo otorga al usuario en el
-- momento de crearlo y sin el la cuenta no puede abrir sesion, de modo que no
-- podria probarse ningun control. No es una concesion de acceso a datos, que es
-- lo que el control DBA-SEG-01 regula. Se muestra aparte para que quede a la
-- vista que el dato se conocia y se descarto con criterio, no por omision.
SELECT
    [Control]           = N'DBA-SEG-01 Permisos de acceso a datos solo a roles',
    [PermisosAUsuarios] = COUNT(*),
    [Resultado]         = CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.database_permissions AS perm
INNER JOIN sys.database_principals AS pr ON pr.principal_id = perm.grantee_principal_id
WHERE pr.type IN ('S','U')
  AND pr.name LIKE N'usr_%'
  AND perm.permission_name <> N'CONNECT';

SELECT
    [Detalle]   = N'Permisos CONNECT, inherentes a la creacion del usuario',
    [Cantidad]  = COUNT(*),
    [Nota]      = N'Esperado: uno por usuario. No constituyen acceso a datos.'
FROM sys.database_permissions AS perm
INNER JOIN sys.database_principals AS pr ON pr.principal_id = perm.grantee_principal_id
WHERE pr.type IN ('S','U') AND pr.name LIKE N'usr_%' AND perm.permission_name = N'CONNECT';
GO

-- 7.4  Control DBA-SEG-02: ningun usuario de negocio en roles fijos amplios
SELECT
    [Control]   = N'DBA-SEG-02 Sin roles fijos de alcance amplio',
    [Casos]     = COUNT(*),
    [Resultado] = CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.database_role_members AS drm
INNER JOIN sys.database_principals AS rol ON rol.principal_id = drm.role_principal_id
INNER JOIN sys.database_principals AS usu ON usu.principal_id = drm.member_principal_id
WHERE usu.name LIKE N'usr_%'
  AND rol.name IN (N'db_owner', N'db_datareader', N'db_datawriter',
                   N'db_ddladmin', N'db_securityadmin', N'db_accessadmin');
GO

-- 7.5  EV-02-03: membresia efectiva de cada usuario
SELECT
    [Usuario] = usu.name,
    [Roles]   = STRING_AGG(rol.name, N', ') WITHIN GROUP (ORDER BY rol.name)
FROM sys.database_principals AS usu
LEFT JOIN sys.database_role_members AS drm ON drm.member_principal_id = usu.principal_id
LEFT JOIN sys.database_principals  AS rol ON rol.principal_id = drm.role_principal_id
WHERE usu.name LIKE N'usr_%'
GROUP BY usu.name
ORDER BY usu.name;
GO

-- 7.6  Conteo general
SELECT
    [Roles creados]      = (SELECT COUNT(*) FROM sys.database_principals WHERE type = 'R' AND name LIKE N'rol_%'),
    [Usuarios creados]   = (SELECT COUNT(*) FROM sys.database_principals WHERE type IN ('S','U') AND name LIKE N'usr_%'),
    [Concesiones]        = (SELECT COUNT(*) FROM sys.database_permissions AS pm
                            INNER JOIN sys.database_principals AS p2 ON p2.principal_id = pm.grantee_principal_id
                            WHERE p2.name LIKE N'rol_%' AND pm.state_desc = 'GRANT'),
    [Denegaciones]       = (SELECT COUNT(*) FROM sys.database_permissions AS pm
                            INNER JOIN sys.database_principals AS p2 ON p2.principal_id = pm.grantee_principal_id
                            WHERE p2.name LIKE N'rol_%' AND pm.state_desc = 'DENY');
GO

PRINT N'== 02_Seguridad.sql finalizado. Conservar las salidas como EV-02-01, EV-02-02 y EV-02-03. ==';
PRINT N'== Siguiente paso: 03_Auditoria.sql ==';
GO
