import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8"),data=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema20",data.includes("s.schemaVersion=20")],
 ["supported currencies",data.includes("supportedCurrencies")],
 ["DB convert",data.includes("convert(amount,fromCurrency,toCurrency)")],
 ["currency guard",data.includes("no puede recibir un movimiento en")],
 ["app convert",app.includes("function convertMoney")],
 ["account guard",app.includes("function ensureAccountCurrency")],
 ["currency audit",app.includes("moneda no válida")]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 20 smoke test OK");
