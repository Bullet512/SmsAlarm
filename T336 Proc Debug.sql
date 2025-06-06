USE [CTRL]
GO
/****** Object:  StoredProcedure [Prl].[usp_prl_DailyPTCVPCReconcilationReport_RTDC]    Script Date: 5/15/2025 9:00:46 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- [Prl].[usp_prl_DailyPTCVPCReconcilationReport_RTDC] @TestInd = 1
ALTER PROCEDURE [Prl].[usp_prl_DailyPTCVPCReconcilationReport_RTDC]
@TestInd BIT = 1
AS
BEGIN
SELECT GETDATE()
	--DECLARE @TestInd BIT = 1

	DECLARE @Today DATE = GETDATE()
	DECLARE @PlazaName VARCHAR(50)

	DECLARE @StartDate DATETIME
	DECLARE @EndDate DATETIME

	DECLARE @PTC_TRANS_START_DATE DATETIME

	SELECT TOP (1)
		@PTC_TRANS_START_DATE = ParamValue
	FROM 
		ICD.Prl.ICDParam (NOLOCK)
	WHERE 
		ParamName = 'PTC_TRANS_START_DATE'

	SET @PTC_TRANS_START_DATE = ISNULL(@PTC_TRANS_START_DATE, '2023-06-14 05:00')

	DECLARE @AppSvcIPAddress VARCHAR(20)

	DECLARE @Body NVARCHAR(MAX) = '<html><style> td {border: solid black 1px;padding-left:5px;padding-right:5px;padding-top:1px;padding-bottom:1px;font-size:11pt;text-align: right;} </style><body>' 
	DECLARE @xml NVARCHAR(MAX);
	DECLARE @Subject VARCHAR(255);
	DECLARE @Recipients VARCHAR(MAX) = 'InfinityAlerts@paturnpike.com;mkapp@paturnpike.com;Milan.Mitrovich@TransCore.com;casey.martin@transcore.com;jakai.cobb@transcore.com;krishna.bhattarai@transcore.com;Jeff.Falk@TransCore.com;PTC-INF-Techs@transcore.com;'
	--set @Recipients = 'raymond.cloak@transcore.com'

	--SET @Recipients= 'InfinityAlerts@paturnpike.com;Milan.Mitrovich@TransCore.com;Matthew.Nalesnik@transcore.com;raymond.cloak@transcore.com;'

	DECLARE @PTCProcessFolder VARCHAR(255) --= '\\10.152.137.34\d$\sftp-root\CSCData\TransactionFileData\Processed\'

	SELECT TOP (1) 
		 @PTCProcessFolder = '\\' + MachineIP + '\d$\InfinityData\TXN\Processed\'		
	FROM 
		OPS.dbo.tblMachines (NOLOCK)
	WHERE 
		MachineTypeID = 3
		AND IsActive = 1		

	SELECT TOP (1)
		@PlazaName = OrgName
	FROM 
		OPS.dbo.tblOrg (NOLOCK)
	WHERE 
		IsActive = 1

	DECLARE @TollDate TABLE(
		TollDate DATE,
		TollDateTransactionFilename VARCHAR (255),
		TollStartDate DATETIME,
		TollEndDate DATETIME
	);

	DECLARE @TransactionFiles TABLE (
		Filename VARCHAR(100) UNIQUE,
		TransactionFileDate DATE
	)

	DECLARE @outTransactionFileStatus TABLE (
		TollDate DATE,
		TollDateTransactionFilename VARCHAR (255),
		TollDateFileStatus VARCHAR(100)
	)

	DECLARE @outTransactionFileSummary TABLE (
		RecID INTEGER IDENTITY,
		TollDate DATE,
		TollDateTransactionFilename VARCHAR (255),
		CoopBatchID BIGINT,
		AVITransCnt INT,
		TBPTransCnt INT,
		LaneOpenMsgCnt INT,
		LaneCloseMsgCnt INT,
		LaneStatusMsgCnt INT,
		TotalTransCnt INTEGER
	)

	DECLARE @outTranactionsFileDetail TABLE (
		TollDate DATE,
		TollDateTransactionFilename VARCHAR (255),
		LaneGroupID INTEGER,
		LaneGroupName VARCHAR(60),
		MessageType VARCHAR(2),
		MessageTypeDesc VARCHAR(25),
		BeginSeqNum INTEGER,
		EndSeqNum INTEGER,
		TransCount INTEGER,
		SortOrder TINYINT
	)

	DECLARE @outTollByPlateTagFileSummary TABLE (
		TollDate DATE,
		--TollDateTransactionFilename VARCHAR (255),
		TollByPlateTransCnt INT,
		PhantomTransCnt INT,
		MultiTagTransCnt INT,
		ExpectedTagFileCnt INT,
		TagFilesSentCnt INT,
		MissingTagFileCnt INT
	)

	DECLARE @outMissingImagesDetails TABLE (
		Title VARCHAR(25),
		TagFileName VARCHAR(12),
		TransSeqNum INT,
		AVIReadTime DATETIME,
		TransID VARCHAR(20),
		TransDate DATETIME,
		LaneNumber TINYINT,
		ImageFileName VARCHAR(255)
	)

	DECLARE @MissingImages TABLE (
		TransID BIGINT,
		TransDate DATETIME,
		LaneNumber INT
	)

	DECLARE @ExpectedTagFiles TABLE (
		TollDate DATE,
		TransID BIGINT,
		TagFileName VARCHAR(12) UNIQUE
	)

	DECLARE @AVIReadTimevsTrandDate TABLE (
        TollDate                 DATE,
        Lt5sCnt                  INTEGER,
        Lt5sPct                  DECIMAL(6, 2),
        Btwn5and30sCnt           INTEGER,
        Btwn5and30sPct           DECIMAL(6, 2),
        Btwn30and60sCnt          INTEGER,
        Btwn30and60sPct          DECIMAL(6, 2),
        Gt60sCnt                 INTEGER,
        Gt60sPct                 DECIMAL(6, 2),
        TagReadAfterTransDateCnt INTEGER,
        TagReadAfterTransDatePct DECIMAL(6, 2),
        TotTagReadCnt            INTEGER
     )
      
	 DECLARE @AVIReadTimeGt5s TABLE (
        TransID                  BIGINT,
        LaneNumber               INTEGER,
        AVIReadTime              DATETIME,
        TransDate                DATETIME,
        AVIReadTimeTrandDateDiff DECIMAL(10, 3),
        Gt5s                     BIT,
        Gt30s                    BIT,
        Gt60s                    BIT,
        TagReadAfterTransDate    BIT
    )

	INSERT INTO @TollDate(
		TollDate
	)
	SELECT TOP 2 
		CAST(DATEADD(DAY, -1 * (ROW_NUMBER() OVER (ORDER BY error)-1), GETDATE()) AS DATE) AS TollDate
	FROM sys.sysmessages

	DELETE FROM @TollDate WHERE TollDate <= '2023-04-27'

	UPDATE @TollDate SET
		TollStartDate = TollDate,
		TollEndDate = DATEADD(MILLISECOND, -3, DATEADD(DAY, 1, CAST(TollDate AS DATETIME))),
		TollDateTransactionFilename = 'INF' + CONVERT(VARCHAR(8), TollDate, 12) --+ '.GZ'
		 
	SELECT
		@StartDate = MIN(TollStartDate),
		@EndDate = MAX(TollEndDate)
	FROM 
		@TollDate

	SELECT TOP (1) 
		@AppSvcIPAddress = MachineIP
	FROM 
		OPS.dbo.tblMachines (NOLOCK) 
	WHERE 
		MachineTypeID = 3
		AND IsActive = 1

	DECLARE @ShellCmd VARCHAR(255)
	SET @ShellCmd = 'dir \\' + @AppSvcIPAddress + '\d$\InfinityData\TXN\Processed\*.GZ /b /s'

	INSERT INTO @TransactionFiles ( Filename )
	EXECUTE xp_cmdshell @ShellCmd --= 'dir \\' + MachineIP + '\d$\InfinityData\TXN\Processed\*.GZ /b /s'

	--SELECT 'here'
	--SELECT *
	
	--FROM @TollDate TD 
	--	INNER JOIN (
	--		SELECT P.mystr
	--		FROM @TransactionFiles TF
	--			CROSS APPLY (
	--				SELECT mystr
	--				FROM ReportLayer.[dbo].[udfr_ParseComma](REPLACE(TF.Filename, '\', ','))
	--		) P
	--		WHERE mystr LIKE 'INF%'
	--	) TFD ON TFD.mystr LIKE TD.TollDateTransactionFilename + '%'


--SELECT * FROM @outTransactionFileStatus
--SELECT * from @TollDate
--SELECT * FROM @TransactionFiles

	INSERT INTO @outTransactionFileStatus (
		TollDate  ,
		TollDateTransactionFilename ,
		TollDateFileStatus
	)
	SELECT 
		TD.TollDate,
		TFD.mystr,
		CASE WHEN TFD.mystr IS NOT NULL THEN 'Sent to PTC Toll Host' ELSE NULL END
	FROM @TollDate TD 
		INNER JOIN (
			SELECT P.mystr
			FROM @TransactionFiles TF
				CROSS APPLY (
					SELECT mystr
					FROM ReportLayer.[dbo].[udfr_ParseComma](REPLACE(TF.Filename, '\', ','))
			) P
			WHERE mystr LIKE 'INF%'
		) TFD ON TFD.mystr LIKE TD.TollDateTransactionFilename + '%'

--SELECT * FROM @outTransactionFileStatus
--SELECT * from @TollDate
--SELECT * FROM @TransactionFiles



	DELETE FROM @TransactionFiles

	--SET @ShellCmd = 'dir \\' + @AppSvcIPAddress + '\d$\InfinityData\TXN\Incoming\*.DAT /b'
	--INSERT INTO @TransactionFiles ( Filename )
	--EXECUTE xp_cmdshell @ShellCmd

	--UPDATE TFS SET
	--	TFS.TollDateFileStatus = 'Pending PTC Toll Host Pickup'
	--FROM
	--	@outTransactionFileStatus TFS
	--	INNER JOIN @TransactionFiles TF 
	--		ON TF.Filename = TFS.TollDateTransactionFilename
	--WHERE TFS.TollDateFileStatus IS NULL

	UPDATE @TransactionFiles SET
		TransactionFileDate = CONVERT(DATE, SUBSTRING(Filename, 4, 6))

	DELETE TF FROM @TransactionFiles TF
		INNER JOIN @outTransactionFileStatus TFS ON TF.Filename = REPLACE(TFS.TollDateTransactionFilename, 'GZ', 'DAT')

	INSERT INTO @outTransactionFileStatus (
	    TollDate,
	    TollDateTransactionFilename,
	    TollDateFileStatus
	)
	SELECT 
		TF.TransactionFileDate,
		TF.Filename,
		'Transaction .DAT File Generated'
	FROM @TransactionFiles TF
	WHERE TF.Filename IS NOT NULL

	--INSERT INTO @outTransactionFileStatus (
	--    TollDate,
	--    TollDateTransactionFilename,
	--    TollDateFileStatus
	--)
	--SELECT 
	--	CAST(CB.DateBatched AS DATE),
	--	CB.PayableFileName,
	--	'Transaction .DAT File Does Not Exist'
	--FROM ICD.dbo.tblCoopBatch CB (NOLOCK)
	--	INNER JOIN ICD.PTC.tblCoopBatchTXNLaneDetail CBTXN (NOLOCK) 
	--		ON CBTXN.CoopBatchID = CB.CoopBatchID
	--	INNER JOIN ICD.PTC.tblTXNLaneDetail TXN (NOLOCK)
	--		ON TXN.InfinityLaneTransactionID = CBTXN.LaneTransactionID
	--WHERE CB.DateBatched BETWEEN @StartDate AND @EndDate
	--AND TXN.TransDate > @PTC_TRANS_START_DATE
	--AND CB.FileType = 'PTC_TXN'
	--AND NOT EXISTS (
	--	SELECT TOP (1) 1
	--	FROM @outTransactionFileStatus TFS
	--	WHERE REPLACE(TFS.TollDateTransactionFilename, 'GZ', 'DAT') = CB.PayableFileName
	--)
	--ORDER BY CB.DateBatched;

	DELETE @TransactionFiles WHERE TransactionFileDate < @StartDate;
	DELETE @outTransactionFileStatus WHERE TollDate < @StartDate;

	INSERT INTO @outTransactionFileSummary
	(
	    TollDate,
	    TollDateTransactionFilename,
	    CoopBatchID,
	    AVITransCnt,
	    TBPTransCnt,
	    LaneOpenMsgCnt,
	    LaneCloseMsgCnt,
		LaneStatusMsgCnt,
	    TotalTransCnt
	)
	SELECT 
		TFS.TollDate,
		REPLACE(TFS.TollDateTransactionFilename, '.GZ', '.DAT'),
		CB.CoopBatchID,
		0,
		0,
		0,
		0,
		0,
		0
	FROM @outTransactionFileStatus TFS
		INNER JOIN ICD.dbo.tblCoopBatch CB (NOLOCK)
			ON CB.PayableFileName = REPLACE(TFS.TollDateTransactionFilename, '.GZ', '.DAT');

	WITH BatchTransTotals(CoopBatchID, AVITransCnt, TBPTransTotal) AS
	(
		SELECT 
			TFS.CoopBatchID,
			SUM(CASE WHEN TTU.TransType = 'ETCL' THEN 1 ELSE 0 END) AS AVITransCnt,
			SUM(CASE WHEN TTU.TransType = 'VIOL' THEN 1 ELSE 0 END) AS TBPTransCnt
		FROM @outTransactionFileSummary TFS
			INNER JOIN ICD.PTC.tblCoopBatchTXNLaneDetail TXN (NOLOCK)
				ON TXN.CoopBatchID = TFS.CoopBatchID
			INNER JOIN OPS.dbo.tblTransaction TTU (NOLOCK)
				ON TTU.TransID = TXN.LaneTransactionID
		GROUP BY TFS.CoopBatchID
	)
	UPDATE TFS SET
		AVITransCnt = BTT.AVITransCnt,
		TFS.TBPTransCnt = BTT.TBPTransTotal
	FROM @outTransactionFileSummary TFS
		INNER JOIN BatchTransTotals BTT 
			ON BTT.CoopBatchID = TFS.CoopBatchID;	
			
	WITH BatchLaneOpenTotals(CoopBatchID, LaneOpenMsgCnt) AS
	(
		SELECT 
			TFS.CoopBatchID,
			COUNT(*) AS LaneOpenMsgCnt			
		FROM @outTransactionFileSummary TFS
			INNER JOIN ICD.PTC.tblCoopBatchLaneOpen BLO (NOLOCK)
				ON BLO.CoopBatchID = TFS.CoopBatchID
			INNER JOIN ICD.PTC.tblCoopBatchLaneOpenDetail BLOD (NOLOCK)
				ON BLOD.UTCDateCreated = BLO.UTCDateCreated
		GROUP BY TFS.CoopBatchID
	)
	UPDATE TFS SET
		TFS.LaneOpenMsgCnt = BLOT.LaneOpenMsgCnt
	FROM @outTransactionFileSummary TFS
		INNER JOIN BatchLaneOpenTotals BLOT 
			ON BLOT.CoopBatchID = TFS.CoopBatchID;	

	WITH BatchLaneCloseTotals(CoopBatchID, LaneCloseMsgCnt) AS
	(
		SELECT 
			TFS.CoopBatchID,
			COUNT(*) AS LaneCloseMsgCnt			
		FROM @outTransactionFileSummary TFS
			INNER JOIN ICD.PTC.tblCoopBatchLaneClose BLC (NOLOCK)
				ON BLC.CoopBatchID = TFS.CoopBatchID
			INNER JOIN ICD.PTC.tblCoopBatchLaneCloseDetail BLCD (NOLOCK)
				ON BLCD.UTCDateCreated = BLC.UTCDateCreated
		GROUP BY TFS.CoopBatchID
	)
	UPDATE TFS SET
		TFS.LaneCloseMsgCnt = BLCT.LaneCloseMsgCnt
	FROM @outTransactionFileSummary TFS
		INNER JOIN BatchLaneCloseTotals BLCT 
			ON BLCT.CoopBatchID = TFS.CoopBatchID;	

	UPDATE TFS SET
		TFS.LaneStatusMsgCnt = (SELECT COUNT(*) FROM OPS.dbo.cfgLanes L WHERE L.IsActive = 1)
	FROM @outTransactionFileSummary TFS

	UPDATE TFS SET
		TFS.TotalTransCnt = AVITransCnt + TBPTransCnt + LaneOpenMsgCnt + LaneCloseMsgCnt + TFS.LaneStatusMsgCnt
	FROM @outTransactionFileSummary TFS

	INSERT INTO @outTranactionsFileDetail
	(
	    TollDate,
	    TollDateTransactionFilename,
	    LaneGroupID,
	    LaneGroupName,
	    MessageType,
	    MessageTypeDesc,
	    BeginSeqNum,
	    EndSeqNum,
	    TransCount,
	    SortOrder
	)
	SELECT 
		TFS.TollDate,
	    TFS.TollDateTransactionFilename,
	    LG.LaneGroupID,
	    LG. LaneGroupName,
	    TXN.MessageType,
	    CASE TXN.MessageType
			WHEN '06' THEN 'Vehicle AET Transaction'
			WHEN '03' THEN 'Lane Open'
			WHEN '04' THEN 'Lane Close'
			WHEN '02' THEN 'Lane Status'
			ELSE 'Invalid'
		END MessageTypeDesc,
	    MIN(TXN.TransactionNumber) AS BeginSeqNum,
	    MAX(TXN.TransactionNumber) AS EndSeqNum,
	    COUNT(*) TransCount,
	    CASE TXN.MessageType
					WHEN '06' THEN 1
					WHEN '03' THEN 2
					WHEN '04' THEN 3
					WHEN '02' THEN 4
					ELSE 5
		END AS SortOrder 
	FROM @outTransactionFileStatus TFS
		INNER JOIN ICD.dbo.tblCoopBatch CB (NOLOCK) 
			ON CB.PayableFileName = REPLACE(TFS.TollDateTransactionFilename, '.GZ', '.DAT')
		INNER JOIN ICD.PTC.tblCoopBatchTXNLaneDetail CBTXN (NOLOCK) ON CBTXN.CoopBatchID = CB.CoopBatchID
		INNER JOIN ICD.PTC.tblTXNLaneDetail TXN (NOLOCK) ON TXN.InfinityLaneTransactionID = CBTXN.LaneTransactionID
		INNER JOIN OPS.dbo.cfgLanes L (NOLOCK) ON L.LaneNumber = CONVERT(INTEGER, TXN.LaneNumber)
		INNER JOIN OPS.dbo.cfgLaneGroups LG (NOLOCK) ON LG.LaneGroupID = L.LaneGroupID	
		INNER JOIN ICD.dbo.tblCoopOrgLaneInfo TCOL (NOLOCK) 
			ON	LG.OrgID = TCOL.OrgID AND 
				TXN.LaneNumber = TCOL.LaneID AND
				TXN.PlazaID = TCOL.CoopOrgID
	WHERE 
		TCOL.IsActive = 1
	GROUP BY
		TFS.TollDate,
	    TFS.TollDateTransactionFilename,
		LG.LaneGroupID,
		LG.LaneGroupName,		
		TXN.MessageType

	INSERT INTO @outTranactionsFileDetail
	(
	    TollDate,
	    TollDateTransactionFilename,
	    LaneGroupID,
	    LaneGroupName,
	    MessageType,
	    MessageTypeDesc,
	    BeginSeqNum,
	    EndSeqNum,
	    TransCount,
	    SortOrder
	)
	SELECT 
		TFS.TollDate,
	    TFS.TollDateTransactionFilename,
	    LG.LaneGroupID,
	    LG. LaneGroupName,
	    TXN.MessageType,
		CASE TXN.MessageType
			WHEN '06' THEN 'Vehicle AET Transaction'
			WHEN '03' THEN 'Lane Open'
			WHEN '04' THEN 'Lane Close'
			WHEN '02' THEN 'Lane Status'
			ELSE 'Invalid'
		END MessageTypeDesc,
	    MIN(TXN.TransactionNumber) AS BeginSeqNum,
	    MAX(TXN.TransactionNumber) AS EndSeqNum,
	    COUNT(*) TransCount,
	    CASE TXN.MessageType
					WHEN '06' THEN 1
					WHEN '03' THEN 2
					WHEN '04' THEN 3
					WHEN '02' THEN 4
					ELSE 5
		END AS SortOrder 
	FROM @outTransactionFileStatus TFS
		INNER JOIN ICD.dbo.tblCoopBatch CB (NOLOCK) 
			ON CB.PayableFileName = REPLACE(TFS.TollDateTransactionFilename, '.GZ', '.DAT')
		INNER JOIN ICD.PTC.tblCoopBatchLaneOpenDetail CBLOD (NOLOCK) ON CBLOD.CoopBatchID = CB.CoopBatchID
		INNER JOIN ICD.PTC.tblTXNLaneDetail TXN (NOLOCK) ON TXN.InfinityLaneTransactionID = CBLOD.LaneTransactionID
		INNER JOIN OPS.dbo.cfgLanes L (NOLOCK) ON L.LaneNumber = CONVERT(INTEGER, TXN.LaneNumber)
		INNER JOIN OPS.dbo.cfgLaneGroups LG (NOLOCK) ON LG.LaneGroupID = L.LaneGroupID	
		INNER JOIN ICD.dbo.tblCoopOrgLaneInfo TCOL (NOLOCK) 
			ON	LG.OrgID = TCOL.OrgID AND 
				TXN.LaneNumber = TCOL.LaneID AND
				TXN.PlazaID = TCOL.CoopOrgID
	WHERE 
		TCOL.IsActive = 1
	GROUP BY
		TFS.TollDate,
	    TFS.TollDateTransactionFilename,
		LG.LaneGroupID,
		LG.LaneGroupName,		
		TXN.MessageType

	INSERT INTO @outTranactionsFileDetail
	(
	    TollDate,
	    TollDateTransactionFilename,
	    LaneGroupID,
	    LaneGroupName,
	    MessageType,
	    MessageTypeDesc,
	    BeginSeqNum,
	    EndSeqNum,
	    TransCount,
	    SortOrder
	)
	SELECT 
		TFS.TollDate,
	    TFS.TollDateTransactionFilename,
	    LG.LaneGroupID,
	    LG. LaneGroupName,
	    TXN.MessageType,
	    CASE TXN.MessageType
			WHEN '06' THEN 'Vehicle AET Transaction'
			WHEN '03' THEN 'Lane Open'
			WHEN '04' THEN 'Lane Close'
			WHEN '02' THEN 'Lane Status'
			ELSE 'Invalid'
		END MessageTypeDesc,
	    MIN(TXN.TransactionNumber) AS BeginSeqNum,
	    MAX(TXN.TransactionNumber) AS EndSeqNum,
	    COUNT(*) TransCount,
	    CASE TXN.MessageType
					WHEN '06' THEN 1
					WHEN '03' THEN 2
					WHEN '04' THEN 3
					WHEN '02' THEN 4
					ELSE 5
		END AS SortOrder 
	FROM @outTransactionFileStatus TFS
		INNER JOIN ICD.dbo.tblCoopBatch CB (NOLOCK) 
			ON CB.PayableFileName = REPLACE(TFS.TollDateTransactionFilename, '.GZ', '.DAT')
		INNER JOIN ICD.PTC.tblCoopBatchLaneCloseDetail CBLCD (NOLOCK) ON CBLCD.CoopBatchID = CB.CoopBatchID
		INNER JOIN ICD.PTC.tblTXNLaneDetail TXN (NOLOCK) ON TXN.InfinityLaneTransactionID = CBLCD.LaneTransactionID
		INNER JOIN OPS.dbo.cfgLanes L (NOLOCK) ON L.LaneNumber = CONVERT(INTEGER, TXN.LaneNumber)
		INNER JOIN OPS.dbo.cfgLaneGroups LG (NOLOCK) ON LG.LaneGroupID = L.LaneGroupID	
		INNER JOIN ICD.dbo.tblCoopOrgLaneInfo TCOL (NOLOCK) 
			ON	LG.OrgID = TCOL.OrgID AND 
				TXN.LaneNumber = TCOL.LaneID AND
				TXN.PlazaID = TCOL.CoopOrgID
	WHERE 
		TCOL.IsActive = 1
	GROUP BY
		TFS.TollDate,
	    TFS.TollDateTransactionFilename,
		LG.LaneGroupID,
		LG.LaneGroupName,		
		TXN.MessageType

	UPDATE @outTranactionsFileDetail SET
		BeginSeqNum = EndSeqNum,
		EndSeqNum = BeginSeqNum
	WHERE (EndSeqNum + 1) - BeginSeqNum <> TransCount

	--	SELECT * FROM @outTranactionsFileDetail

	--SELECT * FROM @outTransactionFileSummary
	--ORDER BY TollDate

	--SELECT * FROM @outTransactionFileStatus

	--INSERT INTO @outTranactionsFileDetail (
	--	TollDate ,
	--	TollDateTransactionFilename ,
	--	LaneGroupID ,
	--	LaneGroupName ,
	--	MessageType ,
	--	BeginSeqNum ,
	--	EndSeqNum ,
	--	TransCount
	--)
	--SELECT 
	--	DATEFROMPARTS(T.TransYear, T.TransMonth, T.TransDay),
	--	@tmpFileName,
	--	LG.LaneGroupID,
	--	LG.LaneGroupName,		
	--	MessageType,
	--	MIN(T.TransactionNumber),
	--	MAX(T.TransactionNumber),
	--	COUNT(*)
	--FROM #Transactions T
	--	INNER JOIN OPS.dbo.cfgLanes L (NOLOCK)
	--		ON L.LaneNumber = CONVERT(INTEGER, T.LaneNumber)
	--	INNER JOIN OPS.dbo.cfgLaneGroups LG (NOLOCK)
	--		ON LG.LaneGroupID = L.LaneGroupID	
	--	INNER JOIN ICD.dbo.tblCoopOrgLaneInfo TCOL (NOLOCK)
	--		ON	LG.OrgID = TCOL.OrgID AND 
	--			T.LaneNumber = TCOL.LaneID AND
	--			T.PlazaID = TCOL.CoopOrgID
	--WHERE 
	--	TCOL.IsActive = 1
	--GROUP BY
	--	DATEFROMPARTS(T.TransYear, T.TransMonth, T.TransDay),
	--	LG.LaneGroupID,
	--	LG.LaneGroupName,		
	--	MessageType
		
		SELECT * FROM @outTranactionsFileDetail

	INSERT INTO @outTollByPlateTagFileSummary (
		TollDate ,
	    --TollDateTransactionFilename ,
	    TollByPlateTransCnt ,
	    PhantomTransCnt,
		MultiTagTransCnt,
		TagFilesSentCnt 
	)
	SELECT 
		TFS.TollDate,
		--TFS.TollDateTransactionFilename,
		SUM(CASE WHEN SUBSTRING(TXN.UO10, 7, 1) = '1' AND SUBSTRING(TXN.UO25, 6, 1) = '0' AND SUBSTRING(TXN.UO4, 6, 1) = '0' THEN 1 ELSE 0 END) AS TollByPlateTransCnt,
		SUM(CASE WHEN SUBSTRING(TXN.UO25, 6, 1) = '1' THEN 1 ELSE 0 END ) AS PhantomTransCnt,
		SUM(CASE WHEN SUBSTRING(TXN.UO4, 6, 1) = '1'  THEN 1 ELSE 0 END) AS MultiTagTransCnt,
		COUNT(VIO.LaneTransactionID) AS TagFilesSentCnt
	FROM @outTransactionFileSummary TFS
		INNER JOIN ICD.PTC.tblCoopBatchTXNLaneDetail CBTXN (NOLOCK)
			ON CBTXN.CoopBatchID = TFS.CoopBatchID
		INNER JOIN ICD.PTC.tblTXNLaneDetail TXN (NOLOCK)
			ON TXN.InfinityLaneTransactionID = CBTXN.LaneTransactionID
		LEFT OUTER JOIN ICD.PTC.tblCoopBatchVIOLaneDetail VIO (NOLOCK)
			ON VIO.LaneTransactionID = TXN.InfinityLaneTransactionID 
	WHERE 
		SUBSTRING(TXN.UO10, 7, 1) = '1'
	GROUP BY
		TFS.TollDate--,
		--TFS.TollDateTransactionFilename,
		--TFS.TBPTransCnt

	--INSERT INTO @ExpectedTagFiles (
	--	TollDate ,
	--	TransID ,
	--	TagFileName
	--)
	--SELECT 
	--	TFS.TollDate,
	--	TTU.TransID,
	--	'P' + RIGHT('00' + ICD.[Prl].[udf_prl_ConvertToBase36](TCOL.CoopOrgID) COLLATE SQL_Latin1_General_CP437_BIN, 2) +
	--			RIGHT('0' +	ICD.[Prl].[udf_prl_ConvertToBase36](TTU.LaneNumber) COLLATE SQL_Latin1_General_CP437_BIN, 1) +
	--			RIGHT('0000' + ICD.[Prl].[udf_prl_ConvertToBase36](TTU.ID % 1679615) COLLATE SQL_Latin1_General_CP437_BIN, 4) + '.tag' AS TagFileName
	--FROM @outTransactionFileSummary TFS
	--	INNER JOIN ICD.PTC.tblCoopBatchTXNLaneDetail TXN (NOLOCK)
	--		ON TXN.CoopBatchID = TFS.CoopBatchID
	--	INNER JOIN OPS.dbo.tblCoopTagTollUsage TTU (NOLOCK)
	--		ON TTU.TransID = TXN.LaneTransactionID
	--	INNER JOIN ICD.dbo.tblCoopOrgLaneInfo TCOL (NOLOCK)
	--		ON	TTU.OrgID = TCOL.OrgID AND TTU.LaneNumber= TCOL.LaneID 
	--WHERE
	--	TTU.TransType = 'VIOL'	
	--	AND TCOL.IsActive = 1

	--SET @ShellCmd = 'dir \\' + @AppSvcIPAddress + '\d$\InfinityData\IMG\Processed\*.tag /b'
	--DELETE FROM @TransactionFiles
	--INSERT INTO @TransactionFiles ( Filename )
	--EXECUTE xp_cmdshell @ShellCmd;

	
	--WITH TagFileCount(TollDate, FileCnt) AS 
	--(
	--	SELECT 
	--		TFS.TollDate,
	--		COUNT(*) AS FileCnt
	--		FROM @outTollByPlateTagFileSummary TFS
	--			INNER JOIN @ExpectedTagFiles ETF
	--				ON ETF.TollDate = TFS.TollDate
	--			INNER JOIN @TransactionFiles TF
	--				ON TF.Filename = ETF.TagFileName
	--		GROUP BY
	--			TFS.TollDate
	--)
	--UPDATE TFS SET
	--	TFS.TagFilesSentCnt = FileCnt
	--FROM @outTollByPlateTagFileSummary TFS
	--	INNER JOIN TagFileCount TFC
	--		ON TFC.TollDate = TFS.TollDate;

	UPDATE @outTollByPlateTagFileSummary SET	
		ExpectedTagFileCnt = TollByPlateTransCnt - (PhantomTransCnt + MultiTagTransCnt)

	UPDATE @outTollByPlateTagFileSummary SET
		MissingTagFileCnt = ExpectedTagFileCnt - TagFilesSentCnt

	INSERT INTO @MissingImages (
		TransID,
		TransDate,
		LaneNumber
	)
	SELECT TOP (100)  -- rc 2023-5-01
		TXN.InfinityLaneTransactionID,
		TXN.TransDate,
		TXN.LaneNumber
	FROM @outTransactionFileSummary TFS
		INNER JOIN ICD.PTC.tblCoopBatchTXNLaneDetail CBTXN (NOLOCK)
			ON CBTXN.CoopBatchID = TFS.CoopBatchID
		INNER JOIN ICD.PTC.tblTXNLaneDetail TXN (NOLOCK)
			ON TXN.InfinityLaneTransactionID = CBTXN.LaneTransactionID
	WHERE 
		SUBSTRING(TXN.UO10, 7, 1) = '1' 
		AND SUBSTRING(TXN.UO25, 6, 1) = '0' -- PhantomTransCnt,
		AND SUBSTRING(TXN.UO4, 6, 1) = '0'  -- MultiTagTransCnt
		AND NOT EXISTS (
			SELECT TOP (1) 1
			FROM ICD.PTC.tblCoopBatchVIOLaneDetail VIO (NOLOCK)
			WHERE VIO.LaneTransactionID = CBTXN.LaneTransactionID
		)	
			AND TXN.TransDate < DATEDIFF(HOUR, -6, TXN.TransDate)
	ORDER BY TransDate DESC

	INSERT INTO @outMissingImagesDetails (
		Title ,
	    TagFileName ,
	    TransSeqNum ,
	    AVIReadTime ,
	    TransID ,
	    TransDate ,
	    LaneNumber ,
	    ImageFileName
	)	
	SELECT 
		CASE 
			WHEN MI.TransID = TTU.TransID THEN '<-- Missing Images -->' 
			ELSE '<-- Split Trx? -->' END AS Title,
		'P' + RIGHT('00' + ICD.[Prl].[udf_prl_ConvertToBase36](TXN.PlazaID) COLLATE SQL_Latin1_General_CP437_BIN, 2) +
					RIGHT('0' +	ICD.[Prl].[udf_prl_ConvertToBase36](TTU.LaneNumber) COLLATE SQL_Latin1_General_CP437_BIN, 1) +
					RIGHT('0000' + ICD.[Prl].[udf_prl_ConvertToBase36](TTU.ID % 1679615) COLLATE SQL_Latin1_General_CP437_BIN, 4) + '.tag' AS TagFileName,
		COALESCE(TTU.LaneSequenceNumber, '') AS SequenceNumber,
		TTU.AVIReadTime, 
		'0' + CAST(TTU.TransID AS VARCHAR),
		TTU.TransDate,
		TTU.LaneNumber,
		REPLACE(UPPER(TTU.ImageFileName), '.JPG', '')
	FROM @outTransactionFileSummary TFS
		INNER JOIN ICD.PTC.tblCoopBatchTXNLaneDetail CBTXN (NOLOCK)
			ON CBTXN.CoopBatchID = TFS.CoopBatchID
		INNER JOIN ICD.PTC.tblTXNLaneDetail TXN (NOLOCK)
			ON TXN.InfinityLaneTransactionID = CBTXN.LaneTransactionID
		INNER JOIN OPS.dbo.tblCoopTagTollUsage TTU (NOLOCK) ON TTU.TransID = CBTXN.LaneTransactionID
		INNER JOIN @MissingImages MI
			ON MI.LaneNumber = TTU.LaneNumber
				AND TTU.TransDate BETWEEN DATEADD(MILLISECOND, -500, MI.TransDate) AND DATEADD(MILLISECOND, 500, MI.TransDate) 
		--INNER JOIN RPT.dbo.tblTransStore RPT_TS (NOLOCK)
		--	ON RPT_TS.TransID = TTU.TransID 
	WHERE TTU.IVISPostClassVehSpeed > 10
	ORDER BY TTU.TransDate

	INSERT INTO @AVIReadTimevsTrandDate
                  (TollDate,
                   Lt5sCnt,
                   Lt5sPct,
                   Btwn5and30sCnt,
                   Btwn5and30sPct,
                   Btwn30and60sCnt,
                   Btwn30and60sPct,
                   Gt60sCnt,
                   Gt60sPct,
                   TagReadAfterTransDateCnt,
                   TagReadAfterTransDatePct,
                   TotTagReadCnt)
      SELECT CAST(TransDate AS DATE),
             SUM(CASE
                   WHEN DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) BETWEEN 0 AND 5000 THEN 1
                   ELSE 0
                 END) AS Lt5sCnt,
             NULL     AS Lt5sPct,
             SUM(CASE
                   WHEN DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) BETWEEN 5001 AND 30000 THEN 1
                   ELSE 0
                 END) AS Btwn5and30sCnt,
             NULL     AS Btwn5and30sPct,
             SUM(CASE
                   WHEN DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) BETWEEN 30001 AND 60000 THEN 1
                   ELSE 0
                 END) AS Btwn30and60sCnt,
             NULL     AS Btwn30and60sPct,
             SUM(CASE
                   WHEN DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) > 60000 THEN 1
                   ELSE 0
                 END) AS Gt60sCnt,
             NULL     AS Gt60sPct,
             SUM(CASE
                   WHEN DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) < 0 THEN 1
                   ELSE 0
                 END) TagReadAfterTransDateCnt,
             NULL     AS TagReadAfterTransDatePct,
             SUM(1)   AS TotTagReadCnt
      FROM   OPS.dbo.tblCoopTagTollUsage TTU (NOLOCK)
             INNER JOIN @TollDate TD
                     ON TTU.TransDate BETWEEN TD.TollStartDate AND TD.TollEndDate
      WHERE  TTU.AVIReadTime IS NOT NULL
             --AND TTU.IVISPostClassVehSpeed > 0
      GROUP  BY CAST(TransDate AS DATE)

      UPDATE @AVIReadTimevsTrandDate
      SET    Lt5sPct = Lt5sCnt * 1.00 / TotTagReadCnt * 100,
             Btwn5and30sPct = Btwn5and30sCnt * 1.00 / TotTagReadCnt * 100,
             Btwn30and60sPct = Btwn30and60sCnt * 1.00 / TotTagReadCnt * 100,
             Gt60sPct = Gt60sCnt * 1.00 / TotTagReadCnt * 100,
             TagReadAfterTransDatePct = TagReadAfterTransDateCnt * 1.00 / TotTagReadCnt * 100

      SELECT '@AVIReadTimevsTrandDate2',
             *
      FROM   @AVIReadTimevsTrandDate

      INSERT INTO @AVIReadTimeGt5s
                  (TransID,
                   LaneNumber,
                   AVIReadTime,
                   TransDate,
                   AVIReadTimeTrandDateDiff,
                   Gt5s,
                   Gt30s,
                   Gt60s,
                   TagReadAfterTransDate)
      SELECT TTU.TransID,
             TTU.LaneNumber,
             TTU.AVIReadTime,
             TTU.TransDate,
             DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) * 1.00 / 1000,
             CASE
               WHEN DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) BETWEEN 5001 AND 30000 THEN 1
               ELSE 0
             END,
             CASE
               WHEN DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) BETWEEN 30001 AND 60000 THEN 1
               ELSE 0
             END,
             CASE
               WHEN DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) > 60000 THEN 1
               ELSE 0
             END,
             CASE
               WHEN DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) < 0 THEN 1
               ELSE 0
             END
      FROM   OPS.dbo.tblCoopTagTollUsage TTU (NOLOCK)
      WHERE  TTU.AVIReadTime IS NOT NULL
             --AND TTU.IVISPostClassVehSpeed > 0
             AND ( DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) >= 5000
                    OR DATEDIFF(MILLISECOND, TTU.AVIReadTime, TTU.TransDate) < 0 )
             AND TTU.TransDate BETWEEN @StartDate AND @EndDate;

-- BEGIN EMAIL SECTION

	SELECT @Body = @Body + '<h2>PTC '+ @PlazaName + ': Infinity - PTC Toll Host/VPC Reconciliation Report as of ' + CONVERT(VARCHAR(10), @Today, 120) + '</h2>'
	SET @Body = @Body + '<a href="mailto:raymond.cloak@transcore.com?Subject=Unsubscribe%20–%20PTC%20Daily%20Transaction%20Reconciliation%20Report&amp;Body=Please%20remove%20me.">Click Here to Unsubscribe</a>'

	SET @Body = @Body + '<table border="1" cellpadding="0px" cellspacing ="0px" >' +
				'<tr><th  style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="3">Missing Transaction Files</th></tr>' +
				'<tr><th>Date</th><th>Transaction<br />Filename</th><th>Status</th></tr>'

	SET @xml = NULL
	SELECT @xml = CAST((
		SELECT DISTINCT
			TollDate AS 'td', '',
			REPLACE(TollDateTransactionFilename, '.GZ', '.DAT') AS 'td', '',
			TollDateFileStatus AS 'td', ''
		FROM
			@outTransactionFileStatus TFS
			INNER JOIN ICD.dbo.tblCoopBatch CB (NOLOCK)
				ON CB.PayableFileName = REPLACE(TollDateTransactionFilename, '.GZ', '.DAT') 
		WHERE 
			TollDateFileStatus <> 'Sent to PTC Toll Host'
			AND CB.DateBatched < DATEADD(MINUTE, -30, GETDATE())
		ORDER BY 
			1 DESC,
			3 DESC
	FOR XML PATH ('tr'),ELEMENTS ) AS NVARCHAR(MAX))

	SET @Body = @Body + ISNULL(@xml, '<tr><td colspan="3" style="text-align:left">No Missing Transaction Files Found</td></tr>') + '</table><br />'

	SET @Body = @Body + '<table border="1" cellpadding="0px" cellspacing ="0px" >' +
				'<tr><th  style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="9">Lane Gap Sequence Report</th></tr>' +
				'<tr><th>Plaza</th><th>Lane</th>'+
				'<th>LaneType</th><th>Current Transaction</th><th>Current Date</th><th>Missing Transaction</th>' +
				'<th>Previous Trans</th><th>Previous Trans Date</th><th>Explanation</th></tr>'
	
	SET @xml = CAST((
	SELECT 
		Plaza AS 'td', '',
		Lane AS 'td', '',
		LaneType AS 'td', '',
		CurrLaneSequenceNumber AS 'td', '',
		CONVERT(VARCHAR, CurrTransDate, 121) AS 'td', '',
		MissingLaneSequenceNumber AS 'td', '',
		PrevLaneSequenceNumber AS 'td', '',
		CONVERT(VARCHAR, PrevTransDate, 121) AS 'td', '',
		MissingLaneSequenceNumberReason AS 'td', ''
	FROM 
		CTRL.Prl.udf_prl_Plaza_LaneSequenceNumberGapDetails_Get(@StartDate, @EndDate)
	ORDER BY
		CurrTransDate DESC 
	FOR XML PATH ('tr'),ELEMENTS ) as nvarchar(max));

	SET @Body = @Body + ISNULL(@xml, '<tr><td colspan="9" style="text-align:left">No gaps found.</td></tr>')+ '</table><br/>'

	SET @Body = @Body + '<table border="1" cellpadding="0px" cellspacing ="0px" >' +
				'<tr><th  style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="7">Transaction File Summary</th></tr>' +
				--'<tr><th rowspan="2">Date</th><th rowspan="2">Transaction<br />Filename</th><th colspan="6">Transaction Count</th></tr>' +
				'<tr><th rowspan="2">Date</th><th colspan="6">Transaction Count</th></tr>' +
				'<th>AVI</th><th>TBP</th><th>Lane Open</th><th>Lane Close</th><th>Lane Status</th><th>Total</th></tr>'

	--SET @xml = NULL
	SELECT @xml = CAST((
		SELECT 
			TollDate AS 'td', '',
			--ISNULL(REPLACE(TollDateTransactionFilename, '.GZ', '.DAT'),'') AS 'td', '',
			FORMAT(SUM(AVITransCnt), '###,##0') AS 'td', '',
			FORMAT(SUM(TBPTransCnt), '###,##0') AS 'td', '',
			FORMAT(SUM(LaneOpenMsgCnt), '###,##0') AS 'td', '',
			FORMAT(SUM(LaneCloseMsgCnt), '###,##0') AS 'td', '',
			FORMAT(SUM(LaneStatusMsgCnt), '###,##0') AS 'td', '',
			FORMAT(SUM(TotalTransCnt), '###,##0') AS 'td', ''
		FROM
			@outTransactionFileSummary
		GROUP BY
			TollDate
		ORDER BY 
			TollDate DESC--,
			--TollDateTransactionFilename DESC
	FOR XML PATH ('tr'),ELEMENTS ) AS NVARCHAR(MAX))

	SET @Body = @Body + ISNULL(@xml, '<tr><td colspan="7" style="text-align:left">No Records Found</td></tr>') + '</table><br />'

	--DECLARE @LastCoopBatchID BIGINT
	--SELECT 
	--	@LastCoopBatchID = MAX(CoopBatchID)
	--FROM 
	--	@outTranactionsFileDetail

	SET @Body = @Body + '<table border="1" cellpadding="0px" cellspacing ="0px" >' +
				'<tr><th  style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="6">Transaction File Detail</th></tr>' +
				--'<tr><th>Transaction<br />Filename</th><th>Date</th><th>Message<br />Type</th><th>Lane Group</th>' +
				'<tr><th>Date</th><th>Message<br />Type</th><th>Lane Group</th>' +
				'<th>Starting<br />Sequence #</th><th>Ending<br />Sequence #</th><th>Transaction<br />Count</th></tr>'

	SET @xml = NULL
	SELECT @xml = CAST((
		SELECT 
			--REPLACE(TollDateTransactionFilename, '.GZ', '.DAT') AS 'td', '',
			TollDate AS 'td', '',
			MessageTypeDesc AS 'td', '',
			LaneGroupName AS 'td', '',
			CASE WHEN MAX(EndSeqNum) - MIN(BeginSeqNum) + 1 = SUM(TransCount) THEN MIN(BeginSeqNum) ELSE MAX(EndSeqNum) END AS 'td', '',
			CASE WHEN MAX(EndSeqNum) - MIN(BeginSeqNum) + 1 = SUM(TransCount) THEN MAX(EndSeqNum) ELSE MIN(BeginSeqNum) END AS 'td', '',
			--MIN(BeginSeqNum) AS 'td', '',
			--MAX(EndSeqNum) AS 'td', '',
			FORMAT(SUM(TransCount), '###,##0') AS 'td', ''
		FROM
			@outTranactionsFileDetail
		GROUP BY
			TollDate, 
			MessageTypeDesc,
			LaneGroupName,
			LaneGroupID
		ORDER BY 
			TollDate DESC, 
			--TollDateTransactionFilename DESC, 
			LaneGroupID--, 
			--SortOrder
	FOR XML PATH ('tr'),ELEMENTS ) AS NVARCHAR(MAX))

	SET @Body = @Body + ISNULL(@xml, '<tr><td colspan="6" style="text-align:left">No Records Found</td></tr>') + '</table><br />'

	SET @Body = @Body + '<table border="1" cellpadding="0px" cellspacing ="0px" >' +
				'<tr><th  style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="7">Violation Transaction Reconciliation Summary</th></tr>' +
				'<tr><th>Date</th><th>Toll-By-Plate Cnt</th><th>Phantom Cnt</th>' +
				'<th>Multi-Tag Cnt</th><th>VPC Expected .tag Files</th><th>.Tag Files Sent</th><th>Missing .Tag Files</th></tr>'

	SET @xml = NULL
	SELECT @xml = CAST((
		SELECT TOP (10)  -- RTC 2022-04-30 
			TollDate AS 'td', '',
			FORMAT(TollByPlateTransCnt, '###,##0') AS 'td', '',
			FORMAT(PhantomTransCnt, '###,##0') AS 'td', '',
			FORMAT(MultiTagTransCnt, '###,##0') AS 'td', '',
			FORMAT(ExpectedTagFileCnt, '###,##0') AS 'td', '',
			FORMAT(TagFilesSentCnt, '###,##0') AS 'td', '',
			FORMAT(MissingTagFileCnt, '###,##0') AS 'td', ''
		FROM
			@outTollByPlateTagFileSummary
		ORDER BY 
			TollDate DESC
	FOR XML PATH ('tr'),ELEMENTS ) AS NVARCHAR(MAX))

	SET @Body = @Body + ISNULL(@xml, '<tr><td colspan="6" style="text-align:left">No Records Found</td></tr>') + '</table><br />'

	SET @Body = @Body + '<table border="1" cellpadding="0px" cellspacing ="0px" >' +
				'<tr><th  style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="8">Violation Transaction Reconciliation Details</th></tr>' +
				'<tr><th>Status</th><th>Tag Filename</th>'+
				'<th>Seq. #</th><th>AVI Read Time</th><th>TransID</th><th>Trans Date</th>' +
				'<th>Lane #</th><th>Image Filename</th></tr>'
	
	SET @xml = CAST((
	SELECT TOP (10)  -- RTC 2023-04-30
		Title AS 'td', '',
		TagFileName AS 'td', '',
		TransSeqNum AS 'td', '',
		CASE WHEN AVIReadTime IS NULL THEN ''
			ELSE CONVERT(VARCHAR, AVIReadTime, 121)
		END AS 'td', '',
		TransID AS 'td', '',
		CONVERT(VARCHAR, TransDate, 121)AS 'td', '',
		LaneNumber AS 'td', '',
		ImageFileName AS 'td', ''
	FROM 
		@outMissingImagesDetails
	ORDER BY
		TransDate DESC 
	FOR XML PATH ('tr'),ELEMENTS ) as nvarchar(max));

	SET @Body = @Body + ISNULL(@xml, '')+ '</table><br/>'

	     SELECT @Body = @Body
                     + '<table border="1" cellpadding="0px" cellspacing ="0px" >'
                     + '<tr><th style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="12">'
                     + 'AVI Read Time vs. Transaction Time</th></tr>'
                     + '<tr><th colspan="3">&nbsp;</th><th colspan="4">Between</th><th colspan="5">&nbsp;</th>'
                     + '<tr><th>Date</th><th>&lt;= 5s</th><th>&lt;= 5s %</th>'
                     + '<th>5s and 30s</th><th>5s and 30s %</th>'
                     + '<th>30s and 60s</th><th>30s and 60s %</th>'
                     + '<th>&gt; 60s</th><th>&gt; 60s %</th>'
                     + '<th>Tag Read After TransDate</th><th>Tag Read After TransDate %</th><th>Tag Reads</th></tr>'

      SELECT @xml = CAST((SELECT TOP 150 TollDate                               AS 'td',
                                         '',
                                         FORMAT(Lt5sCnt, '###,###')             AS 'td',
                                         '',
                                         CAST(Lt5sPct AS VARCHAR) + '%'         AS 'td',
                                         '',
                                         Btwn5and30sCnt                         AS 'td',
                                         '',
                                         CAST(Btwn5and30sPct AS VARCHAR) + '%'  AS 'td',
                                         '',
                                         Btwn30and60sCnt                        AS 'td',
                                         '',
                                         CAST(Btwn30and60sPct AS VARCHAR) + '%' AS 'td',
                                         '',
                                         Gt60sCnt                               AS 'td',
                                         '',
                                         CAST(Gt60sPct AS VARCHAR) + '%'        AS 'td',
                                         '',
                                         TagReadAfterTransDateCnt               AS 'td',
                                         '',
                                         CAST(TagReadAfterTransDatePct AS VARCHAR)
                                         + '%'                                  AS 'td',
                                         '',
                                         FORMAT(TotTagReadCnt, '###,###')       AS 'td',
                                         ''
                          FROM   @AVIReadTimevsTrandDate
                          ORDER  BY TollDate
                          FOR XML PATH ('tr'), ELEMENTS) AS NVARCHAR(MAX))

      SET @Body = @Body + ISNULL(@xml, '') + '</table><br />'

      SELECT @Body = @Body
                     + '<table border="1" cellpadding="0px" cellspacing ="0px" >'
                     + '<tr><th style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="5">'
                     + 'AVI Read Time vs. Transaction Time: Between 5s and 30s</th></tr>'
                     + '<tr><th>TransID</th><th>Lane #</th><th>AVI Read Time</th>'
                     + '<th>Trans Date</th><th>Difference (sec)</th></tr>'

      SET @xml = NULL

      SELECT @xml = CAST((SELECT TOP 150 TransID                            AS 'td',
                                         '',
                                         LaneNumber                         AS 'td',
                                         '',
                                         CONVERT(VARCHAR, AVIReadTime, 121) AS 'td',
                                         '',
                                         CONVERT(VARCHAR, TransDate, 121)   AS 'td',
                                         '',
                                         AVIReadTimeTrandDateDiff           AS 'td',
                                         ''
                          FROM   @AVIReadTimeGt5s
                          WHERE  Gt5s = 1
                          ORDER  BY AVIReadTime
                          FOR XML PATH ('tr'), ELEMENTS) AS NVARCHAR(MAX))

      SET @Body = @Body
                  + ISNULL(@xml, '<tr><td colspan="5" style="text-align:left">No Records Found</td></tr>')
                  + '</table><br />'

      SELECT @Body = @Body
                     + '<table border="1" cellpadding="0px" cellspacing ="0px" >'
                     + '<tr><th style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="5">'
                     + 'AVI Read Time vs. Transaction Time: Between 30s and 60s</th></tr>'
                     + '<tr><th>TransID</th><th>Lane #</th><th>AVI Read Time</th>'
                     + '<th>Trans Date</th><th>Difference (sec)</th></tr>'

      SET @xml = NULL

      SELECT @xml = CAST((SELECT TOP 150 TransID                            AS 'td',
                                         '',
                                         LaneNumber                         AS 'td',
                                         '',
                                         CONVERT(VARCHAR, AVIReadTime, 121) AS 'td',
                                         '',
                                         CONVERT(VARCHAR, TransDate, 121)   AS 'td',
                                         '',
                                         AVIReadTimeTrandDateDiff           AS 'td',
                                         ''
                          FROM   @AVIReadTimeGt5s
                          WHERE  Gt30s = 1
                          ORDER  BY AVIReadTime
                          FOR XML PATH ('tr'), ELEMENTS) AS NVARCHAR(MAX))

      SET @Body = @Body
                  + ISNULL(@xml, '<tr><td colspan="5" style="text-align:left">No Records Found</td></tr>')
                  + '</table><br />'

      SELECT @Body = @Body
                     + '<table border="1" cellpadding="0px" cellspacing ="0px" >'
                     + '<tr><th style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="5">'
                     + 'AVI Read Time vs. Transaction Time: &gt; 60s</th></tr>'
                     + '<tr><th>TransID</th><th>Lane #</th><th>AVI Read Time</th>'
                     + '<th>Trans Date</th><th>Difference (sec)</th></tr>'

      SET @xml = NULL

      SELECT @xml = CAST((SELECT TOP 150 TransID                                   AS 'td',
                                         '',
                                         LaneNumber                                AS 'td',
                                         '',
                                         CONVERT(VARCHAR, AVIReadTime, 121)        AS 'td',
                                         '',
                                         CONVERT(VARCHAR, TransDate, 121)          AS 'td',
                                         '',
                                         CAST(AVIReadTimeTrandDateDiff AS VARCHAR) AS 'td',
                                         ''
                          FROM   @AVIReadTimeGt5s
                          WHERE  Gt60s = 1
                          ORDER  BY AVIReadTime
                          FOR XML PATH ('tr'), ELEMENTS) AS NVARCHAR(MAX))

      SET @Body = @Body
                  + ISNULL(@xml, '<tr><td colspan="5" style="text-align:left">No Records Found</td></tr>')
                  + '</table><br />'

      SELECT @Body = @Body
                     + '<table border="1" cellpadding="0px" cellspacing ="0px" >'
                     + '<tr><th style="background-color: #C9D8EB; color: #000000; text-align: center; font-family: Calibri; font-size: 11pt;" colspan="5">'
                     + 'AVI Read Time vs. Transaction Time: Tag Read After Transaction Date</th></tr>'
                     + '<tr><th>TransID</th><th>Lane #</th><th>AVI Read Time</th>'
                     + '<th>Trans Date</th><th>Difference (sec)</th></tr>'

      SET @xml = NULL

      SELECT @xml = CAST((SELECT TOP 150 TransID                                   AS 'td',
                                         '',
                                         LaneNumber                                AS 'td',
                                         '',
                                         CONVERT(VARCHAR, AVIReadTime, 121)        AS 'td',
                                         '',
                                         CONVERT(VARCHAR, TransDate, 121)          AS 'td',
                                         '',
                                         CAST(AVIReadTimeTrandDateDiff AS VARCHAR) AS 'td',
                                         ''
                          FROM   @AVIReadTimeGt5s
                          WHERE  TagReadAfterTransDate = 1
                          ORDER  BY AVIReadTime
                          FOR XML PATH ('tr'), ELEMENTS) AS NVARCHAR(MAX))

      SET @Body = @Body
                  + ISNULL(@xml, '<tr><td colspan="5" style="text-align:left">No Records Found</td></tr>')
                  + '</table><br />'

	SET @Body = @Body + '</body></html>'

	SET @Subject = 'PTC ' + @PlazaName + ': Daily Infinity - PTC Toll Host/VPC Reconciliation Report: ' + CAST(@Today AS VARCHAR(30));

	IF @TestInd = 0 BEGIN
		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = 'MMC_Alerts',--'DDOT DB Mail',
			@body = @Body,
			@body_format='HTML',
			@recipients = @Recipients,
			@copy_recipients = 'raymond.cloak@transcore.com;arun.rangineni@transcore.com;yassin.khalaf@transcore.com',
			@subject = @Subject
	END ELSE BEGIN
		--SELECT 'Body:', @Body
		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = 'MMC_Alerts',--'DDOT DB Mail',
			@body = @Body,
			@body_format='HTML',
			@recipients = 'raymond.cloak@transcore.com; Arun.Rangineni@TransCore.com;casey.martin@transcore.com;milan.mitrovich@transcore.com',
			@subject = @Subject
	END

	SELECT * FROM @outTranactionsFileDetail
	SELECT * FROM @outTransactionFileSummary

END
