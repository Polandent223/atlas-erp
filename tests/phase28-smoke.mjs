import fs from "node:fs";
const a=fs.readFileSync("assets/app.js","utf8"),d=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema28",d.includes("s.schemaVersion=28")],
 ["router",a.includes("function page()")],
 ["inventory",a.includes("function inventory()")],
 ["control",a.includes("function controlCenter()")],
 ["security",a.includes("function securityCenter()")],
 ["permission",a.includes("function requirePermission")],
 ["pin",a.includes("function sensitiveConfirm")],
 ["timeout",a.includes("atlasLastActivity")]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 28 smoke test OK");
