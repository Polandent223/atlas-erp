import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8");
const data=fs.readFileSync("assets/data.js","utf8");
const css=fs.readFileSync("assets/app.css","utf8");
const checks=[
 ["PERMISSIONS export",data.includes("export const PERMISSIONS")],
 ["schema18",data.includes("s.schemaVersion=18")],
 ["simple nav",app.includes('["sales","Ventas"]')&&app.includes('["controlCenter","Administración"]')],
 ["permission navigation",app.includes("visibleNavGroups")&&app.includes("moduleAllowed")],
 ["control center",app.includes("function controlCenter()")],
 ["access denied",app.includes("function accessDenied()")],
 ["quick actions",app.includes("Acciones rápidas")],
 ["professional responsive css",css.includes(".control-grid")&&css.includes(".quick-actions")]
];
for(const [name,ok] of checks) if(!ok) throw new Error("Falla: "+name);
console.log("ATLAS Fase 18 smoke test OK");
