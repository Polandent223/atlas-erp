import fs from "node:fs";
const a=fs.readFileSync("assets/app.js","utf8"),d=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema31",d.includes("s.schemaVersion=31")],
 ["backup envelope",a.includes("function backupEnvelope")],
 ["backup validation",a.includes("function validateBackupEnvelope")],
 ["safe restore",a.includes("function restoreSafeBackup")],
 ["health",a.includes("function installationHealth")],
 ["maintenance",a.includes("function maintenancePage")],
 ["storage continuity",a.includes('atlas_phase3_data')]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 31 smoke test OK");
