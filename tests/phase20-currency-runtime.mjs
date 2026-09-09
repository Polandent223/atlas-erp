globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
const s=DB.getState();
if(s.schemaVersion!==20)throw new Error("schemaVersion incorrecta");
if(!s.supportedCurrencies.includes("USDT"))throw new Error("USDT no disponible");
const usd=DB.latestRate("USD"); if(!usd||usd<=0)throw new Error("tasa USD inválida");
const ves=DB.convert(1,"USD","VES"); if(!Number.isFinite(ves)||ves<=0)throw new Error("conversión inválida");
const acc=s.cashAccounts.find(a=>String(a.currency).toUpperCase()==="USD"); if(!acc)throw new Error("falta cuenta USD");
let blocked=false; try{DB.moveCash(acc.id,"IN",10,"TEST","",null,"VES",1)}catch(e){blocked=true}
if(!blocked)throw new Error("No bloqueó moneda distinta");
console.log("ATLAS Fase 20 currency runtime OK");
