import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8"),data=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema24",data.includes("s.schemaVersion=24")],
 ["purchaseReturns",data.includes("purchaseReturns")],
 ["supplierCredits",data.includes("supplierCredits")],
 ["supplier credit account",data.includes("Créditos de proveedores")],
 ["purchase return fn",app.includes("function newPurchaseReturn")],
 ["supplier credit fn",app.includes("function applySupplierCredit")],
 ["void purchase fn",app.includes("function voidPurchase")],
 ["return cash refund",app.includes("Reembolso devolución compra")],
 ["void purchase protection",app.includes("ya tiene pagos aplicados")],
 ["purchase return atomic",app.includes('localAtomic("Devolución de compra"')]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 24 smoke test OK");
