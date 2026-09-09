import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8");
const data=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema21",data.includes("s.schemaVersion=21")],
 ["sale currency selector",app.includes('id="saleCurrency"')],
 ["purchase currency selector",app.includes('name="documentCurrency"')],
 ["payment conversion",app.includes("function convertedPayment")],
 ["document conversion",app.includes("function documentAmountsFromUSD")],
 ["sale document total",app.includes("documentTotal:doc.total")],
 ["purchase document total",app.includes("baseTotalUSD:total")],
 ["multicurrency receivable collection",app.includes("Cobro aplicado USD")],
 ["multicurrency payable payment",app.includes("Pago aplicado USD")],
 ["currency integrity",app.includes("moneda distinta a su cuenta")]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 21 smoke test OK");
