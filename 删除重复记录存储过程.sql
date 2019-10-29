SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:      Insus.NET
-- Blog:        https://insus.cnblogs.com
-- Create date: 2019-05-31
-- Update date: 2019-05-31
-- Description: 删除多个重复记录
-- =============================================
CREATE PROCEDURE [dbo].[usp_Delete_Multiple_Duplicate_Record] (
    @TABLE_NAME SYSNAME, 
    @Refer_Column_lists NVARCHAR(MAX) -- '[a],[b],[c]'
)    
AS
BEGIN    
    DECLARE @query NVARCHAR(MAX) = N'
    ;WITH cte_temp_table(rank_num,'+ @Refer_Column_lists +')
    AS (
       SELECT ROW_NUMBER() OVER(PARTITION BY '+ @Refer_Column_lists +' ORDER BY '+ @Refer_Column_lists +') AS rank_num, '+ @Refer_Column_lists +'
       FROM '+ @TABLE_NAME +'
    )
    DELETE FROM cte_temp_table WHERE rank_num > 1;
    '

    EXECUTE sp_executeSql @query
END



-------------
IF OBJECT_ID('tempdb.dbo.#Part') IS NOT NULL DROP TABLE #Part

CREATE TABLE #Part (
    [ID] INT,
    [Item] NVARCHAR(40)
)
GO
INSERT INTO #Part ([ID],[Item]) VALUES 
(23394,'I32-GG443-QT0098-0001'),
(45008,'I38-AA321-WS0098-0506'),
(14350,'K38-12321-5456UD-3493'),
(64582,'872-RTDE3-Q459PW-2323'),
(23545,'098-SSSS1-WS0098-5526'),
(80075,'B78-F1H2Y-5456UD-2530'),
(53567,'PO0-7G7G7-JJY098-0077'),
(44349,'54F-ART43-6545NN-2514'),
(36574,'X3C-SDEWE-3ER808-8764'),
(36574,'RVC-43ASE-H43QWW-9753'),
(14350,'K38-12321-5456UD-3493'),
(64582,'872-RTDE3-Q459PW-2323'),
(80075,'B78-F1H2Y-5456UD-2530'),
(53567,'PO0-7G7G7-JJY098-0077'),
(44349,'54F-ART43-6545NN-2514'),
(44349,'54F-ART43-6545NN-2514'),
(36574,'X3C-SDEWE-3ER808-8764')
GO


EXECUTE [dbo].[usp_Delete_Multiple_Duplicate_Record] #Part,'[ID],[Item]'

SELECT * FROM #Part