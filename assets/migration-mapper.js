const A=v=>Array.isArray(v)?v:[];
export const ENTITIES=["branches","customers","suppliers","products","payment_methods","cash_accounts","sales","purchases","receivables","payables","journal_entries"];
export function buildIdMap(pkg){const maps={};for(const e of ENTITIES){maps[e]={};for(const row of A(pkg?.tables?.[e]))if(row?.id!=null)maps[e][String(row.id)]={localId:String(row.id),cloudId:null};}return maps;}
export function mappingCoverage(maps){let total=0,mapped=0;for(const e of Object.values(maps||{}))for(const v of Object.values(e||{})){total++;if(v.cloudId)mapped++;}return {total,mapped,pending:total-mapped,percent:total?Math.round(mapped*100/total):100};}
export function setCloudId(maps,entity,localId,cloudId){if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(cloudId)))throw new Error("UUID de nube inválido.");if(!maps?.[entity]?.[String(localId)])throw new Error("ID local no encontrado.");maps[entity][String(localId)].cloudId=cloudId;return maps;}
const val=(o,...k)=>{for(const x of k)if(o?.[x]!=null)return o[x];return null};
export function validateReferences(pkg){
 const t=pkg?.tables||{},errors=[];const ids=n=>new Set(A(t[n]).map(x=>String(x.id)));
 const br=ids("branches"),pr=ids("products"),cu=ids("customers"),su=ids("suppliers"),ca=ids("cash_accounts");
 for(const x of A(t.inventory)){const b=val(x,"branchId","branch_id"),p=val(x,"productId","product_id");if(b&&!br.has(String(b)))errors.push(`Inventario ${x.id}: sucursal inexistente`);if(p&&!pr.has(String(p)))errors.push(`Inventario ${x.id}: producto inexistente`)}
 for(const x of A(t.sales)){const b=val(x,"branchId","branch_id"),c=val(x,"customerId","customer_id");if(b&&!br.has(String(b)))errors.push(`Venta ${x.id}: sucursal inexistente`);if(c&&!cu.has(String(c)))errors.push(`Venta ${x.id}: cliente inexistente`);for(const i of A(x.items)){const p=val(i,"productId","product_id");if(p&&!pr.has(String(p)))errors.push(`Venta ${x.id}: producto inexistente`)}}
 for(const x of A(t.purchases)){const b=val(x,"branchId","branch_id"),s=val(x,"supplierId","supplier_id");if(b&&!br.has(String(b)))errors.push(`Compra ${x.id}: sucursal inexistente`);if(s&&!su.has(String(s)))errors.push(`Compra ${x.id}: proveedor inexistente`);for(const i of A(x.items)){const p=val(i,"productId","product_id");if(p&&!pr.has(String(p)))errors.push(`Compra ${x.id}: producto inexistente`)}}
 for(const x of A(t.cash_movements)){const a=val(x,"accountId","cashAccountId","account_id");if(a&&!ca.has(String(a)))errors.push(`Movimiento ${x.id}: cuenta inexistente`)}
 return {ok:errors.length===0,errors};
}
