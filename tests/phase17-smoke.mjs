import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8");
const data=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema17",data.includes("s.schemaVersion=17")],
 ["load fixed",data.includes("hardenState(normalizeState(JSON.parse(raw)))")],
 ["atomic DB",data.includes("atomic(work)")],
 ["cash guard",data.includes("Saldo insuficiente")],
 ["customer credit account",data.includes("Créditos a clientes")],
 ["sale payment method",app.includes("salePaymentMethod")],
 ["return AR reconciliation",app.includes("reconcileReceivableForReturn")],
 ["customer credit accounting",app.includes('accountByName("Créditos a clientes")')],
 ["journal account audit",app.includes("cuenta contable inexistente")]
];
for(const [n,ok] of checks) if(!ok) throw new Error("Falla: "+n);
console.log("ATLAS Fase 17 smoke test OK");
