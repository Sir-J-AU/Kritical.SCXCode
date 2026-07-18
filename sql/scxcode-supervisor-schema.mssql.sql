IF OBJECT_ID('dbo.supervisor_runs', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.supervisor_runs (
    run_id NVARCHAR(120) NOT NULL CONSTRAINT PK_supervisor_runs PRIMARY KEY,
    task NVARCHAR(MAX) NOT NULL,
    mode NVARCHAR(40) NOT NULL,
    created_utc DATETIME2 NOT NULL CONSTRAINT DF_supervisor_runs_created DEFAULT SYSUTCDATETIME()
  );
END;

IF OBJECT_ID('dbo.supervisor_lane_results', 'U') IS NULL
BEGIN
  CREATE TABLE dbo.supervisor_lane_results (
    run_id NVARCHAR(120) NOT NULL,
    lane_id NVARCHAR(120) NOT NULL,
    plane NVARCHAR(80) NOT NULL,
    model NVARCHAR(160) NOT NULL,
    ok BIT NOT NULL,
    status NVARCHAR(120) NULL,
    latency_ms INT NULL,
    prompt_tokens INT NULL,
    completion_tokens INT NULL,
    response_preview NVARCHAR(1000) NULL,
    error NVARCHAR(MAX) NULL,
    created_utc DATETIME2 NOT NULL CONSTRAINT DF_supervisor_lane_results_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_supervisor_lane_results PRIMARY KEY(run_id, lane_id)
  );
END;
