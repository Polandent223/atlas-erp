import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8");
const data=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema19",data.includes("s.schemaVersion=19")],
 ["atomic rollback",data.includes("state=clone(snapshot)")],
 ["selection validation",app.includes("function requireSelection")],
 ["positive number validation",app.includes("function requirePositiveNumber")],
 ["sale atomic",app.includes('localAtomic("Venta"')],
 ["purchase atomic",app.includes('localAtomic("Compra"')],
 ["collection atomic",app.includes('localAtomic("Cobro"')],
 ["payment atomic",app.includes('localAtomic("Pago"')],
 ["transfer atomic",app.includes('localAtomic("Transferencia"')],
 ["return atomic",app.includes('localAtomic("Devolución"')],
 ["expense atomic",app.includes('localAtomic("Gasto"')]
];
for(const [name,ok] of checks) if(!ok) throw new Error("Falla: "+name);
console.log("ATLAS Fase 19 smoke test OK");
