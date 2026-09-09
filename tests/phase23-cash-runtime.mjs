globalThis.localStorage={data:new Map(),getItem(k){return this.data.has(k)?this.data.get(k):null},setItem(k,v){this.data.set(k,String(v))},removeItem(k){this.data.delete(k)}};
const {DB}=await import("../assets/data.js");
const s=DB.getState();
if(s.schemaVersion!==23)throw new Error("schemaVersion incorrecta");
if(!Array.isArray(s.cashTransfers)||!Array.isArray(s.cashClosings)||!Array.isArray(s.cashReconciliations))throw new Error("estructuras financieras faltantes");
if(!s.chartOfAccounts.some(a=>a.name==="Ajustes y diferencias de caja"))throw new Error("cuenta contable de diferencias faltante");

let usd=s.cashAccounts.find(a=>String(a.currency).toUpperCase()==="USD");
if(!usd)throw new Error("falta cuenta USD");
let ves=s.cashAccounts.find(a=>String(a.currency).toUpperCase()==="VES");
if(!ves){ves={id:"ca-ves-23",name:"VES test",type:"Banco",currency:"VES",branchId:s.branches[0]?.id,balance:100000,status:"Activa"};s.cashAccounts.push(ves)}
usd.balance=Math.max(Number(usd.balance||0),100);
const usdBefore=usd.balance,vesBefore=ves.balance;
const sent=10,received=DB.convert(sent,"USD","VES");
DB.atomic(()=>{
 DB.moveCash(usd.id,"OUT",sent,"TF-TEST","",null,"USD",DB.latestRate("USD"));
 DB.moveCash(ves.id,"IN",received,"TF-TEST","",null,"VES",1);
 s.cashTransfers.unshift({id:"tf-test",reference:"TF-TEST",fromAccountId:usd.id,toAccountId:ves.id,fromAmount:sent,toAmount:received});
});
if(Math.abs(usd.balance-(usdBefore-sent))>0.01)throw new Error("salida de transferencia incorrecta");
if(Math.abs(ves.balance-(vesBefore+received))>0.01)throw new Error("entrada de transferencia incorrecta");

const snapshot=JSON.stringify(DB.getState());
let failed=false;
try{DB.atomic(()=>{DB.getState().cashClosings.push({id:"tmp"});throw new Error("rollback")})}catch(e){failed=true}
if(!failed||DB.getState().cashClosings.some(x=>x.id==="tmp"))throw new Error("rollback de cierre falló");
console.log("ATLAS Fase 23 cash runtime OK");
