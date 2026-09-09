import fs from "node:fs";
const a=fs.readFileSync("assets/app.js","utf8");
const required=['nextLocalDoc("purchase","C")','nextLocalDoc("expense","G")','nextLocalDoc("stockTransfer","TR")','nextLocalDoc("cashTransfer","TF")','nextLocalDoc("customerCreditApplication","NC")','nextLocalDoc("supplierCreditApplication","CP")'];
for(const x of required)if(!a.includes(x))throw new Error("Secuencia faltante: "+x);
if(a.includes('${field("Referencia","reference",nextLocalDoc("cashTransfer","TF"))}'))throw new Error("La transferencia de caja consume número al abrir el modal");
console.log("ATLAS Fase 29 sequence contract OK");
