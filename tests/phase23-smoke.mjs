import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8"),data=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema23",data.includes("s.schemaVersion=23")],
 ["cash transfers state",data.includes("cashTransfers")],
 ["cash closings state",data.includes("cashClosings")],
 ["reconciliations state",data.includes("cashReconciliations")],
 ["difference account",data.includes("Ajustes y diferencias de caja")],
 ["transfer function",app.includes("function newCashTransfer")],
 ["closing function",app.includes("function newCashClosing")],
 ["reconcile function",app.includes("function reconcileCashClosing")],
 ["transfer atomic",app.includes('localAtomic("Transferencia financiera"')],
 ["closing atomic",app.includes('localAtomic("Cierre de caja"')],
 ["reconcile accounting",app.includes("Conciliación de caja")]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 23 smoke test OK");
