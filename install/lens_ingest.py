"""Ingest a Lens JSON artifact into KriticalSCXCodeStore.dbo.lens_artifact (compressed, deduped).
Usage: python lens_ingest.py <tool> <jsonPath> <root>"""
import sys, hashlib, pyodbc

try:
    tool, path, root = sys.argv[1], sys.argv[2], sys.argv[3]
    data = open(path, "r", encoding="utf-8", errors="replace").read()
    if not data.strip():
        print(f"{tool}: empty output, skipped"); sys.exit(0)
    sha = hashlib.sha256(data.encode("utf-8", "replace")).hexdigest().upper()
    cn = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\\SQLEXPRESS;"
        "DATABASE=KriticalSCXCodeStore;Trusted_Connection=yes;Encrypt=no;", timeout=15)
    cur = cn.cursor()
    cur.execute(
        "IF NOT EXISTS(SELECT 1 FROM dbo.lens_artifact WHERE tool=? AND content_sha256=?) "
        "INSERT dbo.lens_artifact(tool,root,content_sha256,content_gz,byte_len) "
        "VALUES(?,?,?,COMPRESS(CAST(? AS NVARCHAR(MAX))),?)",
        tool, sha, tool, root, sha, data, len(data))
    cn.commit()
    cur.execute("SELECT COUNT(*) FROM dbo.lens_artifact WHERE tool=?", tool)
    print(f"{tool}: {len(data)} bytes, total rows={cur.fetchone()[0]}")
    cn.close()
except Exception as e:
    print(f"{sys.argv[1] if len(sys.argv)>1 else 'lens'}: ingest error — {e}"); sys.exit(0)
