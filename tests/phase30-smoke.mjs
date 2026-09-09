import fs from "node:fs";
const a=fs.readFileSync("assets/app.js","utf8"),d=fs.readFileSync("assets/data.js","utf8");
const checks=[["schema30",d.includes("s.schemaVersion=30")],["fiscal",d.includes("fiscalConfig")],["page",a.includes("function fiscalPage")],["edit",a.includes("function editFiscalConfig")],["tax",a.includes("function configuredTaxRate")],["igtf",a.includes("function configuredIgtfRate")],["sale prefix",a.includes('nextConfiguredDoc("sale","V")')],["purchase prefix",a.includes('nextConfiguredDoc("purchase","C")')]];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 30 smoke test OK");
