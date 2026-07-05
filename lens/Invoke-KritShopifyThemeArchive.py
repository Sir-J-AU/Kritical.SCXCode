"""
Kritical.SCX.Lens — Shopify THEME ARCHIVE + SLOT-FREEING (.5235)
================================================================
The "download every theme off the store, prove we have it, then delete it to
free the 20-theme cap so the clone/backup can finish" tool the operator asked
for. Enumerates EVERY theme on a store (including ancient unpublished ones),
downloads every asset byte-for-byte, writes a per-asset SHA-256 manifest,
re-verifies the download, and only then (opt-in) DELETEs the theme off the
server.

Built on the documented reusable handlers in kritical_shopify_json.py so it
inherits the JSON-as-string correctness + HKCU token convention.

SAFETY (load-bearing — do not weaken):
  * READ/DOWNLOAD is always allowed on any store, PROD included.
  * DELETE (the slot-freeing write) is REFUSED on the PROD store
    (kriticalptyltd) unconditionally — HR2. Archive PROD, never mutate it.
  * DELETE never touches the live/published theme (role == 'main') or any id
    in --keep. The published theme is the store; freeing it is never the goal.
  * DELETE is opt-in via --delete. Default run = download + manifest + verify
    only (a dry-run that still produces the full local archive).
  * A theme is only eligible for delete AFTER its download re-verifies clean
    (every asset re-hashes to the manifest value). The download IS the backup
    (HR23) — no verified local copy, no delete.

USAGE:
  # Archive every theme on the dev store, no deletes (safe default):
  py -3.14 Invoke-KritShopifyThemeArchive.py --store kritical-1234.myshopify.com

  # Archive + delete every non-published, non-kept theme to free slots:
  py -3.14 Invoke-KritShopifyThemeArchive.py --store kritical-9765.myshopify.com \
      --delete --keep 163009233121,162989342945

  # Archive PROD (download only — deletes always refused there):
  py -3.14 Invoke-KritShopifyThemeArchive.py --store kriticalptyltd.myshopify.com

Output tree (default --out C:\\KriticalSCX\\theme-archive):
  <out>/<store>/theme-<id>-<safe-name>/<asset relpaths...>
  <out>/<store>/theme-<id>-<safe-name>/_manifest.json   (per-asset sha + bytes)
  <out>/<store>/_store-index.json                        (themes + verdicts)

REST endpoints (Admin API 2026-04):
  GET  /themes.json                       -> [{id,name,role,...}]
  GET  /themes/{id}/assets.json           -> [{key,...}] (metadata only)
  GET  /themes/{id}/assets.json?asset[key]=K -> {value|attachment,...}
  DELETE /themes/{id}.json
Rate: REST 2 req/s -> sleep ~0.55 between asset GETs.
"""
from __future__ import annotations
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kritical_shopify_json import hkcu_env, sha256_file, API_VERSION  # documented handlers

PROD_STORE = "kriticalptyltd.myshopify.com"  # HR2: never DELETE here
# HKCU token env name per store (matches vault-env-registry.json convention).
TOKEN_ENV = {
    "kriticalptyltd.myshopify.com": "SHOPIFY_ADMIN_TOKEN_KRITICALPTYLTD",
    "kritical-9765.myshopify.com": "SHOPIFY_ADMIN_TOKEN_K9765",
    "kritical-1234.myshopify.com": "SHOPIFY_ADMIN_TOKEN_K1234",
    "kritical-9999.myshopify.com": "SHOPIFY_ADMIN_TOKEN_K9999",
}


def _req(store, token, path, method="GET", timeout=90, max_retries=6):
    """Admin REST call with 429/5xx retry + Retry-After honoring. Shopify REST is
    2 req/s leaky-bucket; bursts 429. We back off and retry rather than lose the asset."""
    url = f"https://{store}/admin/api/{API_VERSION}/{path}"
    attempt = 0
    while True:
        req = urllib.request.Request(url, method=method,
                                    headers={"X-Shopify-Access-Token": token,
                                             "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = r.read()
                return r.status, (json.loads(body) if body else {})
        except urllib.error.HTTPError as e:
            retryable = e.code == 429 or 500 <= e.code < 600
            if not retryable or attempt >= max_retries:
                raise
            retry_after = e.headers.get("Retry-After")
            wait = float(retry_after) if retry_after else min(2 ** attempt * 0.5, 8.0)
            time.sleep(wait)
            attempt += 1


def list_themes(store, token):
    _, data = _req(store, token, "themes.json")
    return data.get("themes", [])


def list_asset_keys(store, token, theme_id):
    _, data = _req(store, token, f"themes/{theme_id}/assets.json")
    return [a["key"] for a in data.get("assets", [])]


def get_asset(store, token, theme_id, key):
    q = urllib.parse.urlencode({"asset[key]": key})
    _, data = _req(store, token, f"themes/{theme_id}/assets.json?{q}")
    return data.get("asset", {})


def safe_name(name):
    return "".join(c if c.isalnum() or c in "-_" else "-" for c in (name or "theme"))[:60]


def download_theme(store, token, theme, dest_root, sleep):
    theme_id = theme["id"]
    tdir = os.path.join(dest_root, f"theme-{theme_id}-{safe_name(theme.get('name'))}")
    os.makedirs(tdir, exist_ok=True)
    keys = list_asset_keys(store, token, theme_id)
    manifest = {"themeId": theme_id, "name": theme.get("name"), "role": theme.get("role"),
                "assetCount": len(keys), "assets": {}, "errors": []}
    for i, key in enumerate(keys):
        try:
            asset = get_asset(store, token, theme_id, key)
            target = os.path.join(tdir, key.replace("/", os.sep))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            if "attachment" in asset and asset["attachment"] is not None:
                raw = base64.b64decode(asset["attachment"])
                with open(target, "wb") as f:
                    f.write(raw)
            else:
                with open(target, "w", encoding="utf-8", newline="") as f:
                    f.write(asset.get("value", "") or "")
            manifest["assets"][key] = {"sha256": sha256_file(target),
                                       "bytes": os.path.getsize(target)}
        except Exception as e:  # noqa: BLE001 - record + continue, never abort the archive
            manifest["errors"].append({"key": key, "error": str(e)[:200]})
        time.sleep(sleep)
    with open(os.path.join(tdir, "_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    return tdir, manifest


def verify_theme(tdir, manifest):
    """Re-hash every downloaded asset against the manifest. Clean == delete-eligible."""
    if manifest["errors"]:
        return False, f"{len(manifest['errors'])} download errors"
    mismatches = 0
    for key, meta in manifest["assets"].items():
        target = os.path.join(tdir, key.replace("/", os.sep))
        if not os.path.exists(target) or sha256_file(target) != meta["sha256"]:
            mismatches += 1
    return (mismatches == 0), (f"{mismatches} hash mismatch" if mismatches else "verified")


def delete_theme(store, token, theme_id):
    status, _ = _req(store, token, f"themes/{theme_id}.json", method="DELETE")
    return status in (200, 204)


def main():
    ap = argparse.ArgumentParser(description="Archive every Shopify theme off a store, verify, optionally delete to free slots.")
    ap.add_argument("--store", required=True)
    ap.add_argument("--out", default=r"C:\KriticalSCX\theme-archive")
    ap.add_argument("--delete", action="store_true", help="After verified download, DELETE eligible themes off the store (never PROD, never published, never --keep).")
    ap.add_argument("--keep", default="", help="Comma-separated theme ids to never delete.")
    ap.add_argument("--sleep", type=float, default=0.6, help="Seconds between asset GETs (REST 2 req/s; 429s auto-retry with backoff regardless).")
    args = ap.parse_args()

    store = args.store.strip().lower()
    token = hkcu_env(TOKEN_ENV.get(store, ""))
    if not token:
        print(f"[FATAL] no HKCU token for {store} (expected env {TOKEN_ENV.get(store, '?')})")
        sys.exit(2)
    keep = {int(x) for x in args.keep.split(",") if x.strip().isdigit()}
    dest_root = os.path.join(args.out, safe_name(store))
    os.makedirs(dest_root, exist_ok=True)

    themes = list_themes(store, token)
    print(f"[{store}] {len(themes)} themes found (cap is 20). out={dest_root}")
    index = {"store": store, "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             "deleteRequested": args.delete, "prodProtected": store == PROD_STORE,
             "themeCount": len(themes), "themes": []}
    deleted = 0
    for t in themes:
        tid, role, name = t["id"], t.get("role"), t.get("name")
        tdir, manifest = download_theme(store, token, t, dest_root, args.sleep)
        ok, why = verify_theme(tdir, manifest)
        row = {"id": tid, "name": name, "role": role, "assets": manifest["assetCount"],
               "verified": ok, "verifyNote": why, "deleted": False, "deleteSkipReason": None}
        # delete eligibility
        if args.delete:
            if store == PROD_STORE:
                row["deleteSkipReason"] = "HR2: PROD store — deletes refused"
            elif role == "main":
                row["deleteSkipReason"] = "published/live theme — never deleted"
            elif tid in keep:
                row["deleteSkipReason"] = "in --keep list"
            elif not ok:
                row["deleteSkipReason"] = f"download not verified ({why}) — HR23 no-backup-no-delete"
            else:
                row["deleted"] = delete_theme(store, token, tid)
                if row["deleted"]:
                    deleted += 1
                else:
                    row["deleteSkipReason"] = "DELETE API returned non-2xx"
                time.sleep(args.sleep)
        index["themes"].append(row)
        flag = "DELETED" if row["deleted"] else (row["deleteSkipReason"] or ("verified" if ok else why))
        print(f"  theme {tid} [{role or 'unpublished'}] {name!s:50.50} {manifest['assetCount']:4d} assets  {'OK' if ok else 'FAIL':4}  {flag}")

    index["deletedCount"] = deleted
    with open(os.path.join(dest_root, "_store-index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=2)
    verified = sum(1 for r in index["themes"] if r["verified"])
    print(f"\n[{store}] archived {len(themes)} themes ({verified} verified clean), "
          f"{deleted} deleted off server. Slots now free: ~{20 - (len(themes) - deleted)}.")
    print(f"[{store}] index: {os.path.join(dest_root, '_store-index.json')}")


if __name__ == "__main__":
    main()
