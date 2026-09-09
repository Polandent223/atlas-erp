from pathlib import Path
root=Path(__file__).resolve().parents[1]
required=[
 "index.html","assets/app.js","assets/data.js","assets/config.js","assets/supabase.js",
 "assets/repositories.js","assets/sync.js","sql/schema_phase9.sql"
]
missing=[p for p in required if not (root/p).exists()]
if missing: raise SystemExit("Faltan: "+", ".join(missing))
app=(root/"assets/app.js").read_text(encoding="utf-8")
checks=["RemoteRepo.transferStock","RemoteRepo.returnSale","RemoteRepo.createExpense","editRolePermissions","syncCoreNow"]
bad=[c for c in checks if c not in app]
if bad: raise SystemExit("Faltan integraciones: "+", ".join(bad))
print("ATLAS Fase 9: validación estructural OK")
