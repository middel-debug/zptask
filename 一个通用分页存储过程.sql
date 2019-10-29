
-- =============================================
-- Author:        <PatrickLiu>
-- Create date: <2018-4-16 14:21>
-- Description:    <ͨ�õ����ݷ�ҳ�洢����>
-- =============================================
 create PROCEDURE [dbo].[usp_CommonDataResourcePaged]
(
    @TableName          nvarchar(200),           ----Ҫ��ʾ�ı�����������
    @FieldList          nvarchar(1500) = '*',    ----Ҫ��ʾ���ֶ��б�
    @PageSize           int = 20,                ----ÿҳ��ʾ�ļ�¼����
    @PageNumber         int = 1,                 ----Ҫ��ʾ��һҳ�ļ�¼
    @SortFields         nvarchar(1000) = null,   ----�����ֶ��б������
    @EnabledSort        bit = 0,                 ----���򷽷���0Ϊ����1Ϊ����(����Ƕ��ֶ�����Sortָ�����һ�������ֶε�����˳��(���һ�������ֶβ���������)--���򴫲��磺' SortA Asc,SortB Desc,SortC ')
    @QueryCondition     nvarchar(1500) = null,   ----��ѯ����,����WHERE
    @Primarykey         nvarchar(50),            ----���������
    @EnabledDistinct    bit = 0,                 ----�Ƿ���Ӳ�ѯ�ֶε� DISTINCT Ĭ��0�����/1���
    @PageCount          int = 1 output,          ----��ѯ�����ҳ�����ҳ��
    @RecordCount        int = 1 output           ----��ѯ���ļ�¼��
)
AS
    SET NOCOUNT ON
    Declare @SqlResult nvarchar(1000)        ----��Ŷ�̬���ɵ�SQL���
    Declare @SqlTotalCount nvarchar(1000)        ----���ȡ�ò�ѯ��������Ĳ�ѯ���
    Declare @SqlStartOrEndID     nvarchar(1000)        ----���ȡ�ò�ѯ��ͷ���βID�Ĳ�ѯ���
    
    Declare @SortTypeA nvarchar(10)    ----�����������A
    Declare @SortTypeB nvarchar(10)    ----�����������B
    
    Declare @SqlDistinct nvarchar(50)         ----�Ժ���DISTINCT�Ĳ�ѯ����SQL����
    Declare @SqlCountDistinct nvarchar(50)          ----�Ժ���DISTINCT��������ѯ����SQL����
    
    declare @timediff datetime  --��ʱ����ʱ���
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
    
    --------���ɲ�ѯ���--------
    --�˴�@SqlTotalCountΪȡ�ò�ѯ������������
    if @QueryCondition is null or @QueryCondition=''     --û��������ʾ����
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
    
    ----ȡ�ò�ѯ���������-----
    exec sp_executesql @SqlTotalCount,N'@RecordCount int out ',@RecordCount out

    declare @TemporaryCount int --��ʱͳ��
    if @RecordCount = 0
        set @TemporaryCount = 1
    else
        set @TemporaryCount = @RecordCount
    
        --ȡ�÷�ҳ����
        set @PageCount=(@TemporaryCount+@PageSize-1)/@PageSize
    
        /**��ǰҳ������ҳ�� ȡ���һҳ**/
        if @PageNumber>@PageCount
            set @PageNumber=@PageCount
    
        --/*-----���ݷ�ҳ2�ִ���-------*/
        declare @pageIndex int --����/ҳ��С
        declare @lastcount int --����%ҳ��С 
    
        set @pageIndex = @TemporaryCount/@PageSize
        set @lastcount = @TemporaryCount%@PageSize
        if @lastcount > 0
            set @pageIndex = @pageIndex + 1
        else
            set @lastcount = @pagesize
    
        --//***��ʾ��ҳ
        if @QueryCondition is null or @QueryCondition=''     --û��������ʾ����
        begin
            if @pageIndex<2 or @PageNumber<=@pageIndex / 2 + @pageIndex % 2   --ǰ�벿�����ݴ���
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
                set @PageNumber = @pageIndex-@PageNumber+1 --��벿�����ݴ���
                    if @PageNumber <= 1 --���һҳ������ʾ                
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
    
        else --�в�ѯ����
        begin
            if @pageIndex<2 or @PageNumber<=@pageIndex / 2 + @pageIndex % 2   --ǰ�벿�����ݴ���
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
                set @PageNumber = @pageIndex-@PageNumber+1 --��벿�����ݴ���
                if @PageNumber <= 1 --���һҳ������ʾ
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
    
    ------���ز�ѯ���-----
    exec sp_executesql @SqlTotalCount
    --SELECT datediff(ms,@timediff,getdate()) as ��ʱ
    print @SqlTotalCount
    SET NOCOUNT OFF



	---------------------------------------------���ô洢����asp.ent
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
        /// linq to  ef ���÷�ҳ�洢����
        /// </summary>
        /// <param name="num"></param>
        public void loada(int num)
        {
            var param = new List<SqlParameter>();
            //����������մ洢���̲���
            param.Add(new SqlParameter("@TableName","Student"));       //����
            param.Add(new SqlParameter("@FieldList","StudentID,Number,Name,ClassID"));//��ʾ�ֶ�
            param.Add(new SqlParameter("@PageSize",10));                       //��ʾ����
            param.Add(new SqlParameter("@SortFields","StudentID"));           //�����ֶ�
            param.Add(new SqlParameter("@PageNumber",num));                   //��ʾ��һҳ����ҳ���Σ�
            param.Add(new SqlParameter("@EnabledSort",1));                    //0Ϊ����1Ϊ����
            param.Add(new SqlParameter("@QueryCondition", ""));               //where����
            param.Add(new SqlParameter("@Primarykey","StudentID"));          //����������Ψһ��
            param.Add(new SqlParameter("@EnabledDistinct",1));               //�Ƿ���Ӳ�ѯ�ֶε� DISTINCT Ĭ��0�����/1���
            param.Add(new SqlParameter("@PageCount",SqlDbType.Int));         //��ҳ��
            param.Add(new SqlParameter("@RecordCount",SqlDbType.Int));       //��¼��
            //�������ָ����������

            param[9].Direction = ParameterDirection.Output;
            param[10].Direction = ParameterDirection.Output;
         
            var dt = db.Database.SqlQuery<Student>("exec usp_CommonDataResourcePaged  @TableName,@FieldList,@PageSize,@PageNumber,@SortFields,@EnabledSort,@QueryCondition,@Primarykey,@EnabledDistinct,@PageCount output,@RecordCount output", param.ToArray()).ToList();

            int RecordCount = Convert.ToInt32(param[9].Value);
            int PageCount = Convert.ToInt32(param[10].Value);
            lbl_info.Text = "��ǰ��"+ RecordCount + "ҳ,��"+ PageCount + "ҳ";
            userinfo.DataSource = dt;   
            userinfo.DataBind();

       

        }