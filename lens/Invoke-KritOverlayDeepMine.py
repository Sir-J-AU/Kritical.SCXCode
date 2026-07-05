"""
Kritical Lens — OVERLAY DEEP MINE (.5234): per-version ingest of theme-layers/overlay/** history
(the deep churn body) into dbo.LensGitBlob with --follow (pre-refolder lineage). RESUMABLE:
skips files whose newest commit is already stored; safe to re-run until complete.
Usage: python Invoke-KritOverlayDeepMine.py <connectorRepoRoot> [maxFiles]
"""
import sys, os, re, json, hashlib, subprocess, pyodbc

REPO = os.path.abspath(sys.argv[1])
MAX_FILES = int(sys.argv[2]) if len(sys.argv) > 2 else 100000
CONN = ("DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\\SQLEXPRESS;DATABASE=KriticalSCXCodeStore;Trusted_Connection=yes;Encrypt=no;")
ROOT = "theme-layers/overlay"
EXT = re.compile(r"\.(liquid|json|css|js|svg)$", re.I)

def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True, errors="replace")

files = [f for f in git("ls-files", ROOT + "/*").stdout.splitlines()
         if EXT.search(f) and "/_attic/" not in f and ".bak" not in f and ".deprecated." not in f]
print(f"[OVERLAY-MINE] candidate files: {len(files)}")

cn = pyodbc.connect(CONN, timeout=90); cur = cn.cursor()
done_files = 0; new_versions = 0; skipped = 0
for n, rel in enumerate(files):
    if done_files >= MAX_FILES: break
    app = ("overlay:" + rel[len(ROOT) + 1:])[:60]
    log = git("log", "--follow", "--format=%H|%cI|%s", "--", rel)
    commits = [l.split("|", 2) for l in log.stdout.splitlines() if l.strip()]
    if not commits: continue
    # RESUME CHECK: newest commit already stored for this app -> skip file
    cur.execute("SELECT COUNT(*) FROM dbo.LensGitBlob WHERE app=? AND commit_sha=?", app, commits[0][0])
    if cur.fetchone()[0]:
        skipped += 1; continue
    cur.execute("DELETE FROM dbo.LensGitBlob WHERE app=?", app)   # partial rows from an interrupted run
    for i, parts in enumerate(commits):
        if len(parts) < 3: continue
        sha, date, subj = parts
        # --follow may cross renames; ask git for the path at that commit via name-only diff? simplest: try current path then log the miss
        blob = git("show", f"{sha}:{rel}")
        if blob.returncode != 0:
            # renamed earlier in history — resolve the old path at that commit
            nm = git("log", "--follow", "--format=%H", "--name-only", "-1", sha, "--", rel)
            lines = [l for l in nm.stdout.splitlines() if l.strip() and not re.match(r'^[0-9a-f]{40}$', l)]
            if lines:
                blob = git("show", f"{sha}:{lines[-1]}")
            if blob.returncode != 0: continue
        text = blob.stdout
        csha = hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()
        try:
            cur.execute("""INSERT dbo.LensGitBlob(app,path,commit_sha,commit_date,subject,byte_len,content_sha256,route_count,routes,content_gz,ordinal)
                VALUES(?,?,?,?,?,?,?,0,'[]',COMPRESS(CAST(? AS NVARCHAR(MAX))),?)""",
                app, rel[:300], sha, date, subj[:400], len(text.encode()), csha, text, i)
            new_versions += 1
        except pyodbc.IntegrityError:
            pass
    done_files += 1
    if done_files % 50 == 0:
        cn.commit(); print(f"  ...{done_files} files mined, {new_versions} versions, {skipped} already-done")
cn.commit()
cur.execute("SELECT COUNT(*) FROM dbo.LensGitBlob WHERE app LIKE 'overlay:%'")
total = cur.fetchone()[0]
print(f"[OVERLAY-MINE] pass complete: +{new_versions} new versions this run · {skipped} files already mined · overlay total in SQL: {total}")
remaining = len(files) - skipped - done_files
print(f"[OVERLAY-MINE] remaining files (re-run to resume): {max(0, remaining)}")
cn.close()
