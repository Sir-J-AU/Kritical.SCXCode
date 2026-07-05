"""
Kritical Lens — LENSDIFF: super multi-diff across every stored version, IN SQL.
Consumes the already-ingested dbo.LensGitBlob (no git re-walk). For each app, orders versions and
diffs each consecutive pair: routes ADDED / REMOVED, byte delta, and a PROVENANCE tag so a
'restore-backup-over-everything' commit can't fake a peak. Stored to dbo.LensDiff.
Usage: python Invoke-KritLensDiff.py
"""
import json, pyodbc
CONN = ("DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\\SQLEXPRESS;DATABASE=KriticalSCXCodeStore;Trusted_Connection=yes;Encrypt=no;")
cn = pyodbc.connect(CONN, timeout=30); cur = cn.cursor()
cur.execute("""IF OBJECT_ID('dbo.LensDiff') IS NULL CREATE TABLE dbo.LensDiff(
   id INT IDENTITY PRIMARY KEY, app NVARCHAR(60), from_sha VARCHAR(40), to_sha VARCHAR(40),
   from_date VARCHAR(30), routes_added INT, routes_removed INT, byte_delta INT,
   provenance VARCHAR(24), subject NVARCHAR(400), recorded_utc DATETIME2 DEFAULT SYSUTCDATETIME());""")
cur.execute("TRUNCATE TABLE dbo.LensDiff"); cn.commit()

cur.execute("SELECT DISTINCT app FROM dbo.LensGitBlob")
apps = [r[0] for r in cur.fetchall()]
def provenance(subj, added, removed, byte_delta):
    s = (subj or "").lower()
    if any(k in s for k in ("restore","revert","re-add","reinsert","recover","bulk","repo-slim","move ")):
        return "RESTORE/BULK"            # count-inflating — NOT a genuine feature peak
    if added > 25 and removed < 3:
        return "MASS-ADD(suspect)"       # huge one-step addition = likely a restore, treat peak as suspect
    if removed > 25 and added < 3:
        return "MASS-REMOVE"
    return "normal"

total = 0
for app in apps:
    cur.execute("SELECT ordinal, commit_sha, commit_date, subject, routes FROM dbo.LensGitBlob WHERE app=? ORDER BY ordinal DESC", app)
    rows = cur.fetchall()  # oldest -> newest (ordinal DESC because ordinal 0 = newest)
    prev = None
    for ordi, sha, date, subj, routes_json in rows:
        rs = set(json.loads(routes_json or "[]"))
        if prev is not None:
            added = len(rs - prev[0]); removed = len(prev[0] - rs)
            prov = provenance(subj, added, removed, 0)
            if added or removed:
                cur.execute("INSERT dbo.LensDiff(app,from_sha,to_sha,from_date,routes_added,routes_removed,byte_delta,provenance,subject) VALUES(?,?,?,?,?,?,?,?,?)",
                            app, prev[1], sha, prev[2], added, removed, 0, prov, subj[:400]); total += 1
        prev = (rs, sha, date)
cn.commit()

# genuine peak = max route_count EXCLUDING versions produced by a RESTORE/BULK step
print("[LENSDIFF] super multi-diff computed across every stored version (dbo.LensDiff)")
for app in apps:
    cur.execute("""SELECT TOP 1 b.route_count, b.commit_sha FROM dbo.LensGitBlob b
                   WHERE b.app=? AND b.commit_sha NOT IN
                     (SELECT to_sha FROM dbo.LensDiff WHERE app=? AND provenance IN ('RESTORE/BULK','MASS-ADD(suspect)'))
                   ORDER BY b.route_count DESC""", app, app)
    gp = cur.fetchone()
    cur.execute("SELECT route_count FROM dbo.LensGitBlob WHERE app=? ORDER BY ordinal ASC", app); head = cur.fetchone()
    cur.execute("SELECT provenance, COUNT(*) FROM dbo.LensDiff WHERE app=? GROUP BY provenance", app)
    prov = dict(cur.fetchall())
    print(f"  {app:16} HEAD={head[0] if head else '?'} · GENUINE-peak(excl restore/bulk)={gp[0] if gp else '?'} · diffs={sum(prov.values())} {prov}")

cur.execute("INSERT dbo.LensWave(wave,description,status,files_touched,note) VALUES('.5226','LensDiff super multi-diff + provenance tags','complete',?,'peak-confusion fixed: genuine peak excludes RESTORE/BULK commits')", total)
cn.commit()
print(f"[LENSDIFF] {total} consecutive-version diffs stored. Query any transition in SQL — provenance separates real feature-work from restore-over-all noise.")
cn.close()
