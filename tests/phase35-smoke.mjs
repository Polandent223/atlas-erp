import fs from "node:fs";
const d=fs.readFileSync("assets/data.js","utf8"),a=fs.readFileSync("assets/app.js","utf8"),e=fs.readFileSync("assets/cloud-import-executor.js","utf8");
for(const [n,ok] of [["schema35",d.includes("s.schemaVersion=35")],["executor",a.includes("./cloud-import-executor.js")],["activation",a.includes("function cloudActivationPage")],["dryrun",e.includes("dryRun=true")],["id guard",e.includes("mapa de identificadores")]])if(!ok)throw new Error(n);
console.log("ATLAS Fase 35 smoke test OK");
