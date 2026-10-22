/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        07_Rendimiento.sql
  Proposito:     Medir una consulta representativa antes y despues de crear un
                 indice justificado, con evidencia numerica de la diferencia
                 (seccion 7.6 del entregable, caso de rendimiento).

  Controles del Entregable 1 que implementa:
                 DBA-MON-01  Interpretacion de metricas, no solo su captura.
                 DBA-COD-01  Consulta con columnas declaradas de forma explicita.

  Precondiciones:Scripts 00 a 06 ejecutados. El modelo NO debe tener todavia el
                 indice que este script crea: 01_Modelo.sql lo omitio de forma
                 deliberada para que la medicion previa sea real.
  Orden:         Script 07. Antes de 09_Validacion.sql.
  Destructivo:   No sobre los datos. Crea un indice no agrupado.
  Reejecutable:  SI. La SECCION 1 elimina el indice para poder repetir la
                 medicion previa en igualdad de condiciones.
  Resultado
  esperado:      Medicion antes, indice creado, medicion despues y tabla
                 comparativa con el porcentaje de reduccion. Guardar como
                 EV-07-01 a EV-07-03.

  ---------------------------------------------------------------------------
  EL CASO
  ---------------------------------------------------------------------------
  Pregunta de negocio
    Cuanto se facturo y cuantos pedidos entregados hubo en un trimestre
    determinado. Es la consulta que alimenta el cierre comercial y se ejecuta
    de forma recurrente sobre un rango de fechas.

  Por que esta consulta y no otra
    Filtra ventas.Pedido por un rango de FechaPedido y por estado, y agrega
    importes. Sobre 30 000 pedidos, sin indice el motor debe recorrer el indice
    agrupado completo, porque la clave primaria es PedidoID y no acompana al
    predicado de fecha. Es el caso tipico donde un indice bien elegido cambia el
    plan de recorrido completo a busqueda por rango.

  Composicion del indice y por que en ese orden
    Clave: (EstadoPedidoID, FechaPedido).
      EstadoPedidoID va primero por ser un predicado de igualdad, que permite
      posicionarse de forma exacta; FechaPedido va segundo por ser un predicado
      de rango, que solo puede aprovechar el orden una vez fijada la igualdad.
      El orden inverso obligaria a recorrer todas las fechas de todos los
      estados.
    Incluidas: (Subtotal, Impuesto, Total).
      Son las columnas que la consulta agrega. Al incluirlas, el indice cubre la
      consulta por completo y el motor no necesita volver al indice agrupado a
      buscar cada fila, que es donde se concentraba el costo.

  Limitaciones del entorno de medicion
    La instancia es Express, con el grupo de memoria intermedia limitado a
    1 410 MB, y la medicion se realiza en un equipo de escritorio con otras
    cargas. Los valores absolutos de tiempo no son extrapolables a produccion.
    Las lecturas logicas si lo son: no dependen de la memoria disponible ni de
    la carga del equipo, y por eso son la metrica principal de la comparacion.
==============================================================================*/

SET NOCOUNT ON;
GO

USE DBSuperHamburguesas;
GO

/*==============================================================================
  SECCION 0 - TABLA DE MEDICIONES
==============================================================================*/
DROP TABLE IF EXISTS dba.MedicionRendimiento;
CREATE TABLE dba.MedicionRendimiento
(
    MedicionID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MedicionRendimiento PRIMARY KEY,
    Momento        DATETIME2(0) NOT NULL CONSTRAINT DF_MedicionRendimiento_Momento DEFAULT (SYSDATETIME()),
    Escenario      NVARCHAR(20) NOT NULL,
    LecturasLogicas BIGINT NOT NULL,
    TiempoCPU_ms   BIGINT NOT NULL,
    TiempoTotal_ms BIGINT NOT NULL,
    Ejecuciones    INT NOT NULL,
    CONSTRAINT CK_MedicionRendimiento_Escenario CHECK (Escenario IN (N'ANTES', N'DESPUES'))
);
GO

CREATE OR ALTER PROCEDURE dba.usp_CasoRendimiento
AS
BEGIN
    SET NOCOUNT ON;
    -- Consulta representativa: cierre comercial de un trimestre.
    -- Columnas declaradas de forma explicita, conforme a la disposicion 9.2.2.
    SELECT
        Anio         = YEAR(p.FechaPedido),
        Mes          = MONTH(p.FechaPedido),
        Pedidos      = COUNT_BIG(p.PedidoID),
        Subtotal     = SUM(p.Subtotal),
        Impuesto     = SUM(p.Impuesto),
        Total        = SUM(p.Total)
    FROM ventas.Pedido AS p
    WHERE p.EstadoPedidoID = 3                                   -- Entregado
      AND p.FechaPedido >= DATEFROMPARTS(2026, 4, 1)
      AND p.FechaPedido <  DATEFROMPARTS(2026, 7, 1)
    GROUP BY YEAR(p.FechaPedido), MONTH(p.FechaPedido)
    ORDER BY Anio, Mes;
END;
GO

CREATE OR ALTER PROCEDURE dba.usp_MedirCaso
    @pEscenario NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @obj INT = OBJECT_ID(N'dba.usp_CasoRendimiento');

    /* Se limpia la cache de plan del procedimiento para que la comparacion sea
       justa: se mide la ejecucion, no la reutilizacion de un plan previo.

       DBCC FREEPROCCACHE admite un plan_handle, un sql_handle o el nombre de un
       grupo de recursos, NUNCA un object_id: pasarle el identificador del objeto
       produce el error 2560 "Parameter 1 is incorrect for this DBCC statement". */
    DECLARE @ph VARBINARY(64);
    DECLARE @vueltas TINYINT = 0;

    WHILE @vueltas < 20
    BEGIN
        SET @ph = (SELECT TOP (1) ps.plan_handle
                     FROM sys.dm_exec_procedure_stats AS ps
                    WHERE ps.object_id = @obj AND ps.database_id = DB_ID());
        IF @ph IS NULL BREAK;
        DBCC FREEPROCCACHE (@ph) WITH NO_INFOMSGS;
        SET @vueltas += 1;
    END

    /* La medicion se toma como diferencia de los contadores de la PETICION en
       curso, sys.dm_exec_requests, no de sys.dm_exec_sessions.

       Motivo: los contadores de la sesion solo se consolidan cuando la peticion
       termina, de modo que leerlos dentro de la misma ejecucion devuelve el
       mismo valor antes y despues y la diferencia sale en cero. Los de
       sys.dm_exec_requests se actualizan mientras la peticion corre, que es
       exactamente lo que hay que medir. Tampoco se usa
       sys.dm_exec_procedure_stats, porque queda vacia justo despues de liberar
       el plan de la cache. */
    DECLARE @lecturas0 BIGINT, @cpu0 BIGINT, @inicio DATETIME2(3) = SYSDATETIME();

    SELECT @lecturas0 = r.logical_reads, @cpu0 = r.cpu_time
      FROM sys.dm_exec_requests AS r
     WHERE r.session_id = @@SPID;

    EXEC dba.usp_CasoRendimiento;

    DECLARE @lecturas BIGINT, @cpu BIGINT, @total BIGINT;

    SELECT @lecturas = r.logical_reads - @lecturas0,
           @cpu      = r.cpu_time      - @cpu0
      FROM sys.dm_exec_requests AS r
     WHERE r.session_id = @@SPID;

    /* Red de seguridad: si por cualquier motivo la peticion no fuera visible en
       la vista, la medicion quedaria nula. Se registra en cero de forma
       explicita en lugar de fallar la insercion. */
    SET @lecturas = ISNULL(@lecturas, 0);
    SET @cpu      = ISNULL(@cpu, 0);

    SET @total = DATEDIFF(MILLISECOND, @inicio, SYSDATETIME());

    INSERT INTO dba.MedicionRendimiento
        (Escenario, LecturasLogicas, TiempoCPU_ms, TiempoTotal_ms, Ejecuciones)
    VALUES (@pEscenario, @lecturas, @cpu, @total, 1);
END;
GO


/*==============================================================================
  SECCION 1 - MEDICION ANTES (EV-07-01)
  Se elimina el indice si existiera, para que la medicion previa sea real y el
  script pueda repetirse en igualdad de condiciones.
==============================================================================*/
DROP INDEX IF EXISTS IX_Pedido_EstadoFecha ON ventas.Pedido;
GO

PRINT N'--- MEDICION ANTES: ejecute con el plan de ejecucion real activado (Ctrl+M) ---';
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO
EXEC dba.usp_CasoRendimiento;
GO
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

EXEC dba.usp_MedirCaso @pEscenario = N'ANTES';
GO

-- Plan y operador de recorrido utilizados antes del indice
SELECT
    [Escenario]      = N'ANTES',
    [Objeto]         = N'ventas.Pedido',
    [FilasTotales]   = (SELECT SUM(p.rows) FROM sys.partitions AS p
                        WHERE p.object_id = OBJECT_ID(N'ventas.Pedido') AND p.index_id IN (0,1)),
    [IndicesNoAgrup] = (SELECT COUNT(*) FROM sys.indexes
                        WHERE object_id = OBJECT_ID(N'ventas.Pedido') AND type_desc = N'NONCLUSTERED'),
    [Interpretacion] = N'Sin indice no agrupado, el predicado de fecha obliga a recorrer el indice agrupado completo.';
GO


/*==============================================================================
  SECCION 2 - CREACION DEL INDICE JUSTIFICADO
==============================================================================*/
CREATE NONCLUSTERED INDEX IX_Pedido_EstadoFecha
    ON ventas.Pedido (EstadoPedidoID, FechaPedido)
    INCLUDE (Subtotal, Impuesto, Total);
GO

PRINT N'Indice IX_Pedido_EstadoFecha creado: clave (EstadoPedidoID, FechaPedido), incluidas (Subtotal, Impuesto, Total).';
GO

-- Se actualizan las estadisticas para que el optimizador disponga de la
-- distribucion real del nuevo indice.
UPDATE STATISTICS ventas.Pedido IX_Pedido_EstadoFecha WITH FULLSCAN;
GO


/*==============================================================================
  SECCION 3 - MEDICION DESPUES (EV-07-02)
==============================================================================*/
PRINT N'--- MEDICION DESPUES ---';
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO
EXEC dba.usp_CasoRendimiento;
GO
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

EXEC dba.usp_MedirCaso @pEscenario = N'DESPUES';
GO


/*==============================================================================
  SECCION 4 - COMPARACION (EV-07-03)
==============================================================================*/
;WITH A AS (SELECT TOP (1) * FROM dba.MedicionRendimiento WHERE Escenario = N'ANTES'   ORDER BY MedicionID DESC),
      D AS (SELECT TOP (1) * FROM dba.MedicionRendimiento WHERE Escenario = N'DESPUES' ORDER BY MedicionID DESC)
SELECT
    [Metrica]        = N'Lecturas logicas',
    [Antes]          = A.LecturasLogicas,
    [Despues]        = D.LecturasLogicas,
    [Diferencia]     = A.LecturasLogicas - D.LecturasLogicas,
    [ReduccionPct]   = CAST(100.0 * (A.LecturasLogicas - D.LecturasLogicas) / NULLIF(A.LecturasLogicas,0) AS DECIMAL(6,2)),
    [Comentario]     = N'Metrica principal: no depende de la memoria ni de la carga del equipo.'
FROM A CROSS JOIN D
UNION ALL
SELECT N'Tiempo de CPU (ms)', A.TiempoCPU_ms, D.TiempoCPU_ms,
       A.TiempoCPU_ms - D.TiempoCPU_ms,
       CAST(100.0 * (A.TiempoCPU_ms - D.TiempoCPU_ms) / NULLIF(A.TiempoCPU_ms,0) AS DECIMAL(6,2)),
       N'Sensible a la carga del equipo.'
FROM A CROSS JOIN D
UNION ALL
SELECT N'Tiempo transcurrido (ms)', A.TiempoTotal_ms, D.TiempoTotal_ms,
       A.TiempoTotal_ms - D.TiempoTotal_ms,
       CAST(100.0 * (A.TiempoTotal_ms - D.TiempoTotal_ms) / NULLIF(A.TiempoTotal_ms,0) AS DECIMAL(6,2)),
       N'Sensible a la carga del equipo y a la memoria disponible.'
FROM A CROSS JOIN D;
GO

-- Uso real del indice tras la medicion
SELECT
    [Indice]        = i.name,
    [Busquedas]     = ISNULL(us.user_seeks, 0),
    [Recorridos]    = ISNULL(us.user_scans, 0),
    [Busquedasclave]= ISNULL(us.user_lookups, 0),
    [Escrituras]    = ISNULL(us.user_updates, 0),
    [Interpretacion]= CASE WHEN ISNULL(us.user_seeks,0) > 0
                           THEN N'El optimizador eligio busqueda por rango sobre el indice: el indice se usa.'
                           ELSE N'Sin busquedas registradas: revisar si el plan lo utiliza.' END
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS us
       ON us.object_id = i.object_id AND us.index_id = i.index_id AND us.database_id = DB_ID()
WHERE i.object_id = OBJECT_ID(N'ventas.Pedido') AND i.name = N'IX_Pedido_EstadoFecha';
GO

-- Espacio que ocupa el indice: todo indice tiene un costo
SELECT
    [Indice]         = i.name,
    [EspacioKB]      = SUM(ps.used_page_count) * 8,
    [Filas]          = SUM(ps.row_count),
    [Interpretacion] = N'Costo del indice: espacio en disco y mantenimiento en cada escritura sobre ventas.Pedido.'
FROM sys.dm_db_partition_stats AS ps
INNER JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.object_id = OBJECT_ID(N'ventas.Pedido') AND i.name = N'IX_Pedido_EstadoFecha'
GROUP BY i.name;
GO

PRINT N'== 07_Rendimiento.sql finalizado. Conservar las salidas y los planes como EV-07-01 a EV-07-03. ==';
PRINT N'== IMPORTANTE: capturar tambien los planes de ejecucion antes y despues (Ctrl+M en SSMS). ==';
PRINT N'== Siguiente paso: 09_Validacion.sql ==';
GO
