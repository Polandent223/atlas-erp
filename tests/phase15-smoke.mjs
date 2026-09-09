import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8");
const data=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["integrity audit",app.includes("runIntegrityAudit")],
 ["negative cash guard",app.includes("allowNegativeCash")],
 ["negative stock guard",app.includes("allowNegativeStock")],
 ["state hardening",data.includes("function hardenState")],
 ["schema v15 assignment",data.includes("s.schemaVersion=15")],
 ["backup v15",/version\s*:\s*15/.test(data)]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 15 smoke test OK");
