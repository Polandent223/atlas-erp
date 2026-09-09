globalThis.localStorage={
 data:new Map(),
 getItem(k){return this.data.has(k)?this.data.get(k):null},
 setItem(k,v){this.data.set(k,String(v))},
 removeItem(k){this.data.delete(k)}
};
const {DB}=await import("../assets/data.js");
const s=DB.getState();
if(s.schemaVersion!==21)throw new Error("schemaVersion incorrecta");
const usdRate=DB.latestRate("USD");
if(!usdRate||usdRate<=0)throw new Error("Falta tasa USD");
const vesAmount=DB.convert(10,"USD","VES");
if(Math.abs(vesAmount-(10*usdRate))>0.01)throw new Error("Conversión USD→VES incorrecta");
let ves=s.cashAccounts.find(a=>String(a.currency).toUpperCase()==="VES");
if(!ves){
 ves={id:"ca-ves-test",name:"Bolívares prueba",type:"Banco",currency:"VES",branchId:s.branches[0]?.id,balance:100000,status:"Activa"};
 s.cashAccounts.push(ves);
}
const before=Number(ves.balance||0);
DB.moveCash(ves.id,"IN",vesAmount,"MC-TEST","Pago USD 10 en VES",null,"VES",1);
if(Math.abs(Number(ves.balance)-before-vesAmount)>0.01)throw new Error("Movimiento convertido no actualizó la cuenta VES");
const movement=s.cashMovements[0];
if(movement.currency!=="VES")throw new Error("Movimiento no guardó moneda VES");
console.log("ATLAS Fase 21 multicurrency runtime OK");
