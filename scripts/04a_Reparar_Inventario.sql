/*==============================================================================
  PROYECTO 2 - ENTREGABLE 2 | TIIT3175.2 BASES DE DATOS III
  Script:        04a_Reparar_Inventario.sql
  Proposito:     Devolver inventario.ExistenciaIngrediente a su estado original
                 despues de que el incidente logico de 04_Backup.sql se ejecutara
                 sin que existiera la cadena de respaldo.

  Contexto:      En la corrida del 22 de septiembre de 2026, 04_Backup.sql fallo
                 al escribir los respaldos porque la ruta se construyo sin el
                 separador final. El script continuo y la SECCION 8 aplico el
                 incidente deliberado: StockActual quedo en cero en todas las
                 filas, sin respaldo del cual revertirlo.

  Como se repara:El sembrado original de 01_Modelo.sql es determinista: StockActual
                 se calcula a partir del IngredienteID. Se recalcula con la misma
                 expresion, de modo que la tabla vuelve exactamente al valor con
                 el que se cargo. No se toca ninguna otra columna ni tabla.

  Precondiciones:1) 01_Modelo.sql ejecutado con exito en su momento.
                 2) La estructura de la tabla no fue modificada.
  Orden:         Correr UNA VEZ, antes de volver a ejecutar 04_Backup.sql.
  Destructivo:   Sobrescribe StockActual y FechaUltimaActualizacion. Es el efecto
                 buscado: restituir el valor original.
  Reejecutable:  SI. El resultado es idempotente.
==============================================================================*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

USE DBSuperHamburguesas;
GO

IF DB_NAME() <> N'DBSuperHamburguesas'
BEGIN
    RAISERROR(N'Este script debe ejecutarse sobre DBSuperHamburguesas.', 16, 1); RETURN;
END
GO


/*==============================================================================
  SECCION 1 - ESTADO ANTES DE LA REPARACION
==============================================================================*/
SELECT
    [Momento]        = SYSDATETIME(),
    [Etapa]          = N'Antes de reparar',
    [Ingredientes]   = COUNT(*),
    [StockTotal]     = SUM(StockActual),
    [FilasEnCero]    = SUM(CASE WHEN StockActual = 0 THEN 1 ELSE 0 END)
FROM inventario.ExistenciaIngrediente;
GO


/*==============================================================================
  SECCION 2 - REPARACION
  Misma expresion del sembrado original de 01_Modelo.sql, seccion 5.5.
==============================================================================*/
BEGIN TRANSACTION;

UPDATE e
   SET e.StockActual              = CAST(200 + (ABS(CHECKSUM(e.IngredienteID * 5471)) % 1800) AS DECIMAL(14,3)),
       e.FechaUltimaActualizacion = CAST('2026-08-29T00:00:00' AS DATETIME2(0))
  FROM inventario.ExistenciaIngrediente AS e;

DECLARE @filas INT = @@ROWCOUNT;

/* Comprobacion dentro de la transaccion: ninguna fila puede quedar fuera de los
   limites declarados por las restricciones de la tabla. */
IF EXISTS (SELECT 1 FROM inventario.ExistenciaIngrediente WHERE StockActual < 0)
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR(N'La reparacion produjo existencias negativas. Se revirtio por completo.', 16, 1);
    RETURN;
END

COMMIT TRANSACTION;
PRINT N'Reparacion aplicada sobre ' + CAST(@filas AS NVARCHAR(10)) + N' filas.';
GO


/*==============================================================================
  SECCION 3 - ESTADO DESPUES DE LA REPARACION (EV-04A-01)
==============================================================================*/
SELECT
    [Momento]        = SYSDATETIME(),
    [Etapa]          = N'Despues de reparar',
    [Ingredientes]   = COUNT(*),
    [StockTotal]     = SUM(StockActual),
    [StockMinimoObs] = MIN(StockActual),
    [StockMaximoObs] = MAX(StockActual),
    [FilasEnCero]    = SUM(CASE WHEN StockActual = 0 THEN 1 ELSE 0 END),
    [Resultado]      = CASE WHEN SUM(CASE WHEN StockActual = 0 THEN 1 ELSE 0 END) = 0
                            THEN N'CUMPLE' ELSE N'NO CUMPLE' END
FROM inventario.ExistenciaIngrediente;
GO

/* Contraste contra la evidencia capturada por 04_Backup.sql antes del incidente.
   Si la tabla de evidencia todavia existe, el total debe coincidir con la etapa
   "01 Estado inicial". */
IF OBJECT_ID(N'dba.EvidenciaInventario', N'U') IS NOT NULL
BEGIN
    SELECT
        [Etapa registrada] = ev.Etapa,
        [StockTotal]       = ev.StockTotal,
        [StockActualHoy]   = (SELECT SUM(StockActual) FROM inventario.ExistenciaIngrediente),
        [Coincide]         = CASE WHEN ev.StockTotal = (SELECT SUM(StockActual) FROM inventario.ExistenciaIngrediente)
                                  THEN N'SI' ELSE N'NO' END
    FROM dba.EvidenciaInventario AS ev
    WHERE ev.Etapa = N'01 Estado inicial';
END
GO

PRINT N'== 04a_Reparar_Inventario.sql finalizado. Conservar la salida como EV-04A-01. ==';
PRINT N'== Siguiente paso: volver a ejecutar 04_Backup.sql completo. ==';
GO
