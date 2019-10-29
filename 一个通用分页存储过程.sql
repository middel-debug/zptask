
-- =============================================
-- Author:        <PatrickLiu>
-- Create date: <2018-4-16 14:21>
-- Description:    <通用的数据分页存储过程>
-- =============================================
 create PROCEDURE [dbo].[usp_CommonDataResourcePaged]
(
    @TableName          nvarchar(200),           ----要显示的表或多个表的连接
    @FieldList          nvarchar(1500) = '*',    ----要显示的字段列表
    @PageSize           int = 20,                ----每页显示的记录个数
    @PageNumber         int = 1,                 ----要显示那一页的记录
    @SortFields         nvarchar(1000) = null,   ----排序字段列表或条件
    @EnabledSort        bit = 0,                 ----排序方法，0为升序，1为降序(如果是多字段排列Sort指代最后一个排序字段的排列顺序(最后一个排序字段不加排序标记)--程序传参如：' SortA Asc,SortB Desc,SortC ')
    @QueryCondition     nvarchar(1500) = null,   ----查询条件,不需WHERE
    @Primarykey         nvarchar(50),            ----主表的主键
    @EnabledDistinct    bit = 0,                 ----是否添加查询字段的 DISTINCT 默认0不添加/1添加
    @PageCount          int = 1 output,          ----查询结果分页后的总页数
    @RecordCount        int = 1 output           ----查询到的记录数
)
AS
    SET NOCOUNT ON
    Declare @SqlResult nvarchar(1000)        ----存放动态生成的SQL语句
    Declare @SqlTotalCount nvarchar(1000)        ----存放取得查询结果总数的查询语句
    Declare @SqlStartOrEndID     nvarchar(1000)        ----存放取得查询开头或结尾ID的查询语句
    
    Declare @SortTypeA nvarchar(10)    ----数据排序规则A
    Declare @SortTypeB nvarchar(10)    ----数据排序规则B
    
    Declare @SqlDistinct nvarchar(50)         ----对含有DISTINCT的查询进行SQL构造
    Declare @SqlCountDistinct nvarchar(50)          ----对含有DISTINCT的总数查询进行SQL构造
    
    declare @timediff datetime  --耗时测试时间差
    SELECT @timediff=getdate()
    
    if @EnabledDistinct  = 0
        begin
            set @SqlDistinct = 'SELECT '
            set @SqlCountDistinct = 'Count(*)'
        end
    else
        begin
            set @SqlDistinct = 'SELECT DISTINCT '
            set @SqlCountDistinct = 'Count(DISTINCT '+@Primarykey+')'
        end
    
    if @EnabledSort=0
        begin
            set @SortTypeB=' ASC '
            set @SortTypeA=' DESC '
        end
    else
        begin
            set @SortTypeB=' DESC '
            set @SortTypeA=' ASC '
        end
    
    --------生成查询语句--------
    --此处@SqlTotalCount为取得查询结果数量的语句
    if @QueryCondition is null or @QueryCondition=''     --没有设置显示条件
        begin
            set @SqlResult =  @FieldList + ' From ' + @TableName
            set @SqlTotalCount = @SqlDistinct+' @RecordCount='+@SqlCountDistinct+' FROM '+@TableName
            set @SqlStartOrEndID = ' From ' + @TableName
        end
    else
        begin
            set @SqlResult = + @FieldList + ' From ' + @TableName + ' WHERE (1>0) and ' + @QueryCondition
            set @SqlTotalCount = @SqlDistinct+' @RecordCount='+@SqlCountDistinct+' FROM '+@TableName + ' WHERE (1>0) and ' + @QueryCondition
            set @SqlStartOrEndID = ' From ' + @TableName + ' WHERE (1>0) and ' + @QueryCondition
        end
    
    ----取得查询结果总数量-----
    exec sp_executesql @SqlTotalCount,N'@RecordCount int out ',@RecordCount out

    declare @TemporaryCount int --临时统计
    if @RecordCount = 0
        set @TemporaryCount = 1
    else
        set @TemporaryCount = @RecordCount
    
        --取得分页总数
        set @PageCount=(@TemporaryCount+@PageSize-1)/@PageSize
    
        /**当前页大于总页数 取最后一页**/
        if @PageNumber>@PageCount
            set @PageNumber=@PageCount
    
        --/*-----数据分页2分处理-------*/
        declare @pageIndex int --总数/页大小
        declare @lastcount int --总数%页大小 
    
        set @pageIndex = @TemporaryCount/@PageSize
        set @lastcount = @TemporaryCount%@PageSize
        if @lastcount > 0
            set @pageIndex = @pageIndex + 1
        else
            set @lastcount = @pagesize
    
        --//***显示分页
        if @QueryCondition is null or @QueryCondition=''     --没有设置显示条件
        begin
            if @pageIndex<2 or @PageNumber<=@pageIndex / 2 + @pageIndex % 2   --前半部分数据处理
                begin 
                    if @PageNumber=1
                        set @SqlTotalCount=@SqlDistinct+' TOP '+ CAST(@PageSize as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName+' ORDER BY '+ @SortFields +' '+ @SortTypeB
                    else
                    begin
                        if @EnabledSort=1
                        begin                    
                        set @SqlTotalCount=@SqlDistinct+' TOP '+ CAST(@PageSize as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName
                            +' WHERE '+@Primarykey+' <(SELECT MIN('+ @Primarykey +') FROM ('+ @SqlDistinct+' TOP '+ CAST(@PageSize*(@PageNumber-1) as Varchar(20)) +' '+ @Primarykey +' FROM '+@TableName
                            +' ORDER BY '+ @SortFields +' '+ @SortTypeB+') AS TBMinID)'+' ORDER BY '+ @SortFields +' '+ @SortTypeB
                        end
                        else
                        begin
                        set @SqlTotalCount=@SqlDistinct+' TOP '+ CAST(@PageSize as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName
                            +' WHERE '+@Primarykey+' >(SELECT MAX('+ @Primarykey +') FROM ('+ @SqlDistinct+' TOP '+ CAST(@PageSize*(@PageNumber-1) as Varchar(20)) +' '+ @Primarykey +' FROM '+@TableName
                            +' ORDER BY '+ @SortFields +' '+ @SortTypeB+') AS TBMinID)'+' ORDER BY '+ @SortFields +' '+ @SortTypeB 
                        end
                    end    
                end
            else
                begin
                set @PageNumber = @pageIndex-@PageNumber+1 --后半部分数据处理
                    if @PageNumber <= 1 --最后一页数据显示                
                        set @SqlTotalCount=@SqlDistinct+' * FROM ('+@SqlDistinct+' TOP '+ CAST(@lastcount as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName
                            +' ORDER BY '+ @SortFields +' '+ @SortTypeA+') AS TempTB'+' ORDER BY '+ @SortFields +' '+ @SortTypeB 
                    else
                        if @EnabledSort=1
                        begin
                        set @SqlTotalCount=@SqlDistinct+' * FROM ('+@SqlDistinct+' TOP '+ CAST(@PageSize as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName
                            +' WHERE '+@Primarykey+' >(SELECT MAX('+ @Primarykey +') FROM('+ @SqlDistinct+' TOP '+ CAST(@PageSize*(@PageNumber-2)+@lastcount as Varchar(20)) +' '+ @Primarykey +' FROM '+@TableName
                            +' ORDER BY '+ @SortFields +' '+ @SortTypeA+') AS TBMaxID)'
                            +' ORDER BY '+ @SortFields +' '+ @SortTypeA+') AS TempTB'+' ORDER BY '+ @SortFields +' '+ @SortTypeB
                        end
                        else
                        begin
                        set @SqlTotalCount=@SqlDistinct+' * FROM ('+@SqlDistinct+' TOP '+ CAST(@PageSize as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName
                            +' WHERE '+@Primarykey+' <(SELECT MIN('+ @Primarykey +') FROM('+ @SqlDistinct+' TOP '+ CAST(@PageSize*(@PageNumber-2)+@lastcount as Varchar(20)) +' '+ @Primarykey +' FROM '+@TableName
                            +' ORDER BY '+ @SortFields +' '+ @SortTypeA+') AS TBMaxID)'
                            +' ORDER BY '+ @SortFields +' '+ @SortTypeA+') AS TempTB'+' ORDER BY '+ @SortFields +' '+ @SortTypeB 
                        end
                end
        end
    
        else --有查询条件
        begin
            if @pageIndex<2 or @PageNumber<=@pageIndex / 2 + @pageIndex % 2   --前半部分数据处理
            begin
                    if @PageNumber=1
                        set @SqlTotalCount=@SqlDistinct+' TOP '+ CAST(@PageSize as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName                        
                            +' WHERE 1=1 and ' + @QueryCondition + ' ORDER BY '+ @SortFields +' '+ @SortTypeB
                    else if(@EnabledSort=1)
                    begin                    
                        set @SqlTotalCount=@SqlDistinct+' TOP '+ CAST(@PageSize as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName
                            +' WHERE '+@Primarykey+' <(SELECT MIN('+ @Primarykey +') FROM ('+ @SqlDistinct+' TOP '+ CAST(@PageSize*(@PageNumber-1) as Varchar(20)) +' '+ @Primarykey +' FROM '+@TableName
                            +' WHERE (1=1) and ' + @QueryCondition +' ORDER BY '+ @SortFields +' '+ @SortTypeB+') AS TBMinID)'+' ORDER BY '+ @SortFields +' '+ @SortTypeB
                    end
                    else
                    begin
                        set @SqlTotalCount=@SqlDistinct+' TOP '+ CAST(@PageSize as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName
                            +' WHERE '+@Primarykey+' >(SELECT MAX('+ @Primarykey +') FROM ('+ @SqlDistinct+' TOP '+ CAST(@PageSize*(@PageNumber-1) as Varchar(20)) +' '+ @Primarykey +' FROM '+@TableName
                            +' WHERE (1=1) and ' + @QueryCondition +' ORDER BY '+ @SortFields +' '+ @SortTypeB+') AS TBMinID)'+' ORDER BY '+ @SortFields +' '+ @SortTypeB 
                    end           
            end
            else
            begin 
                set @PageNumber = @pageIndex-@PageNumber+1 --后半部分数据处理
                if @PageNumber <= 1 --最后一页数据显示
                        set @SqlTotalCount=@SqlDistinct+' * FROM ('+@SqlDistinct+' TOP '+ CAST(@lastcount as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName
                            +' WHERE (1=1) and '+ @QueryCondition +' ORDER BY '+ @SortFields +' '+ @SortTypeA+') AS TempTB'+' ORDER BY '+ @SortFields +' '+ @SortTypeB                     
                else if(@EnabledSort=1)
                        set @SqlTotalCount=@SqlDistinct+' * FROM ('+@SqlDistinct+' TOP '+ CAST(@PageSize as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName
                            +' WHERE '+@Primarykey+' >(SELECT MAX('+ @Primarykey +') FROM('+ @SqlDistinct+' TOP '+ CAST(@PageSize*(@PageNumber-2)+@lastcount as Varchar(20)) +' '+ @Primarykey +' FROM '+@TableName
                            +' WHERE (1=1) and '+ @QueryCondition +' ORDER BY '+ @SortFields +' '+ @SortTypeA+') AS TBMaxID)'+' ORDER BY '+ @SortFields +' '+ @SortTypeA+') AS TempTB'+' ORDER BY '+ @SortFields +' '+ @SortTypeB    
                else
                        set @SqlTotalCount=@SqlDistinct+' * FROM ('+@SqlDistinct+' TOP '+ CAST(@PageSize as VARCHAR(4))+' '+ @FieldList+' FROM '+@TableName
                            +' WHERE '+@Primarykey+' <(SELECT MIN('+ @Primarykey +') FROM('+ @SqlDistinct+' TOP '+ CAST(@PageSize*(@PageNumber-2)+@lastcount as Varchar(20)) +' '+ @Primarykey +' FROM '+@TableName
                            +' WHERE (1=1) and '+ @QueryCondition +' ORDER BY '+ @SortFields +' '+ @SortTypeA+') AS TBMaxID)'+' ORDER BY '+ @SortFields +' '+ @SortTypeA+') AS TempTB'+' ORDER BY '+ @SortFields +' '+ @SortTypeB            
            end    
        end
    
    ------返回查询结果-----
    exec sp_executesql @SqlTotalCount
    --SELECT datediff(ms,@timediff,getdate()) as 耗时
    print @SqlTotalCount
    SET NOCOUNT OFF



	---------------------------------------------调用存储过程asp.ent
	DECLARE @return_value int,   @PageCount int,   @RecordCount int

SELECT @PageCount = 0 SELECT @RecordCount = 0

EXEC @return_value = [dbo].[usp_CommonDataResourcePaged]   
   @TableName = N'[dbo].[Student]',   
@FieldList = N'[StudentID],[Number],[Name],[ClassID]',   
@PageSize = 30,  
@PageNumber = 50,   
@SortFields = [StudentID],   
@EnabledSort =N'1' ,   
@QueryCondition = N'',   
@Primarykey = N'[StudentID]',  
@EnabledDistinct = 1,   
@PageCount = @PageCount OUTPUT,   
@RecordCount = @RecordCount OUTPUT

SELECT @PageCount as N'@PageCount',   @RecordCount as N'@RecordCount'

SELECT 'Return Value' = @return_value
GO
-----------------------------------------------------
/// <summary>
        /// linq to  ef 调用分页存储过程
        /// </summary>
        /// <param name="num"></param>
        public void loada(int num)
        {
            var param = new List<SqlParameter>();
            //定义数组接收存储过程参数
            param.Add(new SqlParameter("@TableName","Student"));       //表名
            param.Add(new SqlParameter("@FieldList","StudentID,Number,Name,ClassID"));//显示字段
            param.Add(new SqlParameter("@PageSize",10));                       //显示条数
            param.Add(new SqlParameter("@SortFields","StudentID"));           //排序字段
            param.Add(new SqlParameter("@PageNumber",num));                   //显示那一页（分页传参）
            param.Add(new SqlParameter("@EnabledSort",1));                    //0为升序，1为降序
            param.Add(new SqlParameter("@QueryCondition", ""));               //where条件
            param.Add(new SqlParameter("@Primarykey","StudentID"));          //主键（代表唯一）
            param.Add(new SqlParameter("@EnabledDistinct",1));               //是否添加查询字段的 DISTINCT 默认0不添加/1添加
            param.Add(new SqlParameter("@PageCount",SqlDbType.Int));         //总页数
            param.Add(new SqlParameter("@RecordCount",SqlDbType.Int));       //记录数
            //输出参数指定参数类型

            param[9].Direction = ParameterDirection.Output;
            param[10].Direction = ParameterDirection.Output;
         
            var dt = db.Database.SqlQuery<Student>("exec usp_CommonDataResourcePaged  @TableName,@FieldList,@PageSize,@PageNumber,@SortFields,@EnabledSort,@QueryCondition,@Primarykey,@EnabledDistinct,@PageCount output,@RecordCount output", param.ToArray()).ToList();

            int RecordCount = Convert.ToInt32(param[9].Value);
            int PageCount = Convert.ToInt32(param[10].Value);
            lbl_info.Text = "当前第"+ RecordCount + "页,共"+ PageCount + "页";
            userinfo.DataSource = dt;   
            userinfo.DataBind();

       

        }