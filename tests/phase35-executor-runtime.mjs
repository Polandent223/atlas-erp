const calls=[];
globalThis.ATLAS_SUPABASE_CLIENT={
 auth:{async getSession(){return {data:{session:{user:{id:"u1"}}},error:null}}},
 async rpc(n){calls.push(n);return {data:{company_id:"c1"},error:null}},
 from(t){return {select(){return Promise.resolve({count:0,error:null})}}}
};
const {executeCloudImport}=await import("../assets/cloud-import-executor.js");
let blocked=false;try{await executeCloudImport({steps:[]},{dryRun:true})}catch(e){blocked=e.message.includes("confirmación")}
if(!blocked)throw new Error("guard no funciona");
const r=await executeCloudImport({steps:[{table:"products",count:2,rows:[{},{}]}]},{confirmToken:"IMPORTAR-ATLAS",dryRun:true});
if(!r.dryRun||r.companyId!=="c1")throw new Error("dry-run incorrecto");
console.log("ATLAS Fase 35 executor runtime OK");
