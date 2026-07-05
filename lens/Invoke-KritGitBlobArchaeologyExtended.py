"""
Kritical Lens — GIT-BLOB ARCHAEOLOGY (EXTENDED, .5227): the unfinished half of the archaeological dig.
The base Invoke-KritGitBlobArchaeology.py ingests every version of the 4 APP SERVER files. This extends
the SAME dbo.LensGitBlob table to every version of:
  - the canonical Shopify THEME tree (KriticalPax8ToShopify/ShopifyTheme/** liquid/json/css/js), and
  - the backend ROUTE-MODULES (shopify-app/backend/src/routes/*.js — where the routes actually live).
So ANY version of ANY theme file or route module can be diffed against ANY other IN SQL.

ADDITIVE (HR29): does NOT truncate — only re-writes its own 'theme:' / 'route:' rows (idempotent),
leaving the base 4-app rows intact. Read-only against git (no working-tree changes).
Usage: python Invoke-KritGitBlobArchaeologyExtended.py <connectorRepoRoot>
"""
import sys, os, re, json, hashlib, subprocess
import pyodbc

REPO = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
CONN = ("DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\\SQLEXPRESS;DATABASE=KriticalSCXCodeStore;Trusted_Connection=yes;Encrypt=no;")
THEME_ROOT = "KriticalPax8ToShopify/ShopifyTheme"
ROUTES_GLOB = "shopify-app/backend/src/routes"

# route METHOD+PATH so route-modules can be set-diffed across versions (same rules as the base script)
ROUTE_RX = re.compile(r"""(?:app|fastify|router|server)\.(get|post|put|delete|patch)\(\s*['"`]([^'"`]+)['"`]""", re.I)
ROUTE_RX2 = re.compile(r"""\.route\(\s*\{[^}]*?method\s*:\s*['"`]([^'"`]+)['"`][^}]*?url\s*:\s*['"`]([^'"`]+)['"`]""", re.I | re.S)

def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True, errors="replace")

def routes_of(text):
    rs = set()
    for m in ROUTE_RX.finditer(text): rs.add(f"{m.group(1).upper()} {m.group(2)}")
    for m in ROUTE_RX2.finditer(text): rs.add(f"{m.group(1).upper()} {m.group(2)}")
    return sorted(rs)

def ls(pathspec):
    r = git("ls-files", pathspec)
    return [l for l in r.stdout.splitlines() if l.strip()]

# --- discover the target file sets ---
theme_files = [f for f in ls(f"{THEME_ROOT}/*")
               if re.search(r"\.(liquid|json|css|js)$", f, re.I) and "/_attic/" not in f]
route_files = [f for f in ls(f"{ROUTES_GLOB}/*")
               if re.search(r"\.(js|ts|mjs)$", f, re.I) and ".bak" not in f and "node_modules" not in f]

print(f"[GIT-BLOB-EXT] REPO={REPO}")
print(f"[GIT-BLOB-EXT] theme files={len(theme_files)}  route-modules={len(route_files)}")

cn = pyodbc.connect(CONN, timeout=90); cur = cn.cursor()
cur.execute("""IF OBJECT_ID('dbo.LensGitBlob') IS NULL CREATE TABLE dbo.LensGitBlob(
   id INT IDENTITY PRIMARY KEY, app NVARCHAR(60), path NVARCHAR(300), commit_sha VARCHAR(40),
   commit_date VARCHAR(30), subject NVARCHAR(400), byte_len INT, content_sha256 CHAR(64),
   route_count INT, routes NVARCHAR(MAX), content_gz VARBINARY(MAX), ordinal INT,
   CONSTRAINT UX_gitblob UNIQUE(app, commit_sha));""")
# idempotent + additive: clear only our own extended rows, keep the base 4-app rows
cur.execute("DELETE FROM dbo.LensGitBlob WHERE app LIKE 'theme:%' OR app LIKE 'route:%'")
cn.commit()

def ingest(kind, rel, extract_routes):
    """Ingest every git version of one file. app = '<kind>:<relpath-under-root>'. Returns versions written."""
    if kind == "theme":
        app = "theme:" + rel[len(THEME_ROOT) + 1:]
    else:
        app = "route:" + rel[len(ROUTES_GLOB) + 1:]
    app = app[:60]  # NVARCHAR(60)
    log = git("log", "--format=%H|%cI|%s", "--", rel)
    commits = [l.split("|", 2) for l in log.stdout.splitlines() if l.strip()]
    written = 0
    for i, parts in enumerate(commits):
        if len(parts) < 3: continue
        sha, date, subj = parts
        blob = git("show", f"{sha}:{rel}")
        if blob.returncode != 0: continue
        text = blob.stdout
        rs = routes_of(text) if extract_routes else []
        csha = hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()
        try:
            cur.execute("""INSERT dbo.LensGitBlob(app,path,commit_sha,commit_date,subject,byte_len,content_sha256,route_count,routes,content_gz,ordinal)
                VALUES(?,?,?,?,?,?,?,?,?,COMPRESS(CAST(? AS NVARCHAR(MAX))),?)""",
                app, rel[:300], sha, date, subj[:400], len(text.encode()), csha, len(rs), json.dumps(rs), text, i)
            written += 1
        except pyodbc.IntegrityError:
            pass  # (app, commit_sha) already present — same file unchanged across a merge; skip
    return app, written

print("[GIT-BLOB-EXT] ingesting every version of each theme file (this walks full history — patience)...")
theme_versions = 0; theme_apps = 0
for n, f in enumerate(theme_files):
    _, w = ingest("theme", f, extract_routes=False)
    theme_versions += w; theme_apps += 1 if w else 0
    if (n + 1) % 100 == 0:
        cn.commit(); print(f"    ...{n+1}/{len(theme_files)} theme files, {theme_versions} versions so far")
cn.commit()
print(f"[GIT-BLOB-EXT] theme: {theme_versions} file-versions across {theme_apps} files")

print("[GIT-BLOB-EXT] ingesting every version of each route-module (with route sets)...")
route_versions = 0
for f in route_files:
    app, w = ingest("route", f, extract_routes=True)
    route_versions += w
    print(f"    {app:40} {w} versions")
cn.commit()
print(f"[GIT-BLOB-EXT] routes: {route_versions} file-versions across {len(route_files)} modules")

# ---------- SQL-side analysis ----------
print("\n===== ROUTE-MODULE ROUTE ARCHAEOLOGY (from SQL) =====")
cur.execute("SELECT DISTINCT app FROM dbo.LensGitBlob WHERE app LIKE 'route:%' ORDER BY app")
for (app,) in cur.fetchall():
    cur.execute("SELECT TOP 1 route_count, routes FROM dbo.LensGitBlob WHERE app=? ORDER BY ordinal ASC", app)   # HEAD
    head = cur.fetchone()
    cur.execute("SELECT TOP 1 route_count, routes FROM dbo.LensGitBlob WHERE app=? ORDER BY route_count DESC", app)  # peak
    peak = cur.fetchone()
    cur.execute("SELECT COUNT(*) FROM dbo.LensGitBlob WHERE app=?", app); nver = cur.fetchone()[0]
    if not head or not peak: continue
    only_in_peak = sorted(set(json.loads(peak[1])) - set(json.loads(head[1])))
    flag = f" · PEAK-not-HEAD={len(only_in_peak)}" if only_in_peak else ""
    print(f"  {app:40} {nver:3} versions · HEAD routes={head[0]:3} · peak={peak[0]:3}{flag}")

print("\n===== THEME CHURN (top 12 most-revised theme files, from SQL) =====")
cur.execute("""SELECT TOP 12 app, COUNT(*) versions, MAX(byte_len) max_bytes
               FROM dbo.LensGitBlob WHERE app LIKE 'theme:%' GROUP BY app ORDER BY COUNT(*) DESC""")
for app, v, mb in cur.fetchall():
    print(f"  {app:46} {v:3} versions · max {mb:>7} bytes")

total_ext = theme_versions + route_versions
cur.execute("""INSERT dbo.LensWave(wave,description,status,files_touched,note)
   VALUES('.5227','git-blob archaeology EXTENDED: theme tree + route-modules every version -> SQL','complete',?,
   'diff any theme file / route module version vs any other in dbo.LensGitBlob (app LIKE theme:% / route:%)')""", total_ext)
cn.commit()
cur.execute("SELECT COUNT(*), COUNT(DISTINCT app) FROM dbo.LensGitBlob"); n, a = cur.fetchone()
cn.close()
print(f"\n[GIT-BLOB-EXT] COMPLETE — extended by {total_ext} file-versions.")
print(f"  dbo.LensGitBlob now holds {n} versions across {a} tracked files (4 apps + theme + route-modules).")
print("  Diff any theme file across history, e.g.:")
print("    SELECT app,commit_date,byte_len,subject FROM dbo.LensGitBlob WHERE app='theme:layout/theme.liquid' ORDER BY ordinal;")
print("  Reassemble any version byte-exact: SELECT CAST(DECOMPRESS(content_gz) AS NVARCHAR(MAX)) FROM dbo.LensGitBlob WHERE id=<id>;")
