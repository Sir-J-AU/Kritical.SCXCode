"""
Kritical Lens — NETLINK ANIMATION PARITY (.5232): quantifies whether the Netlink 'pretties'
(hover rules, @keyframes, animation uses) survive in a 2026-SBOM theme build. Extracts every
visual atom from theme-layers/netlink-vanilla CSS and checks its presence in the target build.
Stores per-atom rows to dbo.LensAnimationParity. Baseline .5232: 335 atoms -> 328 present (97%);
the 7 missing are all mfp-* (Magnific Popup) + selectal-* — libraries deliberately retired by the
2026 SBOM (replaced by Dawn details-modal / native selects). Keyframes 20/20, animation-uses 29/29.
Usage: python Invoke-KritNetlinkAnimationParity.py <connectorRepo> <targetThemeDir>
"""
import os, re, sys, pyodbc
CONN_REPO = os.path.abspath(sys.argv[1]); TARGET = os.path.abspath(sys.argv[2])
NET = os.path.join(CONN_REPO, "theme-layers", "netlink-vanilla")
RULE_RX = re.compile(r'([^{}]+)\{([^{}]*)\}', re.S)
KEY_RX = re.compile(r'@keyframes\s+([A-Za-z0-9_-]+)')
def atoms(root):
    out = {}
    for dp, _d, fs in os.walk(root):
        for f in fs:
            if not f.endswith('.css') or '.bak' in f: continue
            try: txt = open(os.path.join(dp, f), encoding='utf-8', errors='replace').read()
            except OSError: continue
            for name in KEY_RX.findall(txt): out[('keyframes', name)] = f
            for sel, body in RULE_RX.findall(txt):
                sel = ' '.join(sel.split())[-120:]
                if ':hover' in sel and any(p in body for p in ('transform','transition','opacity','box-shadow','background','color','scale')):
                    out[('hover', sel)] = f
                if 'animation' in body and '@' not in sel: out[('animation-use', sel)] = f
    return out
net = atoms(os.path.join(NET, "assets")); pack = atoms(os.path.join(TARGET, "assets"))
present = sum(1 for k in net if k in pack)
print(f"NETLINK atoms={len(net)} present={present} ({100*present//max(1,len(net))}%) missing={len(net)-present}")
cn = pyodbc.connect('DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\SQLEXPRESS;DATABASE=KriticalSCXCodeStore;Trusted_Connection=yes;Encrypt=no;', timeout=30); cur = cn.cursor()
cur.execute("IF OBJECT_ID('dbo.LensAnimationParity') IS NULL CREATE TABLE dbo.LensAnimationParity(id INT IDENTITY PRIMARY KEY, kind VARCHAR(20), atom NVARCHAR(300), netlink_file NVARCHAR(120), in_pack BIT, recorded_utc DATETIME2 DEFAULT SYSUTCDATETIME())")
cur.execute("TRUNCATE TABLE dbo.LensAnimationParity")
for (kind, key), src in net.items():
    cur.execute("INSERT dbo.LensAnimationParity(kind, atom, netlink_file, in_pack) VALUES(?,?,?,?)", kind, key[:300], src[:120], (kind, key) in pack)
cn.commit(); cn.close()
print("-> dbo.LensAnimationParity refreshed")
