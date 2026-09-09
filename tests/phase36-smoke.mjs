import fs from "node:fs";
const d=fs.readFileSync("assets/data.js","utf8"),a=fs.readFileSync("assets/app.js","utf8"),m=fs.readFileSync("assets/migration-mapper.js","utf8");
for(const [n,ok] of [["schema36",d.includes("s.schemaVersion=36")],["mapper",a.includes("./migration-mapper.js")],["page",a.includes("function migrationMappingPage")],["refs",m.includes("validateReferences")],["coverage",m.includes("mappingCoverage")]])if(!ok)throw new Error(n);
console.log("ATLAS Fase 36 smoke test OK");
