CREATE TABLE IF NOT EXISTS supervisor_runs (
  run_id TEXT PRIMARY KEY,
  task TEXT NOT NULL,
  mode TEXT NOT NULL,
  created_utc TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS supervisor_lane_results (
  run_id TEXT NOT NULL,
  lane_id TEXT NOT NULL,
  plane TEXT NOT NULL,
  model TEXT NOT NULL,
  ok INTEGER NOT NULL,
  status TEXT,
  latency_ms INTEGER,
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  response_preview TEXT,
  error TEXT,
  created_utc TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(run_id, lane_id)
);
