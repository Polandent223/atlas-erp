import fs from "node:fs";const c=fs.readFileSync("assets/cloud-mode.js","utf8"),a=fs.readFileSync("assets/app.js","utf8"),w=fs.readFileSync(".github/workflows/deploy-pages.yml","utf8"),d=fs.readFileSync("assets/data.js","utf8");
if(!d.includes("s.schemaVersion=46"))throw new Error("schema");
for(const x of ["verifyCloudActivation","enableCloudMode","disableCloudMode","isCloudMode"])if(!c.includes(x))throw new Error(x);
for(const x of ["mountingStatusPage","verifyCloudActivationBtn","enableCloudModeBtn","disableCloudModeBtn"])if(!a.includes(x))throw new Error(x);
for(const x of ["actions/configure-pages@v5","actions/upload-pages-artifact@v3","actions/deploy-pages@v4"])if(!w.includes(x))throw new Error(x);
console.log("ATLAS Fase 46 mounting contract OK");