globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
const s=DB.getState(),f=s.settings.fiscalConfig;
if(s.schemaVersion!==30)throw new Error("schema incorrecta");
if(!f||!Number.isFinite(Number(f.ivaRate))||!Number.isFinite(Number(f.igtfRate)))throw new Error("config fiscal inválida");
for(const k of ["invoicePrefix","purchasePrefix","quotePrefix","expensePrefix","returnPrefix","purchaseReturnPrefix","stockTransferPrefix","cashTransferPrefix","cashClosingPrefix"])if(!String(f[k]||"").trim())throw new Error("prefijo faltante "+k);
console.log("ATLAS Fase 30 fiscal runtime OK");
