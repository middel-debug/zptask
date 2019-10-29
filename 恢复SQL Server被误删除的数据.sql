--建表
CREATE TABLE testdelete
    (
      id INT IDENTITY(1, 1)
             NOT NULL
             PRIMARY KEY ,
      NAME VARCHAR(200) ,
      dt DATETIME
    )


--插入数据
INSERT  [dbo].[testdelete]
        ( [NAME], [dt] )
VALUES  ( 'cc', -- NAME - varchar(200)
          '2015-07-04 07:06:40'  -- dt - datetime
          )




SELECT  *  FROM    [dbo].[testdelete]


--删除数据
DELETE  FROM [dbo].[testdelete]



----删除数据之后对数据库进行日志备份
DECLARE @CurrentTime VARCHAR(50) ,
    @FileName VARCHAR(200)
SET @CurrentTime = REPLACE(REPLACE(REPLACE(CONVERT(VARCHAR, GETDATE(), 120),
                                           '-', '_'), ' ', '_'), ':', '')  
SET @FileName = 'D:\sss_logBackup_' + @CurrentTime + '.bak'
BACKUP LOG  [sss]
TO DISK=@FileName WITH FORMAT 



--存储过程依然保持着两种调用方式
EXEC Recover_Deleted_Data_BylogBackup_Proc 'sss','dbo.testdelete',N'D:\sss_logBackup_2015_07_04_150756.BAK'
GO


EXEC Recover_Deleted_Data_BylogBackup_Proc 'sss','dbo.testdelete',N'D:\sss_logBackup_2015_07_04_150756.BAK','2012-06-01','2016-06-30'
GO


------------存储过程
CREATE PROCEDURE Recover_Deleted_Data_BylogBackup_Proc
    @Database_Name NVARCHAR(MAX) ,
    @SchemaName_n_TableName NVARCHAR(MAX) ,
    @Backuppath NVARCHAR(2000),
    @Date_From DATETIME = '1900/01/01' ,
    @Date_To DATETIME = '9999/12/31' 
   
AS
    DECLARE @RowLogContents VARBINARY(8000)
    DECLARE @TransactionID NVARCHAR(MAX)
    DECLARE @AllocUnitID BIGINT
    DECLARE @AllocUnitName NVARCHAR(MAX)
    DECLARE @SQL NVARCHAR(MAX)
    DECLARE @Compatibility_Level INT

    IF ( @Backuppath IS NULL
         OR @Backuppath = ''
       )
        BEGIN
            RAISERROR('The parameter @Backuppath can not be null!',16,1)
            RETURN
        END


 
    SELECT  @Compatibility_Level = dtb.compatibility_level
    FROM    master.sys.databases AS dtb
    WHERE   dtb.name = @Database_Name
 
    IF ISNULL(@Compatibility_Level, 0) <= 80
        BEGIN
            RAISERROR('The compatibility level should be equal to or greater SQL SERVER 2005 (90)',16,1)
            RETURN
        END
 
    IF ( SELECT COUNT(*)
         FROM   INFORMATION_SCHEMA.TABLES
         WHERE  [TABLE_SCHEMA] + '.' + [TABLE_NAME] = @SchemaName_n_TableName
       ) = 0
        BEGIN
            RAISERROR('Could not found the table in the defined database',16,1)
            RETURN
        END
 
    DECLARE @bitTable TABLE
        (
          [ID] INT ,
          [Bitvalue] INT
        )
--Create table to set the bit position of one byte.
 
    INSERT  INTO @bitTable
            SELECT  0 ,
                    2
            UNION ALL
            SELECT  1 ,
                    2
            UNION ALL
            SELECT  2 ,
                    4
            UNION ALL
            SELECT  3 ,
                    8
            UNION ALL
            SELECT  4 ,
                    16
            UNION ALL
            SELECT  5 ,
                    32
            UNION ALL
            SELECT  6 ,
                    64
            UNION ALL
            SELECT  7 ,
                    128
 
--Create table to collect the row data.
    DECLARE @DeletedRecords TABLE
        (
          [Row ID] INT IDENTITY(1, 1) ,
          [RowLogContents] VARBINARY(8000) ,
          [AllocUnitID] BIGINT ,
          [Transaction ID] NVARCHAR(MAX) ,
          [FixedLengthData] SMALLINT ,
          [TotalNoOfCols] SMALLINT ,
          [NullBitMapLength] SMALLINT ,
          [NullBytes] VARBINARY(8000) ,
          [TotalNoofVarCols] SMALLINT ,
          [ColumnOffsetArray] VARBINARY(8000) ,
          [VarColumnStart] SMALLINT ,
          [Slot ID] INT ,
          [NullBitMap] VARCHAR(MAX)
        )
--Create a common table expression to get all the row data plus how many bytes we have for each row.
;
    WITH    RowData
              AS ( SELECT   [RowLog Contents 0] AS [RowLogContents] ,
                            [AllocUnitID] AS [AllocUnitID] ,
                            [Transaction ID] AS [Transaction ID]  
 
--[Fixed Length Data] = Substring (RowLog content 0, Status Bit A+ Status Bit B + 1,2 bytes)
                            ,
                            CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) AS [FixedLengthData]  --@FixedLengthData
 
-- [TotalnoOfCols] =  Substring (RowLog content 0, [Fixed Length Data] + 1,2 bytes)
                            ,
                            CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 1,
                                                              2)))) AS [TotalNoOfCols]
 
--[NullBitMapLength]=ceiling([Total No of Columns] /8.0)
                            ,
                            CONVERT(INT, CEILING(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 1,
                                                              2)))) / 8.0)) AS [NullBitMapLength] 
 
--[Null Bytes] = Substring (RowLog content 0, Status Bit A+ Status Bit B + [Fixed Length Data] +1, [NullBitMapLength] )
                            ,
                            SUBSTRING([RowLog Contents 0],
                                      CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 3,
                                      CONVERT(INT, CEILING(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 1,
                                                              2)))) / 8.0))) AS [NullBytes]
 
--[TotalNoofVarCols] = Substring (RowLog content 0, Status Bit A+ Status Bit B + [Fixed Length Data] +1, [Null Bitmap length] + 2 )
                            ,
                            ( CASE WHEN SUBSTRING([RowLog Contents 0], 1, 1) IN (
                                        0x10, 0x30, 0x70 )
                                   THEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 3
                                                              + CONVERT(INT, CEILING(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 1,
                                                              2)))) / 8.0)), 2))))
                                   ELSE NULL
                              END ) AS [TotalNoofVarCols] 
 
--[ColumnOffsetArray]= Substring (RowLog content 0, Status Bit A+ Status Bit B + [Fixed Length Data] +1, [Null Bitmap length] + 2 , [TotalNoofVarCols]*2 )
                            ,
                            ( CASE WHEN SUBSTRING([RowLog Contents 0], 1, 1) IN (
                                        0x10, 0x30, 0x70 )
                                   THEN SUBSTRING([RowLog Contents 0],
                                                  CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 3
                                                  + CONVERT(INT, CEILING(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 1,
                                                              2)))) / 8.0))
                                                  + 2,
                                                  ( CASE WHEN SUBSTRING([RowLog Contents 0],
                                                              1, 1) IN ( 0x10,
                                                              0x30, 0x70 )
                                                         THEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 3
                                                              + CONVERT(INT, CEILING(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 1,
                                                              2)))) / 8.0)), 2))))
                                                         ELSE NULL
                                                    END ) * 2)
                                   ELSE NULL
                              END ) AS [ColumnOffsetArray] 
 
--  Variable column Start = Status Bit A+ Status Bit B + [Fixed Length Data] + [Null Bitmap length] + 2+([TotalNoofVarCols]*2)
                            ,
                            CASE WHEN SUBSTRING([RowLog Contents 0], 1, 1) IN (
                                      0x10, 0x30, 0x70 )
                                 THEN ( CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 4
                                        + CONVERT(INT, CEILING(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 1,
                                                              2)))) / 8.0))
                                        + ( ( CASE WHEN SUBSTRING([RowLog Contents 0],
                                                              1, 1) IN ( 0x10,
                                                              0x30, 0x70 )
                                                   THEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 3
                                                              + CONVERT(INT, CEILING(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              2 + 1, 2)))) + 1,
                                                              2)))) / 8.0)), 2))))
                                                   ELSE NULL
                                              END ) * 2 ) )
                                 ELSE NULL
                            END AS [VarColumnStart] ,
                            [Slot ID]
                   FROM     fn_dump_dblog(NULL, NULL, N'DISK', 1, @Backuppath,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT)
                   WHERE    AllocUnitId IN (
                            SELECT  [Allocation_unit_id]
                            FROM    sys.allocation_units allocunits
                                    INNER JOIN sys.partitions partitions ON ( allocunits.type IN (
                                                              1, 3 )
                                                              AND partitions.hobt_id = allocunits.container_id
                                                              )
                                                              OR ( allocunits.type = 2
                                                              AND partitions.partition_id = allocunits.container_id
                                                              )
                            WHERE   object_id = OBJECT_ID(''
                                                          + @SchemaName_n_TableName
                                                          + '') )
                            AND Context IN ( 'LCX_MARK_AS_GHOST', 'LCX_HEAP' )
                            AND Operation IN ( 'LOP_DELETE_ROWS' )
                            AND SUBSTRING([RowLog Contents 0], 1, 1) IN ( 0x10,
                                                              0x30, 0x70 )
 
/*Use this subquery to filter the date*/
                            AND [TRANSACTION ID] IN (
                            SELECT DISTINCT
                                    [TRANSACTION ID]
                            FROM    fn_dump_dblog(NULL, NULL, N'DISK', 1,
                                                  @Backuppath, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT, DEFAULT,
                                                  DEFAULT, DEFAULT)
                            WHERE   Context IN ( 'LCX_NULL' )
                                    AND Operation IN ( 'LOP_BEGIN_XACT' )
                                    AND [Transaction Name] IN ( 'DELETE',
                                                              'user_transaction' )
                                    AND CONVERT(NVARCHAR(11), [Begin Time]) BETWEEN @Date_From
                                                              AND
                                                              @Date_To )
                 ),
 
--Use this technique to repeate the row till the no of bytes of the row.
            N1 ( n )
              AS ( SELECT   1
                   UNION ALL
                   SELECT   1
                 ),
            N2 ( n )
              AS ( SELECT   1
                   FROM     N1 AS X ,
                            N1 AS Y
                 ),
            N3 ( n )
              AS ( SELECT   1
                   FROM     N2 AS X ,
                            N2 AS Y
                 ),
            N4 ( n )
              AS ( SELECT   ROW_NUMBER() OVER ( ORDER BY X.n )
                   FROM     N3 AS X ,
                            N3 AS Y
                 )
        INSERT  INTO @DeletedRecords
                SELECT  RowLogContents ,
                        [AllocUnitID] ,
                        [Transaction ID] ,
                        [FixedLengthData] ,
                        [TotalNoOfCols] ,
                        [NullBitMapLength] ,
                        [NullBytes] ,
                        [TotalNoofVarCols] ,
                        [ColumnOffsetArray] ,
                        [VarColumnStart] ,
                        [Slot ID]
         ---Get the Null value against each column (1 means null zero means not null)
                        ,
                        [NullBitMap] = ( REPLACE(STUFF(( SELECT
                                                              ','
                                                              + ( CASE
                                                              WHEN [ID] = 0
                                                              THEN CONVERT(NVARCHAR(1), ( SUBSTRING(NullBytes,
                                                              n, 1) % 2 ))
                                                              ELSE CONVERT(NVARCHAR(1), ( ( SUBSTRING(NullBytes,
                                                              n, 1)
                                                              / [Bitvalue] )
                                                              % 2 ))
                                                              END ) --as [nullBitMap]
                                                         FROM N4 AS Nums
                                                              JOIN RowData AS C ON n <= NullBitMapLength
                                                              CROSS JOIN @bitTable
                                                         WHERE
                                                              C.[RowLogContents] = D.[RowLogContents]
                                                         ORDER BY [RowLogContents] ,
                                                              n ASC
                                                       FOR
                                                         XML PATH('')
                                                       ), 1, 1, ''), ',', '') )
                FROM    RowData D
 
    IF ( SELECT COUNT(*)
         FROM   @DeletedRecords
       ) = 0
        BEGIN
            RAISERROR('There is no data in the log as per the search criteria',16,1)
            RETURN
        END
 
    DECLARE @ColumnNameAndData TABLE
        (
          [Row ID] INT ,
          [Rowlogcontents] VARBINARY(MAX) ,
          [NAME] SYSNAME ,
          [nullbit] SMALLINT ,
          [leaf_offset] SMALLINT ,
          [length] SMALLINT ,
          [system_type_id] TINYINT ,
          [bitpos] TINYINT ,
          [xprec] TINYINT ,
          [xscale] TINYINT ,
          [is_null] INT ,
          [Column value Size] INT ,
          [Column Length] INT ,
          [hex_Value] VARBINARY(MAX) ,
          [Slot ID] INT ,
          [Update] INT
        )
 
--Create common table expression and join it with the rowdata table
-- to get each column details
/*This part is for variable data columns*/
--@RowLogContents, 
--(col.columnOffValue - col.columnLength) + 1,
--col.columnLength
--)
    INSERT  INTO @ColumnNameAndData
            SELECT  [Row ID] ,
                    Rowlogcontents ,
                    NAME ,
                    cols.leaf_null_bit AS nullbit ,
                    leaf_offset ,
                    ISNULL(syscolumns.length, cols.max_length) AS [length] ,
                    cols.system_type_id ,
                    cols.leaf_bit_position AS bitpos ,
                    ISNULL(syscolumns.xprec, cols.precision) AS xprec ,
                    ISNULL(syscolumns.xscale, cols.scale) AS xscale ,
                    SUBSTRING([nullBitMap], cols.leaf_null_bit, 1) AS is_null ,
                    ( CASE WHEN leaf_offset < 1
                                AND SUBSTRING([nullBitMap], cols.leaf_null_bit,
                                              1) = 0
                           THEN ( CASE WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) > 30000
                                       THEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2))))
                                            - POWER(2, 15)
                                       ELSE CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2))))
                                  END )
                      END ) AS [Column value Size] ,
                    ( CASE WHEN leaf_offset < 1
                                AND SUBSTRING([nullBitMap], cols.leaf_null_bit,
                                              1) = 0
                           THEN ( CASE WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) > 30000
                                            AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                       [varColumnStart]) < 30000
                                       THEN ( CASE WHEN [System_type_id] IN (
                                                        35, 34, 99 ) THEN 16
                                                   ELSE 24
                                              END )
                                       WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) > 30000
                                            AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                       [varColumnStart]) > 30000
                                       THEN ( CASE WHEN [System_type_id] IN (
                                                        35, 34, 99 ) THEN 16
                                                   ELSE 24
                                              END ) --24 
                                       WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) < 30000
                                            AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                       [varColumnStart]) < 30000
                                       THEN ( CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2))))
                                              - ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                       [varColumnStart]) )
                                       WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) < 30000
                                            AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                       [varColumnStart]) > 30000
                                       THEN POWER(2, 15)
                                            + CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2))))
                                            - ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                     [varColumnStart])
                                  END )
                      END ) AS [Column Length] ,
                    ( CASE WHEN SUBSTRING([nullBitMap], cols.leaf_null_bit, 1) = 1
                           THEN NULL
                           ELSE SUBSTRING(Rowlogcontents,
                                          ( ( CASE WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) > 30000
                                                   THEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2))))
                                                        - POWER(2, 15)
                                                   ELSE CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2))))
                                              END )
                                            - ( CASE WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) > 30000
                                                          AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart]) < 30000
                                                     THEN ( CASE
                                                              WHEN [System_type_id] IN (
                                                              35, 34, 99 )
                                                              THEN 16
                                                              ELSE 24
                                                            END ) --24 
                                                     WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) > 30000
                                                          AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart]) > 30000
                                                     THEN ( CASE
                                                              WHEN [System_type_id] IN (
                                                              35, 34, 99 )
                                                              THEN 16
                                                              ELSE 24
                                                            END ) --24 
                                                     WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) < 30000
                                                          AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart]) < 30000
                                                     THEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2))))
                                                          - ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart])
                                                     WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) < 30000
                                                          AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart]) > 30000
                                                     THEN POWER(2, 15)
                                                          + CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2))))
                                                          - ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart])
                                                END ) ) + 1,
                                          ( CASE WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) > 30000
                                                      AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart]) < 30000
                                                 THEN ( CASE WHEN [System_type_id] IN (
                                                              35, 34, 99 )
                                                             THEN 16
                                                             ELSE 24
                                                        END ) --24 
                                                 WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) > 30000
                                                      AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart]) > 30000
                                                 THEN ( CASE WHEN [System_type_id] IN (
                                                              35, 34, 99 )
                                                             THEN 16
                                                             ELSE 24
                                                        END ) --24 
                                                 WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) < 30000
                                                      AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart]) < 30000
                                                 THEN ABS(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2))))
                                                          - ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart]))
                                                 WHEN CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2)))) < 30000
                                                      AND ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart]) > 30000
                                                 THEN POWER(2, 15)
                                                      + CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * leaf_offset
                                                              * -1 ) - 1, 2))))
                                                      - ISNULL(NULLIF(CONVERT(INT, CONVERT(BINARY(2), REVERSE(SUBSTRING([ColumnOffsetArray],
                                                              ( 2
                                                              * ( ( leaf_offset
                                                              * -1 ) - 1 ) )
                                                              - 1, 2)))), 0),
                                                              [varColumnStart])
                                            END ))
                      END ) AS hex_Value ,
                    [Slot ID] ,
                    0
            FROM    @DeletedRecords A
                    INNER JOIN sys.allocation_units allocunits ON A.[AllocUnitId] = allocunits.[Allocation_Unit_Id]
                    INNER JOIN sys.partitions partitions ON ( allocunits.type IN (
                                                              1, 3 )
                                                              AND partitions.hobt_id = allocunits.container_id
                                                            )
                                                            OR ( allocunits.type = 2
                                                              AND partitions.partition_id = allocunits.container_id
                                                              )
                    INNER JOIN sys.system_internals_partition_columns cols ON cols.partition_id = partitions.partition_id
                    LEFT OUTER JOIN syscolumns ON syscolumns.id = partitions.object_id
                                                  AND syscolumns.colid = cols.partition_column_id
            WHERE   leaf_offset < 0
            UNION
/*This part is for fixed data columns*/
            SELECT  [Row ID] ,
                    Rowlogcontents ,
                    NAME ,
                    cols.leaf_null_bit AS nullbit ,
                    leaf_offset ,
                    ISNULL(syscolumns.length, cols.max_length) AS [length] ,
                    cols.system_type_id ,
                    cols.leaf_bit_position AS bitpos ,
                    ISNULL(syscolumns.xprec, cols.precision) AS xprec ,
                    ISNULL(syscolumns.xscale, cols.scale) AS xscale ,
                    SUBSTRING([nullBitMap], cols.leaf_null_bit, 1) AS is_null ,
                    ( SELECT TOP 1
                                ISNULL(SUM(CASE WHEN C.leaf_offset > 1
                                                THEN max_length
                                                ELSE 0
                                           END), 0)
                      FROM      sys.system_internals_partition_columns C
                      WHERE     cols.partition_id = C.partition_id
                                AND C.leaf_null_bit < cols.leaf_null_bit
                    ) + 5 AS [Column value Size] ,
                    syscolumns.length AS [Column Length] ,
                    CASE WHEN SUBSTRING([nullBitMap], cols.leaf_null_bit, 1) = 1
                         THEN NULL
                         ELSE SUBSTRING(Rowlogcontents,
                                        ( SELECT TOP 1
                                                    ISNULL(SUM(CASE
                                                              WHEN C.leaf_offset > 1
                                                              AND C.leaf_bit_position = 0
                                                              THEN max_length
                                                              ELSE 0
                                                              END), 0)
                                          FROM      sys.system_internals_partition_columns C
                                          WHERE     cols.partition_id = C.partition_id
                                                    AND C.leaf_null_bit < cols.leaf_null_bit
                                        ) + 5, syscolumns.length)
                    END AS hex_Value ,
                    [Slot ID] ,
                    0
            FROM    @DeletedRecords A
                    INNER JOIN sys.allocation_units allocunits ON A.[AllocUnitId] = allocunits.[Allocation_Unit_Id]
                    INNER JOIN sys.partitions partitions ON ( allocunits.type IN (
                                                              1, 3 )
                                                              AND partitions.hobt_id = allocunits.container_id
                                                            )
                                                            OR ( allocunits.type = 2
                                                              AND partitions.partition_id = allocunits.container_id
                                                              )
                    INNER JOIN sys.system_internals_partition_columns cols ON cols.partition_id = partitions.partition_id
                    LEFT OUTER JOIN syscolumns ON syscolumns.id = partitions.object_id
                                                  AND syscolumns.colid = cols.partition_column_id
            WHERE   leaf_offset > 0
            ORDER BY nullbit
 
    DECLARE @BitColumnByte AS INT
    SELECT  @BitColumnByte = CONVERT(INT, CEILING(COUNT(*) / 8.0))
    FROM    @ColumnNameAndData
    WHERE   [System_Type_id] = 104;
    WITH    N1 ( n )
              AS ( SELECT   1
                   UNION ALL
                   SELECT   1
                 ),
            N2 ( n )
              AS ( SELECT   1
                   FROM     N1 AS X ,
                            N1 AS Y
                 ),
            N3 ( n )
              AS ( SELECT   1
                   FROM     N2 AS X ,
                            N2 AS Y
                 ),
            N4 ( n )
              AS ( SELECT   ROW_NUMBER() OVER ( ORDER BY X.n )
                   FROM     N3 AS X ,
                            N3 AS Y
                 ),
            CTE
              AS ( SELECT   RowLogContents ,
                            [nullbit] ,
                            [BitMap] = CONVERT(VARBINARY(1), CONVERT(INT, SUBSTRING(( REPLACE(STUFF(( SELECT
                                                              ','
                                                              + ( CASE
                                                              WHEN [ID] = 0
                                                              THEN CONVERT(NVARCHAR(1), ( SUBSTRING(hex_Value,
                                                              n, 1) % 2 ))
                                                              ELSE CONVERT(NVARCHAR(1), ( ( SUBSTRING(hex_Value,
                                                              n, 1)
                                                              / [Bitvalue] )
                                                              % 2 ))
                                                              END ) --as [nullBitMap]
                                                              FROM
                                                              N4 AS Nums
                                                              JOIN @ColumnNameAndData
                                                              AS C ON n <= @BitColumnByte
                                                              AND [System_Type_id] = 104
                                                              AND bitpos = 0
                                                              CROSS JOIN @bitTable
                                                              WHERE
                                                              C.[RowLogContents] = D.[RowLogContents]
                                                              ORDER BY [RowLogContents] ,
                                                              n ASC
                                                              FOR
                                                              XML
                                                              PATH('')
                                                              ), 1, 1, ''),
                                                              ',', '') ),
                                                              bitpos + 1, 1)))
                   FROM     @ColumnNameAndData D
                   WHERE    [System_Type_id] = 104
                 )
        UPDATE  A
        SET     [hex_Value] = [BitMap]
        FROM    @ColumnNameAndData A
                INNER JOIN CTE B ON A.[RowLogContents] = B.[RowLogContents]
                                    AND A.[nullbit] = B.[nullbit]
 
 
/**************Check for BLOB DATA TYPES******************************/
    DECLARE @Fileid INT
    DECLARE @Pageid INT
    DECLARE @Slotid INT
    DECLARE @CurrentLSN INT
    DECLARE @LinkID INT
    DECLARE @Context VARCHAR(50)
    DECLARE @ConsolidatedPageID VARCHAR(MAX)
    DECLARE @LCX_TEXT_MIX VARBINARY(MAX)
 
    DECLARE @temppagedata TABLE
        (
          [ParentObject] SYSNAME ,
          [Object] SYSNAME ,
          [Field] SYSNAME ,
          [Value] SYSNAME
        )
 
    DECLARE @pagedata TABLE
        (
          [Page ID] SYSNAME ,
          [File IDS] INT ,
          [Page IDS] INT ,
          [AllocUnitId] BIGINT ,
          [ParentObject] SYSNAME ,
          [Object] SYSNAME ,
          [Field] SYSNAME ,
          [Value] SYSNAME
        )
 
    DECLARE @ModifiedRawData TABLE
        (
          [ID] INT IDENTITY(1, 1) ,
          [PAGE ID] VARCHAR(MAX) ,
          [FILE IDS] INT ,
          [PAGE IDS] INT ,
          [Slot ID] INT ,
          [AllocUnitId] BIGINT ,
          [RowLog Contents 0_var] VARCHAR(MAX) ,
          [RowLog Length] VARCHAR(50) ,
          [RowLog Len] INT ,
          [RowLog Contents 0] VARBINARY(MAX) ,
          [Link ID] INT DEFAULT ( 0 ) ,
          [Update] INT
        )
 
    DECLARE Page_Data_Cursor CURSOR
    FOR
        /*We need to filter LOP_MODIFY_ROW,LOP_MODIFY_COLUMNS from log for deleted records of BLOB data type& Get its Slot No, Page ID & AllocUnit ID*/
            SELECT  LTRIM(RTRIM(REPLACE([Description], 'Deallocated', ''))) AS [PAGE ID] ,
                    [Slot ID] ,
                    [AllocUnitId] ,
                    NULL AS [RowLog Contents 0] ,
                    NULL AS [RowLog Contents 0] ,
                    Context
            FROM    fn_dump_dblog(NULL, NULL, N'DISK', 1, @Backuppath, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT)
            WHERE   AllocUnitId IN (
                    SELECT  [Allocation_unit_id]
                    FROM    sys.allocation_units allocunits
                            INNER JOIN sys.partitions partitions ON ( allocunits.type IN (
                                                              1, 3 )
                                                              AND partitions.hobt_id = allocunits.container_id
                                                              )
                                                              OR ( allocunits.type = 2
                                                              AND partitions.partition_id = allocunits.container_id
                                                              )
                    WHERE   object_id = OBJECT_ID('' + @SchemaName_n_TableName
                                                  + '') )
                    AND Operation IN ( 'LOP_MODIFY_ROW' )
                    AND [Context] IN ( 'LCX_PFS' )
                    AND Description LIKE '%Deallocated%'
            /*Use this subquery to filter the date*/
                    AND [TRANSACTION ID] IN (
                    SELECT DISTINCT
                            [TRANSACTION ID]
                    FROM    fn_dump_dblog(NULL, NULL, N'DISK', 1, @Backuppath,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT)
                    WHERE   Context IN ( 'LCX_NULL' )
                            AND Operation IN ( 'LOP_BEGIN_XACT' )
                            AND [Transaction Name] = 'DELETE'
                            AND CONVERT(NVARCHAR(11), [Begin Time]) BETWEEN @Date_From
                                                              AND
                                                              @Date_To )
            GROUP BY [Description] ,
                    [Slot ID] ,
                    [AllocUnitId] ,
                    Context
            UNION
            SELECT  [PAGE ID] ,
                    [Slot ID] ,
                    [AllocUnitId] ,
                    SUBSTRING([RowLog Contents 0], 15,
                              LEN([RowLog Contents 0])) AS [RowLog Contents 0] ,
                    CONVERT(INT, SUBSTRING([RowLog Contents 0], 7, 2)) ,
                    Context --,CAST(RIGHT([Current LSN],4) AS INT) AS [Current LSN]
            FROM    fn_dump_dblog(NULL, NULL, N'DISK', 1, @Backuppath, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                  DEFAULT, DEFAULT)
            WHERE   AllocUnitId IN (
                    SELECT  [Allocation_unit_id]
                    FROM    sys.allocation_units allocunits
                            INNER JOIN sys.partitions partitions ON ( allocunits.type IN (
                                                              1, 3 )
                                                              AND partitions.hobt_id = allocunits.container_id
                                                              )
                                                              OR ( allocunits.type = 2
                                                              AND partitions.partition_id = allocunits.container_id
                                                              )
                    WHERE   object_id = OBJECT_ID('' + @SchemaName_n_TableName
                                                  + '') )
                    AND Context IN ( 'LCX_TEXT_MIX' )
                    AND Operation IN ( 'LOP_DELETE_ROWS' ) 
            /*Use this subquery to filter the date*/
                    AND [TRANSACTION ID] IN (
                    SELECT DISTINCT
                            [TRANSACTION ID]
                    FROM    fn_dump_dblog(NULL, NULL, N'DISK', 1, @Backuppath,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT, DEFAULT,
                                          DEFAULT, DEFAULT, DEFAULT)
                    WHERE   Context IN ( 'LCX_NULL' )
                            AND Operation IN ( 'LOP_BEGIN_XACT' )
                            AND [Transaction Name] = 'DELETE'
                            AND CONVERT(NVARCHAR(11), [Begin Time]) BETWEEN @Date_From
                                                              AND
                                                              @Date_To )
                         
            /****************************************/
 
    OPEN Page_Data_Cursor
 
    FETCH NEXT FROM Page_Data_Cursor INTO @ConsolidatedPageID, @Slotid,
        @AllocUnitID, @LCX_TEXT_MIX, @LinkID, @Context
 
    WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @hex_pageid AS VARCHAR(MAX)
            /*Page ID contains File Number and page number It looks like 0001:00000130.
              In this example 0001 is file Number &  00000130 is Page Number & These numbers are in Hex format*/
            SET @Fileid = SUBSTRING(@ConsolidatedPageID, 0,
                                    CHARINDEX(':', @ConsolidatedPageID)) -- Seperate File ID from Page ID
         
            SET @hex_pageid = '0x' + SUBSTRING(@ConsolidatedPageID,
                                               CHARINDEX(':',
                                                         @ConsolidatedPageID)
                                               + 1, LEN(@ConsolidatedPageID))  ---Seperate the page ID
            SELECT  @Pageid = CONVERT(INT, CAST('' AS XML).value('xs:hexBinary(substring(sql:variable("@hex_pageid"),sql:column("t.pos")) )',
                                                              'varbinary(max)')) -- Convert Page ID from hex to integer
            FROM    ( SELECT    CASE SUBSTRING(@hex_pageid, 1, 2)
                                  WHEN '0x' THEN 3
                                  ELSE 0
                                END
                    ) AS t ( pos ) 
             
            IF @Context = 'LCX_PFS'
                BEGIN
                    DELETE  @temppagedata
                    INSERT  INTO @temppagedata
                            EXEC
                                ( 'DBCC PAGE(' + @DataBase_Name + ', '
                                  + @fileid + ', ' + @pageid
                                  + ', 1) with tableresults,no_infomsgs;'
                                ); 
                    INSERT  INTO @pagedata
                            SELECT  @ConsolidatedPageID ,
                                    @fileid ,
                                    @pageid ,
                                    @AllocUnitID ,
                                    [ParentObject] ,
                                    [Object] ,
                                    [Field] ,
                                    [Value]
                            FROM    @temppagedata
                END
            ELSE
                IF @Context = 'LCX_TEXT_MIX'
                    BEGIN
                        INSERT  INTO @ModifiedRawData
                                SELECT  @ConsolidatedPageID ,
                                        @fileid ,
                                        @pageid ,
                                        @Slotid ,
                                        @AllocUnitID ,
                                        NULL ,
                                        0 ,
                                        CONVERT(INT, CONVERT(VARBINARY, REVERSE(SUBSTRING(@LCX_TEXT_MIX,
                                                              11, 2)))) ,
                                        @LCX_TEXT_MIX ,
                                        @LinkID ,
                                        0
                    END    
            FETCH NEXT FROM Page_Data_Cursor INTO @ConsolidatedPageID, @Slotid,
                @AllocUnitID, @LCX_TEXT_MIX, @LinkID, @Context
        END
     
    CLOSE Page_Data_Cursor
    DEALLOCATE Page_Data_Cursor
 
    DECLARE @Newhexstring VARCHAR(MAX);
 
    --The data is in multiple rows in the page, so we need to convert it into one row as a single hex value.
    --This hex value is in string format
    INSERT  INTO @ModifiedRawData
            ( [PAGE ID] ,
              [FILE IDS] ,
              [PAGE IDS] ,
              [Slot ID] ,
              [AllocUnitId] ,
              [RowLog Contents 0_var] ,
              [RowLog Length]
            )
            SELECT  [Page ID] ,
                    [FILE IDS] ,
                    [PAGE IDS] ,
                    SUBSTRING([ParentObject],
                              CHARINDEX('Slot', [ParentObject]) + 4,
                              ( CHARINDEX('Offset', [ParentObject])
                                - ( CHARINDEX('Slot', [ParentObject]) + 4 ) )
                              - 2) AS [Slot ID] ,
                    [AllocUnitId] ,
                    SUBSTRING(( SELECT  REPLACE(STUFF(( SELECT
                                                              REPLACE(SUBSTRING([Value],
                                                              CHARINDEX(':',
                                                              [Value]) + 1,
                                                              CHARINDEX('?',
                                                              [Value])
                                                              - CHARINDEX(':',
                                                              [Value])), '?',
                                                              '')
                                                        FROM  @pagedata C
                                                        WHERE B.[Page ID] = C.[Page ID]
                                                              AND SUBSTRING(B.[ParentObject],
                                                              CHARINDEX('Slot',
                                                              B.[ParentObject])
                                                              + 4,
                                                              ( CHARINDEX('Offset',
                                                              B.[ParentObject])
                                                              - ( CHARINDEX('Slot',
                                                              B.[ParentObject])
                                                              + 4 ) )) = SUBSTRING(C.[ParentObject],
                                                              CHARINDEX('Slot',
                                                              C.[ParentObject])
                                                              + 4,
                                                              ( CHARINDEX('Offset',
                                                              C.[ParentObject])
                                                              - ( CHARINDEX('Slot',
                                                              C.[ParentObject])
                                                              + 4 ) ))
                                                              AND [Object] LIKE '%Memory Dump%'
                                                        ORDER BY '0x'
                                                              + LEFT([Value],
                                                              CHARINDEX(':',
                                                              [Value]) - 1)
                                                      FOR
                                                        XML PATH('')
                                                      ), 1, 1, ''), ' ', '')
                              ), 1, 20000) AS [Value] ,
                    SUBSTRING(( SELECT  '0x'
                                        + REPLACE(STUFF(( SELECT
                                                              REPLACE(SUBSTRING([Value],
                                                              CHARINDEX(':',
                                                              [Value]) + 1,
                                                              CHARINDEX('?',
                                                              [Value])
                                                              - CHARINDEX(':',
                                                              [Value])), '?',
                                                              '')
                                                          FROM
                                                              @pagedata C
                                                          WHERE
                                                              B.[Page ID] = C.[Page ID]
                                                              AND SUBSTRING(B.[ParentObject],
                                                              CHARINDEX('Slot',
                                                              B.[ParentObject])
                                                              + 4,
                                                              ( CHARINDEX('Offset',
                                                              B.[ParentObject])
                                                              - ( CHARINDEX('Slot',
                                                              B.[ParentObject])
                                                              + 4 ) )) = SUBSTRING(C.[ParentObject],
                                                              CHARINDEX('Slot',
                                                              C.[ParentObject])
                                                              + 4,
                                                              ( CHARINDEX('Offset',
                                                              C.[ParentObject])
                                                              - ( CHARINDEX('Slot',
                                                              C.[ParentObject])
                                                              + 4 ) ))
                                                              AND [Object] LIKE '%Memory Dump%'
                                                          ORDER BY '0x'
                                                              + LEFT([Value],
                                                              CHARINDEX(':',
                                                              [Value]) - 1)
                                                        FOR
                                                          XML PATH('')
                                                        ), 1, 1, ''), ' ', '')
                              ), 7, 4) AS [Length]
            FROM    @pagedata B
            WHERE   [Object] LIKE '%Memory Dump%'
            GROUP BY [Page ID] ,
                    [FILE IDS] ,
                    [PAGE IDS] ,
                    [ParentObject] ,
                    [AllocUnitId]--,[Current LSN]
            ORDER BY [Slot ID]
 
    UPDATE  @ModifiedRawData
    SET     [RowLog Len] = CONVERT(VARBINARY(8000), REVERSE(CAST('' AS XML).value('xs:hexBinary(substring(sql:column("[RowLog Length]"),0))',
                                                              'varbinary(Max)')))
    FROM    @ModifiedRawData
    WHERE   [LINK ID] = 0
 
    UPDATE  @ModifiedRawData
    SET     [RowLog Contents 0] = CAST('' AS XML).value('xs:hexBinary(substring(sql:column("[RowLog Contents 0_var]"),0))',
                                                        'varbinary(Max)')
    FROM    @ModifiedRawData
    WHERE   [LINK ID] = 0
 
    UPDATE  B
    SET     B.[RowLog Contents 0] = ( CASE WHEN A.[RowLog Contents 0] IS NOT NULL
                                                AND C.[RowLog Contents 0] IS NOT NULL
                                           THEN A.[RowLog Contents 0]
                                                + C.[RowLog Contents 0]
                                           WHEN A.[RowLog Contents 0] IS NULL
                                                AND C.[RowLog Contents 0] IS NOT NULL
                                           THEN C.[RowLog Contents 0]
                                           WHEN A.[RowLog Contents 0] IS NOT NULL
                                                AND C.[RowLog Contents 0] IS NULL
                                           THEN A.[RowLog Contents 0]
                                      END ) ,
            B.[Update] = ISNULL(B.[Update], 0) + 1
    FROM    @ModifiedRawData B
            LEFT JOIN @ModifiedRawData A ON A.[Page IDS] = CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING(B.[RowLog Contents 0],
                                                              15 + 14, 2))))
                                            AND A.[File IDS] = CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING(B.[RowLog Contents 0],
                                                              19 + 14, 2))))
                                            AND A.[Link ID] = B.[Link ID]
            LEFT JOIN @ModifiedRawData C ON C.[Page IDS] = CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING(B.[RowLog Contents 0],
                                                              27 + 14, 2))))
                                            AND C.[File IDS] = CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING(B.[RowLog Contents 0],
                                                              31 + 14, 2))))
                                            AND C.[Link ID] = B.[Link ID]
    WHERE   ( A.[RowLog Contents 0] IS NOT NULL
              OR C.[RowLog Contents 0] IS NOT NULL
            )
 
 
    UPDATE  B
    SET     B.[RowLog Contents 0] = ( CASE WHEN A.[RowLog Contents 0] IS NOT NULL
                                                AND C.[RowLog Contents 0] IS NOT NULL
                                           THEN A.[RowLog Contents 0]
                                                + C.[RowLog Contents 0]
                                           WHEN A.[RowLog Contents 0] IS NULL
                                                AND C.[RowLog Contents 0] IS NOT NULL
                                           THEN C.[RowLog Contents 0]
                                           WHEN A.[RowLog Contents 0] IS NOT NULL
                                                AND C.[RowLog Contents 0] IS NULL
                                           THEN A.[RowLog Contents 0]
                                      END )
    --,B.[Update]=ISNULL(B.[Update],0)+1
    FROM    @ModifiedRawData B
            LEFT JOIN @ModifiedRawData A ON A.[Page IDS] = CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING(B.[RowLog Contents 0],
                                                              15 + 14, 2))))
                                            AND A.[File IDS] = CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING(B.[RowLog Contents 0],
                                                              19 + 14, 2))))
                                            AND A.[Link ID] <> B.[Link ID]
                                            AND B.[Update] = 0
            LEFT JOIN @ModifiedRawData C ON C.[Page IDS] = CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING(B.[RowLog Contents 0],
                                                              27 + 14, 2))))
                                            AND C.[File IDS] = CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING(B.[RowLog Contents 0],
                                                              31 + 14, 2))))
                                            AND C.[Link ID] <> B.[Link ID]
                                            AND B.[Update] = 0
    WHERE   ( A.[RowLog Contents 0] IS NOT NULL
              OR C.[RowLog Contents 0] IS NOT NULL
            )
 
    UPDATE  @ModifiedRawData
    SET     [RowLog Contents 0] = ( CASE WHEN [RowLog Len] >= 8000
                                         THEN SUBSTRING([RowLog Contents 0],
                                                        15, [RowLog Len])
                                         WHEN [RowLog Len] < 8000
                                         THEN SUBSTRING([RowLog Contents 0],
                                                        15 + 6,
                                                        CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING([RowLog Contents 0],
                                                              15, 6)))))
                                    END )
    FROM    @ModifiedRawData
    WHERE   [LINK ID] = 0
 
    UPDATE  @ColumnNameAndData
    SET     [hex_Value] = [RowLog Contents 0] 
    --,A.[Update]=A.[Update]+1
    FROM    @ColumnNameAndData A
            INNER JOIN @ModifiedRawData B ON CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING([hex_value],
                                                              17, 4)))) = [PAGE IDS]
                                             AND CONVERT(INT, SUBSTRING([hex_value],
                                                              9, 2)) = B.[Link ID]
    WHERE   [System_Type_Id] IN ( 99, 167, 175, 231, 239, 241, 165, 98 )
            AND [Link ID] <> 0 
 
    UPDATE  @ColumnNameAndData
    SET     [hex_Value] = ( CASE WHEN B.[RowLog Contents 0] IS NOT NULL
                                      AND C.[RowLog Contents 0] IS NOT NULL
                                 THEN B.[RowLog Contents 0]
                                      + C.[RowLog Contents 0]
                                 WHEN B.[RowLog Contents 0] IS NULL
                                      AND C.[RowLog Contents 0] IS NOT NULL
                                 THEN C.[RowLog Contents 0]
                                 WHEN B.[RowLog Contents 0] IS NOT NULL
                                      AND C.[RowLog Contents 0] IS NULL
                                 THEN B.[RowLog Contents 0]
                            END )
    --,A.[Update]=A.[Update]+1
    FROM    @ColumnNameAndData A
            LEFT JOIN @ModifiedRawData B ON CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING([hex_value],
                                                              5, 4)))) = B.[PAGE IDS]
                                            AND B.[Link ID] = 0
            LEFT JOIN @ModifiedRawData C ON CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING([hex_value],
                                                              17, 4)))) = C.[PAGE IDS]
                                            AND C.[Link ID] = 0
    WHERE   [System_Type_Id] IN ( 99, 167, 175, 231, 239, 241, 165, 98 )
            AND ( B.[RowLog Contents 0] IS NOT NULL
                  OR C.[RowLog Contents 0] IS NOT NULL
                )
 
    UPDATE  @ColumnNameAndData
    SET     [hex_Value] = [RowLog Contents 0] 
    --,A.[Update]=A.[Update]+1
    FROM    @ColumnNameAndData A
            INNER JOIN @ModifiedRawData B ON CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING([hex_value],
                                                              9, 4)))) = [PAGE IDS]
                                             AND CONVERT(INT, SUBSTRING([hex_value],
                                                              3, 2)) = [Link ID]
    WHERE   [System_Type_Id] IN ( 35, 34, 99 )
            AND [Link ID] <> 0 
     
    UPDATE  @ColumnNameAndData
    SET     [hex_Value] = [RowLog Contents 0]
    --,A.[Update]=A.[Update]+10
    FROM    @ColumnNameAndData A
            INNER JOIN @ModifiedRawData B ON CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING([hex_value],
                                                              9, 4)))) = [PAGE IDS]
    WHERE   [System_Type_Id] IN ( 35, 34, 99 )
            AND [Link ID] = 0
 
    UPDATE  @ColumnNameAndData
    SET     [hex_Value] = [RowLog Contents 0] 
    --,A.[Update]=A.[Update]+1
    FROM    @ColumnNameAndData A
            INNER JOIN @ModifiedRawData B ON CONVERT(INT, CONVERT(VARBINARY(MAX), REVERSE(SUBSTRING([hex_value],
                                                              15, 4)))) = [PAGE IDS]
    WHERE   [System_Type_Id] IN ( 35, 34, 99 )
            AND [Link ID] = 0
 
    UPDATE  @ColumnNameAndData
    SET     [hex_value] = 0xFFFE + SUBSTRING([hex_value], 9, LEN([hex_value]))
    --,[Update]=[Update]+1
    WHERE   [system_type_id] = 241
 
    CREATE TABLE [#temp_Data]
        (
          [FieldName] VARCHAR(MAX) ,
          [FieldValue] NVARCHAR(MAX) ,
          [Rowlogcontents] VARBINARY(8000) ,
          [Row ID] INT
        )
 
    INSERT  INTO #temp_Data
            SELECT  NAME ,
                    CASE WHEN system_type_id IN ( 231, 239 )
                         THEN LTRIM(RTRIM(CONVERT(NVARCHAR(MAX), hex_Value)))  --NVARCHAR ,NCHAR
                         WHEN system_type_id IN ( 167, 175 )
                         THEN LTRIM(RTRIM(CONVERT(VARCHAR(MAX), hex_Value)))  --VARCHAR,CHAR
                         WHEN system_type_id IN ( 35 )
                         THEN LTRIM(RTRIM(CONVERT(VARCHAR(MAX), hex_Value))) --Text
                         WHEN system_type_id IN ( 99 )
                         THEN LTRIM(RTRIM(CONVERT(NVARCHAR(MAX), hex_Value))) --nText 
                         WHEN system_type_id = 48
                         THEN CONVERT(VARCHAR(MAX), CONVERT(TINYINT, CONVERT(BINARY(1), REVERSE(hex_Value)))) --TINY INTEGER
                         WHEN system_type_id = 52
                         THEN CONVERT(VARCHAR(MAX), CONVERT(SMALLINT, CONVERT(BINARY(2), REVERSE(hex_Value)))) --SMALL INTEGER
                         WHEN system_type_id = 56
                         THEN CONVERT(VARCHAR(MAX), CONVERT(INT, CONVERT(BINARY(4), REVERSE(hex_Value)))) -- INTEGER
                         WHEN system_type_id = 127
                         THEN CONVERT(VARCHAR(MAX), CONVERT(BIGINT, CONVERT(BINARY(8), REVERSE(hex_Value))))-- BIG INTEGER
                         WHEN system_type_id = 61
                         THEN CONVERT(VARCHAR(MAX), CONVERT(DATETIME, CONVERT(VARBINARY(8000), REVERSE(hex_Value))), 100) --DATETIME
                         WHEN system_type_id = 58
                         THEN CONVERT(VARCHAR(MAX), CONVERT(SMALLDATETIME, CONVERT(VARBINARY(8000), REVERSE(hex_Value))), 100) --SMALL DATETIME
                         WHEN system_type_id = 108
                         THEN CONVERT(VARCHAR(MAX), CONVERT(NUMERIC(38, 20), CONVERT(VARBINARY, CONVERT(VARBINARY(1), xprec)
                              + CONVERT(VARBINARY(1), xscale))
                              + CONVERT(VARBINARY(1), 0) + hex_Value)) --- NUMERIC
                         WHEN system_type_id = 106
                         THEN CONVERT(VARCHAR(MAX), CONVERT(DECIMAL(38, 20), CONVERT(VARBINARY, CONVERT(VARBINARY(1), xprec)
                              + CONVERT(VARBINARY(1), xscale))
                              + CONVERT(VARBINARY(1), 0) + hex_Value)) --- DECIMAL
                         WHEN system_type_id IN ( 60, 122 )
                         THEN CONVERT(VARCHAR(MAX), CONVERT(MONEY, CONVERT(VARBINARY(8000), REVERSE(hex_Value))), 2) --MONEY,SMALLMONEY
                         WHEN system_type_id = 104
                         THEN CONVERT(VARCHAR(MAX), CONVERT (BIT, CONVERT(BINARY(1), hex_Value)
                              % 2))  -- BIT
                         WHEN system_type_id = 62
                         THEN RTRIM(LTRIM(STR(CONVERT(FLOAT, SIGN(CAST(CONVERT(VARBINARY(8000), REVERSE(hex_Value)) AS BIGINT))
                                              * ( 1.0
                                                  + ( CAST(CONVERT(VARBINARY(8000), REVERSE(hex_Value)) AS BIGINT)
                                                      & 0x000FFFFFFFFFFFFF )
                                                  * POWER(CAST(2 AS FLOAT),
                                                          -52) )
                                              * POWER(CAST(2 AS FLOAT),
                                                      ( ( CAST(CONVERT(VARBINARY(8000), REVERSE(hex_Value)) AS BIGINT)
                                                          & 0x7ff0000000000000 )
                                                        / EXP(52 * LOG(2))
                                                        - 1023 ))), 53,
                                              LEN(hex_Value)))) --- FLOAT
                         WHEN system_type_id = 59
                         THEN LEFT(LTRIM(STR(CAST(SIGN(CAST(CONVERT(VARBINARY(8000), REVERSE(hex_Value)) AS BIGINT))
                                             * ( 1.0
                                                 + ( CAST(CONVERT(VARBINARY(8000), REVERSE(hex_Value)) AS BIGINT)
                                                     & 0x007FFFFF )
                                                 * POWER(CAST(2 AS REAL), -23) )
                                             * POWER(CAST(2 AS REAL),
                                                     ( ( ( CAST(CONVERT(VARBINARY(8000), REVERSE(hex_Value)) AS INT) )
                                                         & 0x7f800000 )
                                                       / EXP(23 * LOG(2))
                                                       - 127 )) AS REAL), 23,
                                             23)), 8) --Real
                         WHEN system_type_id IN ( 165, 173 )
                         THEN ( CASE WHEN CHARINDEX(0x,
                                                    CAST('' AS XML).value('xs:hexBinary(sql:column("hex_Value"))',
                                                              'VARBINARY(8000)')) = 0
                                     THEN '0x'
                                     ELSE ''
                                END ) + CAST('' AS XML).value('xs:hexBinary(sql:column("hex_Value"))',
                                                              'varchar(max)') -- BINARY,VARBINARY
                         WHEN system_type_id = 34
                         THEN ( CASE WHEN CHARINDEX(0x,
                                                    CAST('' AS XML).value('xs:hexBinary(sql:column("hex_Value"))',
                                                              'VARBINARY(8000)')) = 0
                                     THEN '0x'
                                     ELSE ''
                                END ) + CAST('' AS XML).value('xs:hexBinary(sql:column("hex_Value"))',
                                                              'varchar(max)')  --IMAGE
                         WHEN system_type_id = 36
                         THEN CONVERT(VARCHAR(MAX), CONVERT(UNIQUEIDENTIFIER, hex_Value)) --UNIQUEIDENTIFIER
                         WHEN system_type_id = 231
                         THEN CONVERT(VARCHAR(MAX), CONVERT(SYSNAME, hex_Value)) --SYSNAME
                         WHEN system_type_id = 241
                         THEN CONVERT(VARCHAR(MAX), CONVERT(XML, hex_Value)) --XML
                         WHEN system_type_id = 189
                         THEN ( CASE WHEN CHARINDEX(0x,
                                                    CAST('' AS XML).value('xs:hexBinary(sql:column("hex_Value"))',
                                                              'VARBINARY(8000)')) = 0
                                     THEN '0x'
                                     ELSE ''
                                END ) + CAST('' AS XML).value('xs:hexBinary(sql:column("hex_Value"))',
                                                              'varchar(max)') --TIMESTAMP
                         WHEN system_type_id = 98
                         THEN ( CASE WHEN CONVERT(INT, SUBSTRING(hex_Value, 1,
                                                              1)) = 56
                                     THEN CONVERT(VARCHAR(MAX), CONVERT(INT, CONVERT(BINARY(4), REVERSE(SUBSTRING(hex_Value,
                                                              3,
                                                              LEN(hex_Value))))))  -- INTEGER
                                     WHEN CONVERT(INT, SUBSTRING(hex_Value, 1,
                                                              1)) = 108
                                     THEN CONVERT(VARCHAR(MAX), CONVERT(NUMERIC(38,
                                                              20), CONVERT(VARBINARY(1), SUBSTRING(hex_Value,
                                                              3, 1))
                                          + CONVERT(VARBINARY(1), SUBSTRING(hex_Value,
                                                              4, 1))
                                          + CONVERT(VARBINARY(1), 0)
                                          + SUBSTRING(hex_Value, 5,
                                                      LEN(hex_Value)))) --- NUMERIC
                                     WHEN CONVERT(INT, SUBSTRING(hex_Value, 1,
                                                              1)) = 167
                                     THEN LTRIM(RTRIM(CONVERT(VARCHAR(MAX), SUBSTRING(hex_Value,
                                                              9,
                                                              LEN(hex_Value))))) --VARCHAR,CHAR
                                     WHEN CONVERT(INT, SUBSTRING(hex_Value, 1,
                                                              1)) = 36
                                     THEN CONVERT(VARCHAR(MAX), CONVERT(UNIQUEIDENTIFIER, SUBSTRING(( hex_Value ),
                                                              3, 20))) --UNIQUEIDENTIFIER
                                     WHEN CONVERT(INT, SUBSTRING(hex_Value, 1,
                                                              1)) = 61
                                     THEN CONVERT(VARCHAR(MAX), CONVERT(DATETIME, CONVERT(VARBINARY(8000), REVERSE(SUBSTRING(hex_Value,
                                                              3,
                                                              LEN(hex_Value))))), 100) --DATETIME
                                     WHEN CONVERT(INT, SUBSTRING(hex_Value, 1,
                                                              1)) = 165
                                     THEN '0x'
                                          + SUBSTRING(( CASE WHEN CHARINDEX(0x,
                                                              CAST('' AS XML).value('xs:hexBinary(sql:column("hex_Value"))',
                                                              'VARBINARY(8000)')) = 0
                                                             THEN '0x'
                                                             ELSE ''
                                                        END )
                                                      + CAST('' AS XML).value('xs:hexBinary(sql:column("hex_Value"))',
                                                              'varchar(max)'),
                                                      11, LEN(hex_Value)) -- BINARY,VARBINARY
                                END )
                    END AS FieldValue ,
                    [Rowlogcontents] ,
                    [Row ID]
            FROM    @ColumnNameAndData
            ORDER BY nullbit
 
--Create the column name in the same order to do pivot table.
 
    DECLARE @FieldName VARCHAR(MAX)
    SET @FieldName = STUFF(( SELECT ','
                                    + CAST(QUOTENAME([Name]) AS VARCHAR(MAX))
                             FROM   syscolumns
                             WHERE  id = OBJECT_ID(''
                                                   + @SchemaName_n_TableName
                                                   + '')
                           FOR
                             XML PATH('')
                           ), 1, 1, '')
 
--Finally did pivot table and get the data back in the same format.
 
    SET @sql = 'SELECT ' + @FieldName
        + ' FROM #temp_Data PIVOT (Min([FieldValue]) FOR FieldName IN ('
        + @FieldName + ')) AS pvt'
    EXEC sp_executesql @sql
 
GO