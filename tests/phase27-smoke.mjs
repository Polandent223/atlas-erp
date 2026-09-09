import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8"),data=fs.readFileSync("assets/data.js","utf8"),css=fs.readFileSync("assets/app.css","utf8");
for(const [n,ok] of [["schema",data.includes("s.schemaVersion=27")],["dash",app.includes("atlas-dashboard")],["kpi",app.includes("kpi-grid")],["quick",app.includes("Acciones rápidas")],["alerts",app.includes("Alertas y notificaciones")],["theme",css.includes("--atlas-navy")],["mobile",css.includes("@media(max-width:760px)")]])if(!ok)throw new Error(n);
console.log("ATLAS Fase 27 smoke test OK");
