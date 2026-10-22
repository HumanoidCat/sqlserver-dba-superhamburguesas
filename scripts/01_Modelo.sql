/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        01_Modelo.sql
  Proposito:     Implementar el modelo fisico de DBSuperHamburguesas: los seis
                 esquemas de negocio, las 18 tablas del diccionario con sus
                 PK, FK, CHECK, UNIQUE y DEFAULT, los catalogos de control y
                 el volumen de datos de prueba reproducible (secciones 5, 5.1
                 y 6.1 del entregable).

  Controles del Entregable 1 que implementa:
                 DBA-COD-01  Objetos calificados por esquema; sin proyeccion de
                             todas las columnas en codigo productivo.
                 DBA-COD-02  Script versionado, ordenado, sin credenciales ni
                             rutas personales, con bloque destructivo declarado.
                 DBA-GOB-01  El modelo queda bajo la base creada en el script 00,
                             cuyo propietario ya fue asignado de forma explicita.

  Precondiciones:1) 00_CreateDatabase.sql ejecutado con exito.
                 2) La base DBSuperHamburguesas existe, esta en linea y en
                    modelo de recuperacion FULL.
                 3) La base NO contiene todavia los esquemas de negocio.
  Orden:         Script 01. Se ejecuta despues de 00 y antes de 02_Seguridad.sql.
  Destructivo:   PARCIALMENTE. La SECCION 0.1 elimina todos los objetos del
                 modelo y viene DESACTIVADA. Solo debe habilitarse para
                 reconstruir el ambiente de pruebas desde cero.
  Duracion
  aproximada:    Entre 1 y 3 minutos, dominados por la carga de la seccion 5.
  Resultado
  esperado:      18 tablas creadas, catalogos y datos maestros cargados, y el
                 volumen transaccional de la seccion 5. La SECCION 6 imprime
                 seis conjuntos de verificacion. Guardar su salida completa
                 como evidencia EV-01-01.

  ---------------------------------------------------------------------------
  DECISIONES DE IMPLEMENTACION
  ---------------------------------------------------------------------------
  Fidelidad al modelo base
    El DDL de la SECCION 2 reproduce literalmente el diccionario minimo de
    datos entregado por el docente. No se renombra, elimina ni altera ninguna
    tabla, columna, clave ni restriccion. Se conservan incluso los nombres de
    restriccion originales, que ya cumplen la convencion del Entregable 1.

  Esquema administrativo dba
    Se crea un esquema dba para alojar los objetos administrativos que exigen
    las secciones posteriores: el registro de auditoria complementario y la
    tabla de numeros auxiliar. Justificacion tecnica: la seccion 5 del
    entregable prohibe que permanezcan tablas de negocio en dbo y admite
    objetos administrativos con justificacion. Un esquema propio permite,
    ademas, denegar su acceso a los doce roles de negocio en 02_Seguridad.sql
    con una sola sentencia, en lugar de objeto por objeto.

  Ausencia deliberada de indices no agrupados
    No se crea ningun indice no agrupado fuera de los que las restricciones PK
    y UNIQUE generan por si mismas. El caso de rendimiento de 07_Rendimiento.sql
    debe medir un antes y un despues reales; sembrar aqui el indice que ese
    script propone anularia la comparacion.

  Reproducibilidad de los datos de prueba
    La seccion 5 no utiliza NEWID() ni RAND() sin semilla. Los valores derivan
    de una funcion determinista del numero de fila, de modo que dos ejecuciones
    del script sobre bases limpias producen exactamente los mismos datos. Esto
    es lo que permite comparar las evidencias de antes y despues del incidente
    logico que se simula en 05_Restore_Recovery.sql.

  Volumen y consumo de registro
    La base opera en modelo FULL, por lo que la carga masiva se registra
    integramente en el log. El volumen se dimensiono para consumir bastante
    menos que los 128 MB preasignados al archivo de registro. Si aun asi el log
    creciera, ello indica que la base ya acumulaba transacciones previas y debe
    ejecutarse un respaldo de log antes de continuar.

  Ausencia de ON DELETE CASCADE
    Ninguna relacion utiliza propagacion de borrado. El modelo depende de la
    trazabilidad de pedidos y movimientos; una eliminacion en cascada destruiria
    silenciosamente el historial que la seccion 7.5 debe recuperar.

  Sin informacion personal real
    Los nombres de clientes y empleados se componen a partir de listas de
    nombres y apellidos de uso general combinadas de forma deterministica. No
    corresponden a personas reales ni provienen de ninguna fuente de datos
    personales.
==============================================================================*/

SET NOCOUNT ON;
GO

USE DBSuperHamburguesas;
GO


/*==============================================================================
  SECCION 0 - GUARDAS Y REINICIO
==============================================================================*/

/*------------------------------------------------------------------------------
  0.1  REINICIO DEL MODELO (DESTRUCTIVO - DESACTIVADO)
  Elimina las 18 tablas y los esquemas. Descomentar UNICAMENTE para reconstruir
  el modelo sobre una base ya creada. El orden respeta las dependencias de FK.
------------------------------------------------------------------------------*/
/*
DROP TABLE IF EXISTS ventas.PedidoDetalle;
DROP TABLE IF EXISTS ventas.Pedido;
DROP TABLE IF EXISTS ventas.Cliente;
DROP TABLE IF EXISTS ventas.EstadoPedido;
DROP TABLE IF EXISTS inventario.MovimientoInventario;
DROP TABLE IF EXISTS inventario.ExistenciaIngrediente;
DROP TABLE IF EXISTS inventario.TipoMovimientoInventario;
DROP TABLE IF EXISTS proveedores.ProveedorIngrediente;
DROP TABLE IF EXISTS proveedores.Proveedor;
DROP TABLE IF EXISTS contabilidad.MovimientoContable;
DROP TABLE IF EXISTS contabilidad.CuentaContable;
DROP TABLE IF EXISTS rrhh.Empleado;
DROP TABLE IF EXISTS rrhh.Puesto;
DROP TABLE IF EXISTS rrhh.Departamento;
DROP TABLE IF EXISTS catalogo.HamburguesaImpuesto;
DROP TABLE IF EXISTS catalogo.RecetaHamburguesa;
DROP TABLE IF EXISTS catalogo.TipoImpuesto;
DROP TABLE IF EXISTS catalogo.Ingrediente;
DROP TABLE IF EXISTS catalogo.Hamburguesa;
DROP TABLE IF EXISTS dba.Numero;
GO
DROP SCHEMA IF EXISTS ventas;
DROP SCHEMA IF EXISTS inventario;
DROP SCHEMA IF EXISTS proveedores;
DROP SCHEMA IF EXISTS contabilidad;
DROP SCHEMA IF EXISTS rrhh;
DROP SCHEMA IF EXISTS catalogo;
DROP SCHEMA IF EXISTS dba;
GO
PRINT N'AVISO: modelo eliminado.';
GO
*/

/*------------------------------------------------------------------------------
  0.2  Verificacion de precondiciones
------------------------------------------------------------------------------*/
IF DB_NAME() <> N'DBSuperHamburguesas'
BEGIN
    RAISERROR(N'Este script debe ejecutarse sobre DBSuperHamburguesas. Contexto actual incorrecto.', 16, 1);
    RETURN;
END

IF (SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()) <> N'FULL'
BEGIN
    RAISERROR(N'La base no esta en modelo de recuperacion FULL. Revise 00_CreateDatabase.sql.', 16, 1);
    RETURN;
END

IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'catalogo')
BEGIN
    RAISERROR(N'Los esquemas de negocio ya existen. Revise la SECCION 0.1 antes de continuar.', 16, 1);
    RETURN;
END
PRINT N'Precondiciones verificadas.';
GO


/*==============================================================================
  SECCION 1 - ESQUEMAS
  Los seis esquemas de negocio deben existir antes de las tablas, conforme al
  requisito previo declarado en el diccionario minimo de datos.
==============================================================================*/
CREATE SCHEMA catalogo;
GO
CREATE SCHEMA ventas;
GO
CREATE SCHEMA inventario;
GO
CREATE SCHEMA rrhh;
GO
CREATE SCHEMA proveedores;
GO
CREATE SCHEMA contabilidad;
GO

-- Esquema administrativo. Ver la justificacion tecnica del encabezado.
CREATE SCHEMA dba;
GO

PRINT N'Siete esquemas creados: seis de negocio y uno administrativo.';
GO


/*==============================================================================
  SECCION 2 - TABLAS DEL MODELO BASE
  DDL reproducido literalmente del diccionario minimo de datos entregado.
==============================================================================*/

/*--------------------------------------------------------------
  2.1  Esquema catalogo
--------------------------------------------------------------*/
CREATE TABLE catalogo.Hamburguesa
(
    HamburguesaID INT IDENTITY(1,1) NOT NULL,
    Nombre        NVARCHAR(100) NOT NULL,
    Descripcion   NVARCHAR(300) NULL,
    PrecioBase    DECIMAL(12,2) NOT NULL,
    Activa        BIT NOT NULL
        CONSTRAINT DF_Hamburguesa_Activa DEFAULT (1),

    CONSTRAINT PK_Hamburguesa
        PRIMARY KEY (HamburguesaID),

    CONSTRAINT UQ_Hamburguesa_Nombre
        UNIQUE (Nombre),

    CONSTRAINT CK_Hamburguesa_PrecioBase
        CHECK (PrecioBase >= 0)
);
GO

CREATE TABLE catalogo.Ingrediente
(
    IngredienteID   INT IDENTITY(1,1) NOT NULL,
    Nombre          NVARCHAR(100) NOT NULL,
    UnidadMedida    NVARCHAR(20) NOT NULL,
    CostoReferencia DECIMAL(12,4) NOT NULL,
    Activo          BIT NOT NULL
        CONSTRAINT DF_Ingrediente_Activo DEFAULT (1),

    CONSTRAINT PK_Ingrediente
        PRIMARY KEY (IngredienteID),

    CONSTRAINT CK_Ingrediente_CostoReferencia
        CHECK (CostoReferencia >= 0)
);
GO

CREATE TABLE catalogo.RecetaHamburguesa
(
    RecetaID          INT IDENTITY(1,1) NOT NULL,
    HamburguesaID     INT NOT NULL,
    IngredienteID     INT NOT NULL,
    CantidadRequerida DECIMAL(12,3) NOT NULL,

    CONSTRAINT PK_RecetaHamburguesa
        PRIMARY KEY (RecetaID),

    CONSTRAINT FK_RecetaHamburguesa_Hamburguesa
        FOREIGN KEY (HamburguesaID)
        REFERENCES catalogo.Hamburguesa(HamburguesaID),

    CONSTRAINT FK_RecetaHamburguesa_Ingrediente
        FOREIGN KEY (IngredienteID)
        REFERENCES catalogo.Ingrediente(IngredienteID),

    CONSTRAINT UQ_RecetaHamburguesa_Hamburguesa_Ingrediente
        UNIQUE (HamburguesaID, IngredienteID),

    CONSTRAINT CK_RecetaHamburguesa_CantidadRequerida
        CHECK (CantidadRequerida > 0)
);
GO

CREATE TABLE catalogo.TipoImpuesto
(
    TipoImpuestoID INT IDENTITY(1,1) NOT NULL,
    Nombre         NVARCHAR(80) NOT NULL,
    Porcentaje     DECIMAL(5,2) NOT NULL,
    Activo         BIT NOT NULL
        CONSTRAINT DF_TipoImpuesto_Activo DEFAULT (1),

    CONSTRAINT PK_TipoImpuesto
        PRIMARY KEY (TipoImpuestoID),

    CONSTRAINT CK_TipoImpuesto_Porcentaje
        CHECK (Porcentaje >= 0 AND Porcentaje <= 100)
);
GO

CREATE TABLE catalogo.HamburguesaImpuesto
(
    HamburguesaID INT NOT NULL,
    TipoImpuestoID INT NOT NULL,

    CONSTRAINT PK_HamburguesaImpuesto
        PRIMARY KEY (HamburguesaID, TipoImpuestoID),

    CONSTRAINT FK_HamburguesaImpuesto_Hamburguesa
        FOREIGN KEY (HamburguesaID)
        REFERENCES catalogo.Hamburguesa(HamburguesaID),

    CONSTRAINT FK_HamburguesaImpuesto_TipoImpuesto
        FOREIGN KEY (TipoImpuestoID)
        REFERENCES catalogo.TipoImpuesto(TipoImpuestoID)
);
GO

/*--------------------------------------------------------------
  2.2  Esquema ventas
--------------------------------------------------------------*/
CREATE TABLE ventas.Cliente
(
    ClienteID INT IDENTITY(1,1) NOT NULL,
    Nombre    NVARCHAR(100) NOT NULL,
    Apellido  NVARCHAR(100) NOT NULL,
    Telefono  NVARCHAR(30) NULL,
    Correo    NVARCHAR(150) NULL,
    Direccion NVARCHAR(300) NULL,
    Activo    BIT NOT NULL
        CONSTRAINT DF_Cliente_Activo DEFAULT (1),

    CONSTRAINT PK_Cliente
        PRIMARY KEY (ClienteID)
);
GO

CREATE TABLE ventas.EstadoPedido
(
    EstadoPedidoID TINYINT NOT NULL,
    NombreEstado   NVARCHAR(40) NOT NULL,

    CONSTRAINT PK_EstadoPedido
        PRIMARY KEY (EstadoPedidoID)
);
GO

CREATE TABLE ventas.Pedido
(
    PedidoID       BIGINT IDENTITY(1,1) NOT NULL,
    ClienteID      INT NOT NULL,
    FechaPedido    DATETIME2(0) NOT NULL
        CONSTRAINT DF_Pedido_FechaPedido DEFAULT (SYSDATETIME()),
    EstadoPedidoID TINYINT NOT NULL,
    Subtotal       DECIMAL(14,2) NOT NULL,
    Impuesto       DECIMAL(14,2) NOT NULL,
    Total          DECIMAL(14,2) NOT NULL,

    CONSTRAINT PK_Pedido
        PRIMARY KEY (PedidoID),

    CONSTRAINT FK_Pedido_Cliente
        FOREIGN KEY (ClienteID)
        REFERENCES ventas.Cliente(ClienteID),

    CONSTRAINT FK_Pedido_EstadoPedido
        FOREIGN KEY (EstadoPedidoID)
        REFERENCES ventas.EstadoPedido(EstadoPedidoID),

    CONSTRAINT CK_Pedido_Subtotal
        CHECK (Subtotal >= 0),

    CONSTRAINT CK_Pedido_Impuesto
        CHECK (Impuesto >= 0),

    CONSTRAINT CK_Pedido_Total
        CHECK (Total >= 0)
);
GO

CREATE TABLE ventas.PedidoDetalle
(
    PedidoDetalleID BIGINT IDENTITY(1,1) NOT NULL,
    PedidoID        BIGINT NOT NULL,
    HamburguesaID   INT NOT NULL,
    Cantidad        SMALLINT NOT NULL,
    PrecioUnitario  DECIMAL(12,2) NOT NULL,
    SubtotalLinea   DECIMAL(14,2) NOT NULL,

    CONSTRAINT PK_PedidoDetalle
        PRIMARY KEY (PedidoDetalleID),

    CONSTRAINT FK_PedidoDetalle_Pedido
        FOREIGN KEY (PedidoID)
        REFERENCES ventas.Pedido(PedidoID),

    CONSTRAINT FK_PedidoDetalle_Hamburguesa
        FOREIGN KEY (HamburguesaID)
        REFERENCES catalogo.Hamburguesa(HamburguesaID),

    CONSTRAINT CK_PedidoDetalle_Cantidad
        CHECK (Cantidad > 0),

    CONSTRAINT CK_PedidoDetalle_PrecioUnitario
        CHECK (PrecioUnitario >= 0),

    CONSTRAINT CK_PedidoDetalle_SubtotalLinea
        CHECK (SubtotalLinea >= 0)
);
GO

/*--------------------------------------------------------------
  2.3  Esquema inventario
--------------------------------------------------------------*/
CREATE TABLE inventario.ExistenciaIngrediente
(
    IngredienteID            INT NOT NULL,
    StockActual              DECIMAL(14,3) NOT NULL,
    StockMinimo              DECIMAL(14,3) NOT NULL,
    StockMaximo              DECIMAL(14,3) NOT NULL,
    FechaUltimaActualizacion DATETIME2(0) NOT NULL,

    CONSTRAINT PK_ExistenciaIngrediente
        PRIMARY KEY (IngredienteID),

    CONSTRAINT FK_ExistenciaIngrediente_Ingrediente
        FOREIGN KEY (IngredienteID)
        REFERENCES catalogo.Ingrediente(IngredienteID),

    CONSTRAINT CK_ExistenciaIngrediente_StockActual
        CHECK (StockActual >= 0),

    CONSTRAINT CK_ExistenciaIngrediente_StockMinimo
        CHECK (StockMinimo >= 0),

    CONSTRAINT CK_ExistenciaIngrediente_StockMaximo
        CHECK (StockMaximo >= StockMinimo)
);
GO

CREATE TABLE inventario.TipoMovimientoInventario
(
    TipoMovimientoID TINYINT NOT NULL,
    NombreTipo        NVARCHAR(30) NOT NULL,

    CONSTRAINT PK_TipoMovimientoInventario
        PRIMARY KEY (TipoMovimientoID)
);
GO

CREATE TABLE inventario.MovimientoInventario
(
    MovimientoInventarioID BIGINT IDENTITY(1,1) NOT NULL,
    IngredienteID          INT NOT NULL,
    TipoMovimientoID       TINYINT NOT NULL,
    FechaMovimiento        DATETIME2(0) NOT NULL
        CONSTRAINT DF_MovimientoInventario_FechaMovimiento
        DEFAULT (SYSDATETIME()),
    Cantidad               DECIMAL(14,3) NOT NULL,
    CostoUnitario          DECIMAL(12,4) NULL,
    Observacion            NVARCHAR(300) NULL,

    CONSTRAINT PK_MovimientoInventario
        PRIMARY KEY (MovimientoInventarioID),

    CONSTRAINT FK_MovimientoInventario_Ingrediente
        FOREIGN KEY (IngredienteID)
        REFERENCES catalogo.Ingrediente(IngredienteID),

    CONSTRAINT FK_MovimientoInventario_TipoMovimiento
        FOREIGN KEY (TipoMovimientoID)
        REFERENCES inventario.TipoMovimientoInventario(TipoMovimientoID),

    CONSTRAINT CK_MovimientoInventario_Cantidad
        CHECK (Cantidad > 0)
);
GO

/*--------------------------------------------------------------
  2.4  Esquema rrhh
--------------------------------------------------------------*/
CREATE TABLE rrhh.Departamento
(
    DepartamentoID SMALLINT IDENTITY(1,1) NOT NULL,
    Nombre         NVARCHAR(100) NOT NULL,
    Descripcion    NVARCHAR(250) NULL,

    CONSTRAINT PK_Departamento
        PRIMARY KEY (DepartamentoID)
);
GO

CREATE TABLE rrhh.Puesto
(
    PuestoID    SMALLINT IDENTITY(1,1) NOT NULL,
    Nombre      NVARCHAR(100) NOT NULL,
    Descripcion NVARCHAR(250) NULL,

    CONSTRAINT PK_Puesto
        PRIMARY KEY (PuestoID)
);
GO

CREATE TABLE rrhh.Empleado
(
    EmpleadoID      INT IDENTITY(1,1) NOT NULL,
    Identificacion  NVARCHAR(30) NOT NULL,
    Nombre          NVARCHAR(100) NOT NULL,
    Apellido        NVARCHAR(100) NOT NULL,
    FechaNacimiento DATE NULL,
    Telefono        NVARCHAR(30) NULL,
    Correo          NVARCHAR(150) NULL,
    FechaIngreso    DATE NOT NULL,
    DepartamentoID  SMALLINT NOT NULL,
    PuestoID        SMALLINT NOT NULL,
    Salario         DECIMAL(14,2) NOT NULL,
    Estado          NVARCHAR(20) NOT NULL,

    CONSTRAINT PK_Empleado
        PRIMARY KEY (EmpleadoID),

    CONSTRAINT UQ_Empleado_Identificacion
        UNIQUE (Identificacion),

    CONSTRAINT FK_Empleado_Departamento
        FOREIGN KEY (DepartamentoID)
        REFERENCES rrhh.Departamento(DepartamentoID),

    CONSTRAINT FK_Empleado_Puesto
        FOREIGN KEY (PuestoID)
        REFERENCES rrhh.Puesto(PuestoID),

    CONSTRAINT CK_Empleado_Salario
        CHECK (Salario >= 0)
);
GO

/*--------------------------------------------------------------
  2.5  Esquema proveedores
--------------------------------------------------------------*/
CREATE TABLE proveedores.Proveedor
(
    ProveedorID          INT IDENTITY(1,1) NOT NULL,
    IdentificacionFiscal NVARCHAR(30) NOT NULL,
    NombreProveedor      NVARCHAR(150) NOT NULL,
    Contacto             NVARCHAR(150) NULL,
    Telefono             NVARCHAR(30) NULL,
    Correo               NVARCHAR(150) NULL,
    Activo               BIT NOT NULL
        CONSTRAINT DF_Proveedor_Activo DEFAULT (1),

    CONSTRAINT PK_Proveedor
        PRIMARY KEY (ProveedorID),

    CONSTRAINT UQ_Proveedor_IdentificacionFiscal
        UNIQUE (IdentificacionFiscal)
);
GO

CREATE TABLE proveedores.ProveedorIngrediente
(
    ProveedorID        INT NOT NULL,
    IngredienteID      INT NOT NULL,
    PrecioReferencia   DECIMAL(12,4) NOT NULL,
    TiempoEntregaDias  SMALLINT NOT NULL,

    CONSTRAINT PK_ProveedorIngrediente
        PRIMARY KEY (ProveedorID, IngredienteID),

    CONSTRAINT FK_ProveedorIngrediente_Proveedor
        FOREIGN KEY (ProveedorID)
        REFERENCES proveedores.Proveedor(ProveedorID),

    CONSTRAINT FK_ProveedorIngrediente_Ingrediente
        FOREIGN KEY (IngredienteID)
        REFERENCES catalogo.Ingrediente(IngredienteID),

    CONSTRAINT CK_ProveedorIngrediente_PrecioReferencia
        CHECK (PrecioReferencia >= 0),

    CONSTRAINT CK_ProveedorIngrediente_TiempoEntregaDias
        CHECK (TiempoEntregaDias >= 0)
);
GO

/*--------------------------------------------------------------
  2.6  Esquema contabilidad
--------------------------------------------------------------*/
CREATE TABLE contabilidad.CuentaContable
(
    CuentaContableID INT IDENTITY(1,1) NOT NULL,
    CodigoCuenta     NVARCHAR(30) NOT NULL,
    NombreCuenta     NVARCHAR(150) NOT NULL,
    TipoCuenta       NVARCHAR(30) NOT NULL,
    Activa           BIT NOT NULL
        CONSTRAINT DF_CuentaContable_Activa DEFAULT (1),

    CONSTRAINT PK_CuentaContable
        PRIMARY KEY (CuentaContableID),

    CONSTRAINT UQ_CuentaContable_CodigoCuenta
        UNIQUE (CodigoCuenta)
);
GO

CREATE TABLE contabilidad.MovimientoContable
(
    MovimientoContableID BIGINT IDENTITY(1,1) NOT NULL,
    CuentaContableID      INT NOT NULL,
    FechaMovimiento       DATETIME2(0) NOT NULL,
    Descripcion           NVARCHAR(300) NOT NULL,
    TipoMovimiento        NVARCHAR(20) NOT NULL,
    Monto                 DECIMAL(14,2) NOT NULL,
    Referencia            NVARCHAR(100) NULL,

    CONSTRAINT PK_MovimientoContable
        PRIMARY KEY (MovimientoContableID),

    CONSTRAINT FK_MovimientoContable_CuentaContable
        FOREIGN KEY (CuentaContableID)
        REFERENCES contabilidad.CuentaContable(CuentaContableID),

    CONSTRAINT CK_MovimientoContable_Monto
        CHECK (Monto > 0)
);
GO

PRINT N'Dieciocho tablas del modelo base creadas.';
GO


/*==============================================================================
  SECCION 3 - TABLA AUXILIAR DE NUMEROS
  Objeto administrativo. Genera secuencias sin recorrido iterativo, en
  cumplimiento de la disposicion 9.2.8 del Entregable 1, que exige favorecer la
  programacion orientada a conjuntos.
==============================================================================*/
CREATE TABLE dba.Numero
(
    N INT NOT NULL,
    CONSTRAINT PK_Numero PRIMARY KEY (N)
);
GO

INSERT INTO dba.Numero (N)
SELECT TOP (200000)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
FROM sys.all_objects AS a
CROSS JOIN sys.all_objects AS b;
GO

PRINT N'Tabla auxiliar dba.Numero cargada con 200 000 valores.';
GO


/*==============================================================================
  SECCION 4 - CATALOGOS Y DATOS MAESTROS
==============================================================================*/

/*------------------------------------------------------------------------------
  4.1  Catalogos de control con clave asignada
  EstadoPedidoID y TipoMovimientoID no son IDENTITY: sus valores son parte del
  contrato del modelo y se asignan de forma explicita.
------------------------------------------------------------------------------*/
INSERT INTO ventas.EstadoPedido (EstadoPedidoID, NombreEstado)
VALUES (1, N'Pendiente'),
       (2, N'Preparacion'),
       (3, N'Entregado'),
       (4, N'Cancelado');
GO

INSERT INTO inventario.TipoMovimientoInventario (TipoMovimientoID, NombreTipo)
VALUES (1, N'ENTRADA'),
       (2, N'SALIDA'),
       (3, N'AJUSTE');
GO

/*------------------------------------------------------------------------------
  4.2  catalogo.TipoImpuesto
------------------------------------------------------------------------------*/
INSERT INTO catalogo.TipoImpuesto (Nombre, Porcentaje, Activo)
VALUES (N'Impuesto al valor agregado', 13.00, 1),
       (N'Impuesto de servicio',        10.00, 1),
       (N'Exento',                       0.00, 1);
GO

/*------------------------------------------------------------------------------
  4.3  catalogo.Ingrediente
  CostoReferencia es informacion restringida: en 02_Seguridad.sql se excluye de
  los permisos de los roles de consulta.
------------------------------------------------------------------------------*/
INSERT INTO catalogo.Ingrediente (Nombre, UnidadMedida, CostoReferencia, Activo)
VALUES (N'Pan brioche',            N'unidad', 320.0000, 1),
       (N'Pan integral',           N'unidad', 355.0000, 1),
       (N'Carne de res 150 g',     N'unidad', 1250.0000, 1),
       (N'Carne de cerdo 150 g',   N'unidad', 980.0000, 1),
       (N'Pechuga de pollo 150 g', N'unidad', 1120.0000, 1),
       (N'Medallon vegetal 150 g', N'unidad', 1380.0000, 1),
       (N'Queso cheddar',          N'rebanada', 210.0000, 1),
       (N'Queso suizo',            N'rebanada', 245.0000, 1),
       (N'Tocineta',               N'tira',   185.0000, 1),
       (N'Lechuga',                N'g',        2.5000, 1),
       (N'Tomate',                 N'g',        1.8000, 1),
       (N'Cebolla morada',         N'g',        1.4000, 1),
       (N'Pepinillo',              N'g',        3.2000, 1),
       (N'Salsa de la casa',       N'ml',       4.1000, 1),
       (N'Mostaza',                N'ml',       2.2000, 1),
       (N'Salsa de tomate',        N'ml',       1.9000, 1),
       (N'Aros de cebolla',        N'unidad',  95.0000, 1),
       (N'Papa para freir',        N'g',        1.1000, 1),
       (N'Aceite vegetal',         N'ml',       0.9000, 1),
       (N'Sal fina',               N'g',        0.4000, 1);
GO

/*------------------------------------------------------------------------------
  4.4  catalogo.Hamburguesa
------------------------------------------------------------------------------*/
INSERT INTO catalogo.Hamburguesa (Nombre, Descripcion, PrecioBase, Activa)
VALUES (N'Clasica de la casa',   N'Carne de res, queso cheddar, lechuga, tomate y salsa de la casa.', 4200.00, 1),
       (N'Doble tocineta',       N'Doble carne de res, tocineta crocante y queso cheddar.',           6300.00, 1),
       (N'Pollo crocante',       N'Pechuga de pollo empanizada, lechuga y mostaza.',                  4650.00, 1),
       (N'Cerdo ahumado',        N'Carne de cerdo, cebolla morada y salsa de la casa.',               4850.00, 1),
       (N'Vegetariana',          N'Medallon vegetal, queso suizo, tomate y pepinillo.',               5100.00, 1),
       (N'Suiza especial',       N'Carne de res, queso suizo y aros de cebolla.',                     5450.00, 1),
       (N'Criolla',              N'Carne de res, tomate, cebolla morada y salsa de tomate.',          4350.00, 1),
       (N'Doble queso',          N'Doble carne de res con cheddar y suizo.',                          5980.00, 1),
       (N'Ligera integral',      N'Pechuga de pollo en pan integral con lechuga y tomate.',           4700.00, 1),
       (N'Infantil',             N'Porcion reducida de carne de res con queso cheddar.',              2950.00, 1),
       (N'Edicion limitada',     N'Preparacion de temporada. Puede no estar disponible.',             6800.00, 0);
GO

/*------------------------------------------------------------------------------
  4.5  catalogo.RecetaHamburguesa
  Composicion determinista: a cada hamburguesa se le asignan entre cuatro y
  siete ingredientes, sin repetir la combinacion (restringido por
  UQ_RecetaHamburguesa_Hamburguesa_Ingrediente).
------------------------------------------------------------------------------*/
INSERT INTO catalogo.RecetaHamburguesa (HamburguesaID, IngredienteID, CantidadRequerida)
SELECT h.HamburguesaID,
       i.IngredienteID,
       CAST(1 + (ABS(CHECKSUM(h.HamburguesaID * 7919 + i.IngredienteID * 104729)) % 4) AS DECIMAL(12,3))
FROM catalogo.Hamburguesa AS h
INNER JOIN catalogo.Ingrediente AS i
        ON ((h.HamburguesaID * 31 + i.IngredienteID * 17) % 7) < 3
WHERE i.IngredienteID <= 16;
GO

/*------------------------------------------------------------------------------
  4.6  catalogo.HamburguesaImpuesto
  Todo producto activo tributa el impuesto al valor agregado; la infantil se
  registra ademas como exenta de impuesto de servicio.
------------------------------------------------------------------------------*/
INSERT INTO catalogo.HamburguesaImpuesto (HamburguesaID, TipoImpuestoID)
SELECT h.HamburguesaID, 1
FROM catalogo.Hamburguesa AS h;

INSERT INTO catalogo.HamburguesaImpuesto (HamburguesaID, TipoImpuestoID)
SELECT h.HamburguesaID, 2
FROM catalogo.Hamburguesa AS h
WHERE h.PrecioBase >= 4500.00;
GO

/*------------------------------------------------------------------------------
  4.7  rrhh.Departamento y rrhh.Puesto
------------------------------------------------------------------------------*/
INSERT INTO rrhh.Departamento (Nombre, Descripcion)
VALUES (N'Produccion',      N'Preparacion de alimentos y control de cocina.'),
       (N'Servicio',        N'Atencion de clientes en salon y para llevar.'),
       (N'Administracion',  N'Gestion administrativa y financiera.'),
       (N'Compras',         N'Abastecimiento y relacion con proveedores.'),
       (N'Tecnologia',      N'Sistemas de informacion y soporte tecnico.');
GO

INSERT INTO rrhh.Puesto (Nombre, Descripcion)
VALUES (N'Cocinero',                  N'Preparacion de productos del catalogo.'),
       (N'Auxiliar de cocina',        N'Apoyo en preparacion y limpieza.'),
       (N'Cajero',                     N'Registro de pedidos y cobro.'),
       (N'Mesero',                     N'Atencion en salon.'),
       (N'Supervisor de turno',        N'Coordinacion operativa del turno.'),
       (N'Analista administrativo',    N'Procesos administrativos y contables.'),
       (N'Encargado de compras',       N'Gestion de proveedores y pedidos de insumos.'),
       (N'Administrador de base de datos', N'Operacion y custodia de las bases de datos.');
GO

/*------------------------------------------------------------------------------
  4.8  rrhh.Empleado
  Identificacion, FechaNacimiento y Salario son informacion sensible: en
  02_Seguridad.sql se excluyen de los permisos de rol_rrhh_consulta.
  Los datos son sinteticos y no corresponden a personas reales.
------------------------------------------------------------------------------*/
INSERT INTO rrhh.Empleado
    (Identificacion, Nombre, Apellido, FechaNacimiento, Telefono, Correo,
     FechaIngreso, DepartamentoID, PuestoID, Salario, Estado)
SELECT
    RIGHT(N'0' + CAST(100000000 + n.N * 137 AS NVARCHAR(20)), 9),
    CHOOSE(1 + (n.N % 10), N'Ana', N'Bruno', N'Carla', N'Diego', N'Elena',
                            N'Fabio', N'Gabriela', N'Hugo', N'Irene', N'Javier'),
    CHOOSE(1 + ((n.N * 3) % 10), N'Alvarado', N'Brenes', N'Chacon', N'Delgado', N'Espinoza',
                                  N'Fallas', N'Guzman', N'Herrera', N'Jimenez', N'Loria'),
    DATEADD(DAY, -(7300 + (n.N * 97) % 5400), CAST('2026-01-01' AS DATE)),
    N'8' + RIGHT(N'0000000' + CAST((n.N * 613) % 10000000 AS NVARCHAR(10)), 7),
    N'empleado' + CAST(n.N AS NVARCHAR(10)) + N'@ejemplo.local',
    DATEADD(DAY, -((n.N * 53) % 2600), CAST('2026-01-01' AS DATE)),
    1 + (n.N % 5),
    1 + (n.N % 8),
    CAST(450000 + ((n.N * 8117) % 950000) AS DECIMAL(14,2)),
    CASE WHEN n.N % 12 = 0 THEN N'INACTIVO' ELSE N'ACTIVO' END
FROM dba.Numero AS n
WHERE n.N <= 30;
GO

/*------------------------------------------------------------------------------
  4.9  proveedores.Proveedor y proveedores.ProveedorIngrediente
  PrecioReferencia es informacion restringida al perfil de gestion.
------------------------------------------------------------------------------*/
INSERT INTO proveedores.Proveedor
    (IdentificacionFiscal, NombreProveedor, Contacto, Telefono, Correo, Activo)
VALUES (N'3101000001', N'Distribuidora Panaderia del Valle', N'Contacto comercial', N'22001001', N'ventas@panaderiavalle.local', 1),
       (N'3101000002', N'Carnes Selectas del Norte',         N'Contacto comercial', N'22001002', N'pedidos@carnesnorte.local',   1),
       (N'3101000003', N'Lacteos Monteverde',                N'Contacto comercial', N'22001003', N'ventas@lacteosmv.local',      1),
       (N'3101000004', N'Vegetales Frescos Guanacaste',      N'Contacto comercial', N'22001004', N'pedidos@vegetalesgt.local',   1),
       (N'3101000005', N'Abarrotes y Salsas Centrales',      N'Contacto comercial', N'22001005', N'ventas@abarrotescc.local',    1),
       (N'3101000006', N'Congelados Pacifico',               N'Contacto comercial', N'22001006', N'pedidos@congpacifico.local',  1),
       (N'3101000007', N'Aceites Industriales del Sur',      N'Contacto comercial', N'22001007', N'ventas@aceitessur.local',     1),
       (N'3101000008', N'Proveedora Temporal Cerrada',       N'Sin contacto',       NULL,        NULL,                           0);
GO

INSERT INTO proveedores.ProveedorIngrediente
    (ProveedorID, IngredienteID, PrecioReferencia, TiempoEntregaDias)
SELECT p.ProveedorID,
       i.IngredienteID,
       CAST(i.CostoReferencia * (0.85 + ((ABS(CHECKSUM(p.ProveedorID * 8191 + i.IngredienteID * 65537)) % 25) / 100.0)) AS DECIMAL(12,4)),
       CAST(1 + (ABS(CHECKSUM(p.ProveedorID * 131 + i.IngredienteID * 251)) % 7) AS SMALLINT)
FROM proveedores.Proveedor AS p
INNER JOIN catalogo.Ingrediente AS i
        ON ((p.ProveedorID * 13 + i.IngredienteID) % 4) = 0
WHERE p.Activo = 1;
GO

/*------------------------------------------------------------------------------
  4.10  contabilidad.CuentaContable
------------------------------------------------------------------------------*/
INSERT INTO contabilidad.CuentaContable (CodigoCuenta, NombreCuenta, TipoCuenta, Activa)
VALUES (N'1-01-001', N'Caja general',                    N'Activo',     1),
       (N'1-01-002', N'Bancos cuenta corriente',         N'Activo',     1),
       (N'1-02-001', N'Inventario de ingredientes',      N'Activo',     1),
       (N'2-01-001', N'Cuentas por pagar a proveedores', N'Pasivo',     1),
       (N'2-02-001', N'Impuestos por pagar',             N'Pasivo',     1),
       (N'3-01-001', N'Capital social',                  N'Patrimonio', 1),
       (N'4-01-001', N'Ingresos por ventas',             N'Ingreso',    1),
       (N'4-02-001', N'Otros ingresos operativos',       N'Ingreso',    1),
       (N'5-01-001', N'Costo de ventas',                 N'Gasto',      1),
       (N'5-02-001', N'Gastos de personal',              N'Gasto',      1),
       (N'5-03-001', N'Servicios publicos',              N'Gasto',      1),
       (N'5-04-001', N'Cuenta historica cerrada',        N'Gasto',      0);
GO

/*------------------------------------------------------------------------------
  4.11  contabilidad.MovimientoContable
  Registro financiero: en 03_Auditoria.sql toda operacion sobre esta tabla queda
  auditada, y en 02_Seguridad.sql se le deniega DELETE incluso al perfil de
  gestion, para preservar la trazabilidad.
------------------------------------------------------------------------------*/
INSERT INTO contabilidad.MovimientoContable
    (CuentaContableID, FechaMovimiento, Descripcion, TipoMovimiento, Monto, Referencia)
SELECT 1 + (n.N % 11),
       DATEADD(HOUR, -(n.N * 7), CAST('2026-08-29T00:00:00' AS DATETIME2(0))),
       N'Asiento contable de operacion numero ' + CAST(n.N AS NVARCHAR(10)),
       CASE WHEN n.N % 2 = 0 THEN N'DEBITO' ELSE N'CREDITO' END,
       CAST(10000 + ((n.N * 3571) % 990000) AS DECIMAL(14,2)),
       N'REF-' + RIGHT(N'000000' + CAST(n.N AS NVARCHAR(10)), 6)
FROM dba.Numero AS n
WHERE n.N <= 500;
GO

PRINT N'Catalogos y datos maestros cargados.';
GO


/*==============================================================================
  SECCION 5 - VOLUMEN TRANSACCIONAL REPRODUCIBLE

  Volumenes objetivo:
      ventas.Cliente                    1 500
      ventas.Pedido                    30 000
      ventas.PedidoDetalle           ~ 75 000
      inventario.MovimientoInventario  60 000

  Dimensionamiento: el enunciado pide un volumen mayor en las tablas
  transaccionales para poder demostrar permisos, respaldos, restauracion y
  rendimiento. Se eligieron estos valores porque producen aproximadamente
  166 000 filas transaccionales -suficientes para que el caso de rendimiento de
  07_Rendimiento.sql muestre una diferencia medible entre recorrido completo y
  busqueda por indice- consumiendo bastante menos que los 128 MB de registro
  preasignados, ya que la base opera en modelo FULL y la carga se registra por
  completo.

  Determinismo: todos los valores derivan de ABS(CHECKSUM(<expresion del numero
  de fila>)), que es una funcion pura del numero de fila. No se emplea NEWID()
  ni RAND(). Dos ejecuciones sobre bases limpias producen datos identicos.
==============================================================================*/

/*------------------------------------------------------------------------------
  5.1  ventas.Cliente
------------------------------------------------------------------------------*/
INSERT INTO ventas.Cliente (Nombre, Apellido, Telefono, Correo, Direccion, Activo)
SELECT
    CHOOSE(1 + (n.N % 12), N'Adriana', N'Bernal', N'Camila', N'Daniel', N'Emilia', N'Federico',
                            N'Gustavo', N'Helena', N'Ignacio', N'Julieta', N'Karla', N'Leonardo'),
    CHOOSE(1 + ((n.N * 5) % 12), N'Aguilar', N'Barrantes', N'Cascante', N'Duarte', N'Esquivel', N'Fonseca',
                                  N'Gomez', N'Hidalgo', N'Induni', N'Jaen', N'Kopper', N'Leiva'),
    N'7' + RIGHT(N'0000000' + CAST((n.N * 977) % 10000000 AS NVARCHAR(10)), 7),
    N'cliente' + CAST(n.N AS NVARCHAR(10)) + N'@ejemplo.local',
    N'Direccion de referencia numero ' + CAST(n.N AS NVARCHAR(10)) + N', Tilaran, Guanacaste',
    CASE WHEN n.N % 20 = 0 THEN 0 ELSE 1 END
FROM dba.Numero AS n
WHERE n.N <= 1500;
GO

/*------------------------------------------------------------------------------
  5.2  ventas.Pedido
  Los importes se insertan en cero y se calculan en 5.4 a partir del detalle,
  de modo que la suma de las lineas coincida siempre con el encabezado. Los
  CHECK del modelo admiten el valor cero, por lo que el estado intermedio es
  valido.
  Las fechas se distribuyen sobre los ultimos 24 meses para que el caso de
  rendimiento por rango de fechas tenga sentido.
------------------------------------------------------------------------------*/
INSERT INTO ventas.Pedido (ClienteID, FechaPedido, EstadoPedidoID, Subtotal, Impuesto, Total)
SELECT
    1 + (ABS(CHECKSUM(n.N * 2654435761)) % 1500),
    DATEADD(MINUTE,
            -(ABS(CHECKSUM(n.N * 40503)) % 1051200),   -- 1 051 200 minutos = 24 meses
            CAST('2026-08-29T00:00:00' AS DATETIME2(0))),
    CASE
        WHEN n.N % 25 = 0 THEN 4                        -- Cancelado
        WHEN n.N % 11 = 0 THEN 1                        -- Pendiente
        WHEN n.N %  7 = 0 THEN 2                        -- Preparacion
        ELSE 3                                          -- Entregado
    END,
    0, 0, 0
FROM dba.Numero AS n
WHERE n.N <= 30000;
GO

PRINT N'ventas.Pedido cargado.';
GO

/*------------------------------------------------------------------------------
  5.3  ventas.PedidoDetalle
  Entre una y cuatro lineas por pedido, siempre sobre hamburguesas activas.
------------------------------------------------------------------------------*/
INSERT INTO ventas.PedidoDetalle (PedidoID, HamburguesaID, Cantidad, PrecioUnitario, SubtotalLinea)
SELECT
    p.PedidoID,
    h.HamburguesaID,
    CAST(1 + (ABS(CHECKSUM(p.PedidoID * 7907 + l.N * 6121)) % 3) AS SMALLINT),
    h.PrecioBase,
    CAST((1 + (ABS(CHECKSUM(p.PedidoID * 7907 + l.N * 6121)) % 3)) * h.PrecioBase AS DECIMAL(14,2))
FROM ventas.Pedido AS p
CROSS JOIN dba.Numero AS l
INNER JOIN catalogo.Hamburguesa AS h
        ON h.HamburguesaID = 1 + (ABS(CHECKSUM(p.PedidoID * 15485863 + l.N * 32452843)) % 10)
WHERE l.N <= 4
  AND l.N <= 1 + (ABS(CHECKSUM(p.PedidoID * 99991)) % 4)
  AND h.Activa = 1;
GO

PRINT N'ventas.PedidoDetalle cargado.';
GO

/*------------------------------------------------------------------------------
  5.4  Consolidacion de importes del encabezado
  Impuesto al valor agregado del 13 %, conforme al catalogo de la seccion 4.2.
------------------------------------------------------------------------------*/
UPDATE p
SET p.Subtotal = agg.Subtotal,
    p.Impuesto = CAST(agg.Subtotal * 0.13 AS DECIMAL(14,2)),
    p.Total    = agg.Subtotal + CAST(agg.Subtotal * 0.13 AS DECIMAL(14,2))
FROM ventas.Pedido AS p
INNER JOIN (
    SELECT pd.PedidoID,
           Subtotal = SUM(pd.SubtotalLinea)
    FROM ventas.PedidoDetalle AS pd
    GROUP BY pd.PedidoID
) AS agg
        ON agg.PedidoID = p.PedidoID;
GO

/*------------------------------------------------------------------------------
  5.5  inventario.ExistenciaIngrediente
  Una fila por ingrediente. StockMaximo se calcula siempre por encima de
  StockMinimo para satisfacer CK_ExistenciaIngrediente_StockMaximo.
------------------------------------------------------------------------------*/
INSERT INTO inventario.ExistenciaIngrediente
    (IngredienteID, StockActual, StockMinimo, StockMaximo, FechaUltimaActualizacion)
SELECT
    i.IngredienteID,
    CAST(200 + (ABS(CHECKSUM(i.IngredienteID * 5471)) % 1800) AS DECIMAL(14,3)),
    CAST(100 + (ABS(CHECKSUM(i.IngredienteID * 3079)) % 150)  AS DECIMAL(14,3)),
    CAST(2500 + (ABS(CHECKSUM(i.IngredienteID * 9767)) % 1500) AS DECIMAL(14,3)),
    CAST('2026-08-29T00:00:00' AS DATETIME2(0))
FROM catalogo.Ingrediente AS i;
GO

/*------------------------------------------------------------------------------
  5.6  inventario.MovimientoInventario
  Historico de movimientos. CK_MovimientoInventario_Cantidad exige cantidad
  positiva: el sentido del movimiento lo expresa TipoMovimientoID y no el signo.
  Esta es la tabla sobre la que 05_Restore_Recovery.sql simula el incidente
  logico, por lo que conviene que tenga volumen suficiente.
------------------------------------------------------------------------------*/
INSERT INTO inventario.MovimientoInventario
    (IngredienteID, TipoMovimientoID, FechaMovimiento, Cantidad, CostoUnitario, Observacion)
SELECT
    1 + (ABS(CHECKSUM(n.N * 15485867)) % 20),
    CASE
        WHEN n.N % 10 = 0 THEN 3                        -- AJUSTE
        WHEN n.N %  3 = 0 THEN 1                        -- ENTRADA
        ELSE 2                                          -- SALIDA
    END,
    DATEADD(MINUTE,
            -(ABS(CHECKSUM(n.N * 25165843)) % 1051200),
            CAST('2026-08-29T00:00:00' AS DATETIME2(0))),
    CAST(1 + (ABS(CHECKSUM(n.N * 32452867)) % 250) AS DECIMAL(14,3)),
    CASE WHEN n.N % 3 = 0
         THEN CAST(1 + (ABS(CHECKSUM(n.N * 49979693)) % 1400) AS DECIMAL(12,4))
         ELSE NULL
    END,
    CASE
        WHEN n.N % 10 = 0 THEN N'Ajuste por conteo fisico'
        WHEN n.N %  3 = 0 THEN N'Ingreso por compra a proveedor'
        ELSE N'Consumo de produccion'
    END
FROM dba.Numero AS n
WHERE n.N <= 60000;
GO

PRINT N'inventario.MovimientoInventario cargado.';
GO


/*==============================================================================
  SECCION 6 - VERIFICACION Y EVIDENCIA (EV-01-01)
  Conservar la salida completa de los seis conjuntos con su fecha y hora.
==============================================================================*/

-- 6.1  Inventario de objetos por esquema
SELECT
    [Momento]  = SYSDATETIME(),
    [Esquema]  = s.name,
    [Tablas]   = COUNT(t.object_id)
FROM sys.schemas AS s
LEFT JOIN sys.tables AS t
       ON t.schema_id = s.schema_id
WHERE s.name IN (N'catalogo', N'ventas', N'inventario', N'rrhh', N'proveedores', N'contabilidad', N'dba', N'dbo')
GROUP BY s.name
ORDER BY s.name;
GO

-- 6.2  Comprobacion de la regla: ninguna tabla de negocio en dbo
SELECT
    [Regla]              = N'Sin tablas de negocio en dbo',
    [TablasEnDbo]        = COUNT(*),
    [Resultado]          = CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = N'dbo';
GO

-- 6.3  Conteo de filas por tabla
SELECT
    [Tabla] = QUOTENAME(s.name) + N'.' + QUOTENAME(t.name),
    [Filas] = SUM(CASE WHEN p.index_id IN (0,1) THEN p.rows ELSE 0 END)
FROM sys.tables AS t
INNER JOIN sys.schemas    AS s ON s.schema_id = t.schema_id
INNER JOIN sys.partitions AS p ON p.object_id = t.object_id
WHERE s.name <> N'dba'
GROUP BY s.name, t.name
ORDER BY s.name, t.name;
GO

-- 6.4  Restricciones implementadas por tipo
SELECT
    [TipoRestriccion] = N'PRIMARY KEY',  [Cantidad] = COUNT(*) FROM sys.key_constraints WHERE type = 'PK'
UNION ALL
SELECT N'UNIQUE',      COUNT(*) FROM sys.key_constraints   WHERE type = 'UQ'
UNION ALL
SELECT N'FOREIGN KEY', COUNT(*) FROM sys.foreign_keys
UNION ALL
SELECT N'CHECK',       COUNT(*) FROM sys.check_constraints
UNION ALL
SELECT N'DEFAULT',     COUNT(*) FROM sys.default_constraints;
GO

-- 6.5  Integridad de las claves foraneas y de las restricciones CHECK.
-- is_not_trusted = 1 indicaria una restriccion que el motor no garantiza.
SELECT
    [Objeto]        = N'Claves foraneas',
    [NoConfiables]  = SUM(CASE WHEN is_not_trusted = 1 THEN 1 ELSE 0 END),
    [Deshabilitadas]= SUM(CASE WHEN is_disabled   = 1 THEN 1 ELSE 0 END)
FROM sys.foreign_keys
UNION ALL
SELECT N'Restricciones CHECK',
       SUM(CASE WHEN is_not_trusted = 1 THEN 1 ELSE 0 END),
       SUM(CASE WHEN is_disabled   = 1 THEN 1 ELSE 0 END)
FROM sys.check_constraints;
GO

-- 6.6  Coherencia funcional de los datos cargados
SELECT
    [Prueba]    = N'Total del pedido igual a subtotal mas impuesto',
    [Incumplen] = COUNT(*),
    [Resultado] = CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM ventas.Pedido AS p
WHERE p.Total <> p.Subtotal + p.Impuesto
UNION ALL
SELECT N'Subtotal del encabezado igual a la suma de sus lineas',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM ventas.Pedido AS p
INNER JOIN (
    SELECT pd.PedidoID, S = SUM(pd.SubtotalLinea)
    FROM ventas.PedidoDetalle AS pd
    GROUP BY pd.PedidoID
) AS a ON a.PedidoID = p.PedidoID
WHERE p.Subtotal <> a.S
UNION ALL
SELECT N'Pedidos sin ninguna linea de detalle',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'REVISAR' END
FROM ventas.Pedido AS p
WHERE NOT EXISTS (SELECT 1 FROM ventas.PedidoDetalle AS pd WHERE pd.PedidoID = p.PedidoID)
UNION ALL
SELECT N'Existencias registradas para todos los ingredientes',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM catalogo.Ingrediente AS i
WHERE NOT EXISTS (SELECT 1 FROM inventario.ExistenciaIngrediente AS e WHERE e.IngredienteID = i.IngredienteID);
GO

-- 6.7  Consumo de espacio y de registro tras la carga.
-- Comparar contra la linea base capturada en EV-00-02. En modelo FULL, el
-- porcentaje de uso del log solo desciende tras un respaldo de registro.
SELECT
    [Archivo]     = df.name,
    [Tipo]        = df.type_desc,
    [TamanoMB]    = CAST(df.size / 128.0 AS DECIMAL(12,2)),
    [UsadoMB]     = CAST(FILEPROPERTY(df.name, 'SpaceUsed') / 128.0 AS DECIMAL(12,2)),
    [LibreMB]     = CAST((df.size - FILEPROPERTY(df.name, 'SpaceUsed')) / 128.0 AS DECIMAL(12,2)),
    [UsoPct]      = CAST(100.0 * FILEPROPERTY(df.name, 'SpaceUsed') / NULLIF(df.size, 0) AS DECIMAL(5,2))
FROM sys.database_files AS df;

SELECT
    [LogTotalMB]     = CAST(total_log_size_in_bytes / 1048576.0 AS DECIMAL(12,2)),
    [LogUsadoMB]     = CAST(used_log_space_in_bytes  / 1048576.0 AS DECIMAL(12,2)),
    [LogUsadoPct]    = CAST(used_log_space_in_percent AS DECIMAL(5,2)),
    [RazonEsperaLog] = (SELECT log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME());
GO

PRINT N'== 01_Modelo.sql finalizado. Conservar la salida como evidencia EV-01-01. ==';
PRINT N'== Siguiente paso: 02_Seguridad.sql ==';
GO
