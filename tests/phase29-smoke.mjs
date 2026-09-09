import fs from "node:fs";
const a=fs.readFileSync("assets/app.js","utf8"),d=fs.readFileSync("assets/data.js","utf8");
const checks=[
 ["schema29",d.includes("s.schemaVersion=29")],
 ["purchase",a.includes('nextLocalDoc("purchase","C")')],
 ["expense",a.includes('nextLocalDoc("expense","G")')],
 ["stock",a.includes('nextLocalDoc("stockTransfer","TR")')],
 ["cash transfer",a.includes('nextLocalDoc("cashTransfer","TF")')],
 ["voided return",a.includes("La venta está anulada y no puede recibir devoluciones.")],
 ["customer credit",a.includes('nextLocalDoc("customerCreditApplication","NC")')],
 ["supplier credit",a.includes('nextLocalDoc("supplierCreditApplication","CP")')]
];
for(const [n,ok] of checks)if(!ok)throw new Error("Falla: "+n);
console.log("ATLAS Fase 29 smoke test OK");
