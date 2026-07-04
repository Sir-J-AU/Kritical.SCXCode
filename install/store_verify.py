"""Round-trip fidelity check for KriticalSCXCodeStore: for every stored row, DECOMPRESS the
content and re-hash it (UTF-8, same as ingest) — it must equal the stored content_sha256.
COMPRESS/DECOMPRESS is lossless, so this proves the store returns exactly what went in."""
import pyodbc, hashlib, sys

cn = pyodbc.connect(
    "DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\\SQLEXPRESS;"
    "DATABASE=KriticalSCXCodeStore;Trusted_Connection=yes;Encrypt=no;", timeout=20)
cur = cn.cursor()
tables = [
    ("decision_log", "content_gz", "content_sha256"),
    ("lens_artifact", "content_gz", "content_sha256"),
    ("context_shard", "content_gz", "content_sha256"),
]
grand_total = grand_ok = 0
for tbl, col, shacol in tables:
    total = ok = 0
    for sha, content in cur.execute(
            f"SELECT {shacol}, CAST(DECOMPRESS({col}) AS NVARCHAR(MAX)) "
            f"FROM dbo.{tbl} WHERE {col} IS NOT NULL"):
        total += 1
        if content is not None:
            rehash = hashlib.sha256(content.encode("utf-8", "replace")).hexdigest().upper()
            if rehash == (sha or "").upper():
                ok += 1
            else:
                print(f"  MISMATCH {tbl} stored={sha[:16]} rehash={rehash[:16]}")
    grand_total += total; grand_ok += ok
    pct = (100.0 * ok / total) if total else 100.0
    print(f"  {tbl:<14} {ok}/{total} hash-match ({pct:.1f}%)")
pct = (100.0 * grand_ok / grand_total) if grand_total else 100.0
print(f"TOTAL FIDELITY: {grand_ok}/{grand_total} rows lossless ({pct:.1f}%)")
cn.close()
sys.exit(0 if grand_ok == grand_total else 1)
