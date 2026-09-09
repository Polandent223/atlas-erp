globalThis.localStorage={
 data:new Map(),
 getItem(k){return this.data.has(k)?this.data.get(k):null},
 setItem(k,v){this.data.set(k,String(v))},
 removeItem(k){this.data.delete(k)}
};
const {DB}=await import("../assets/data.js");
const s=DB.getState();
if(s.schemaVersion!==17) throw new Error("schemaVersion incorrecta");
if(!s.chartOfAccounts.some(a=>a.name==="Créditos a clientes")) throw new Error("falta cuenta de créditos");
const ca=s.cashAccounts[0];
ca.balance=10;
DB.save();
let blocked=false;
try{DB.moveCash(ca.id,"OUT",20,"TEST","Debe bloquearse")}catch(e){blocked=true}
if(!blocked) throw new Error("No bloqueó caja negativa");
DB.moveCash(ca.id,"IN",5,"TEST-IN","entrada");
if(Number(ca.balance)!==15) throw new Error("Movimiento de caja incorrecto");
let journalBlocked=false;
try{DB.postJournal("BAD","Malo",[{accountId:"no-existe",debit:10,credit:0},{accountId:s.chartOfAccounts[0].id,debit:0,credit:10}])}catch(e){journalBlocked=true}
if(!journalBlocked) throw new Error("No bloqueó cuenta contable inválida");
console.log("ATLAS Fase 17 data runtime OK");
