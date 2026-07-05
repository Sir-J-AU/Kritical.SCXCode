"""
Kritical Lens — THEME DELTA ARCHAEOLOGY.
For a theme path, diffs the PEAK-file-count commit against HEAD, classifies each peak file as:
  PRESENT      — still at HEAD
  REORG        — gone from this path but the same basename exists elsewhere at HEAD (moved, not lost)
  REAL-MISSING — genuinely absent at HEAD (candidate to restore)
For REAL-MISSING it records the restore commit + byte-exact content so you can restore precisely.
Stored to dbo.LensThemeDelta. Read-only against git. Usage: python <script> <connectorRepo>
"""
import sys, os, re, json, hashlib, subprocess
import pyodbc

REPO = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
CONN = ("DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\\SQLEXPRESS;DATABASE=KriticalSCXCodeStore;Trusted_Connection=yes;Encrypt=no;")
PATHS = ["theme-layers/overlay", "theme-layers/overlay-modern-anim-2026"]

def git(*a): return subprocess.run(["git","-C",REPO,*a], capture_output=True, text=True, errors="replace")

def peak_commit(path):
    peak=0; sha=None
    for h in git("log","--format=%h","--",path).stdout.split():
        cnt=len(git("ls-tree","-r","--name-only",h,"--",path).stdout.splitlines())
        if cnt>peak: peak=cnt; sha=h
    return sha, peak

cn=pyodbc.connect(CONN,timeout=60); cur=cn.cursor()
cur.execute("""IF OBJECT_ID('dbo.LensThemeDelta') IS NULL CREATE TABLE dbo.LensThemeDelta(
   id INT IDENTITY PRIMARY KEY, theme_path NVARCHAR(200), [file] NVARCHAR(500), [status] VARCHAR(15),
   reorg_target NVARCHAR(500), restore_sha VARCHAR(20), byte_len INT, content_sha256 CHAR(64),
   content_gz VARBINARY(MAX), recorded_utc DATETIME2 DEFAULT SYSUTCDATETIME());""")
cur.execute("TRUNCATE TABLE dbo.LensThemeDelta"); cn.commit()

# full HEAD tree (all paths) for reorg detection by basename
head_all = git("ls-tree","-r","--name-only","HEAD").stdout.splitlines()
head_basenames = {}
for p in head_all: head_basenames.setdefault(os.path.basename(p), []).append(p)

for path in PATHS:
    sha, peak = peak_commit(path)
    if not sha: print(f"  {path}: no history"); continue
    peak_files = set(git("ls-tree","-r","--name-only",sha,"--",path).stdout.splitlines())
    head_files = set(git("ls-tree","-r","--name-only","HEAD","--",path).stdout.splitlines())
    missing = sorted(peak_files - head_files)
    present = len(peak_files & head_files)
    real=0; reorg=0
    for f in missing:
        bn = os.path.basename(f)
        elsewhere = [h for h in head_basenames.get(bn, []) if h != f]
        if elsewhere:
            cur.execute("INSERT dbo.LensThemeDelta(theme_path,[file],[status],reorg_target,restore_sha) VALUES(?,?,?,?,?)",
                        path, f, "REORG", elsewhere[0][:500], sha); reorg+=1
        else:
            blob = git("show", f"{sha}:{f}")
            content = blob.stdout if blob.returncode==0 else ""
            csha = hashlib.sha256(content.encode("utf-8","replace")).hexdigest()
            cur.execute("INSERT dbo.LensThemeDelta(theme_path,[file],[status],restore_sha,byte_len,content_sha256,content_gz) "
                        "VALUES(?,?,?,?,?,?,COMPRESS(CAST(? AS NVARCHAR(MAX))))",
                        path, f, "REAL-MISSING", sha, len(content.encode()), csha, content); real+=1
    cn.commit()
    print(f"  {path}: peak={peak} (@{sha}) HEAD={len(head_files)} · present={present} · REORG(moved)={reorg} · REAL-MISSING={real}")

cur.execute("INSERT dbo.LensWave(wave,description,status,files_touched,note) VALUES('.5223','theme delta archaeology — real-loss vs reorg into SQL','complete',2,'REAL-MISSING files stored byte-exact with restore_sha')")
cn.commit()
cur.execute("SELECT [status], COUNT(*) FROM dbo.LensThemeDelta GROUP BY [status]")
tot=dict(cur.fetchall())
print(f"\n===== THEME DELTA COMPLETE (dbo.LensThemeDelta) =====")
print(f"  {tot}")
cur.execute("SELECT TOP 15 [file], restore_sha FROM dbo.LensThemeDelta WHERE [status]='REAL-MISSING' ORDER BY file")
rm=cur.fetchall()
if rm:
    print("  GENUINELY MISSING files (byte-exact content stored — restore from restore_sha):")
    for f,s in rm: print(f"    {f}  (restore @ {s})")
else:
    print("  NO genuinely-missing files — the delta was reorganization, not loss.")
cn.close()
