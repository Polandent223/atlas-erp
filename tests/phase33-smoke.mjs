import fs from "node:fs";
const d=fs.readFileSync("assets/data.js","utf8"),a=fs.readFileSync("assets/app.js","utf8"),m=fs.readFileSync("assets/migration.js","utf8");
const checks=[["schema33",d.includes("s.schemaVersion=33")],["migration import",a.includes('from "./migration.js"')],["page",a.includes("function migrationPage")],["export",a.includes("function exportMigrationPackage")],["builder",m.includes("buildMigrationPackage")],["validator",m.includes("validateMigrationPackage")],["no pin export",!m.includes("pin:u.pin")]];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 33 smoke test OK");
