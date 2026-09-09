import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8");
const data=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema22",data.includes("s.schemaVersion=22")],
 ["credits UI",app.includes("Créditos a favor de clientes")],
 ["apply credit",app.includes("function applyCustomerCredit")],
 ["cash refund",app.includes("Reembolso devolución")],
 ["refund metadata",app.includes("refundAccountId,refundPaymentMethodId")],
 ["void sale",app.includes("function voidSale")],
 ["void audit",app.includes('"VOID","sale"')],
 ["credit accounting",app.includes("Aplicación de crédito a favor")],
 ["void protection",app.includes("ya tiene cobros aplicados")]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 22 smoke test OK");
