import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8");
const data=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema 16",data.includes("s.schemaVersion=16")],
 ["document counters",data.includes("documentCounters")],
 ["customer credits",data.includes("customerCredits")],
 ["payment helper",app.includes("activePaymentMethods")],
 ["return reconciliation",app.includes("reconcileReceivableForReturn")],
 ["customer credit helper",app.includes("addCustomerCredit")],
 ["journal guard",app.includes("assertJournalBalanced")],
 ["duplicate document audit",app.includes("Número de venta duplicado")]
];
for(const [name,ok] of checks)if(!ok)throw new Error("Falla: "+name);
console.log("ATLAS Fase 16 smoke test OK");
