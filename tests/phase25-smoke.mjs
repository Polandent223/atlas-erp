import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8"),data=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema25",data.includes("s.schemaVersion=25")],
 ["metrics",app.includes("function reportMetrics")],
 ["valuation",app.includes("function inventoryValuation")],
 ["top products",app.includes("function topProductsReport")],
 ["aged AR",app.includes("function agedReceivables")],
 ["net profit",app.includes("netProfit")],
 ["csv",app.includes("function reportCSV")],
 ["manager page",app.includes("Reportes y control gerencial")]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 25 smoke test OK");
