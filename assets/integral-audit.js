const A=v=>Array.isArray(v)?v:[],N=v=>Number(v||0);
const duplicates=(rows,key)=>{const s=new Set(),d=new Set();for(const r of rows){const v=r?.[key];if(v==null||v==="")continue;const x=String(v);s.has(x)?d.add(x):s.add(x)}return [...d]};
export function runIntegralAudit(s){
 const issues=[],warnings=[],checks=[];const add=(name,ok,detail="")=>checks.push({name,ok,detail});
 add("Empresa configurada",!!s?.company?.name,s?.company?.name||"Sin nombre");
 add("Sucursales",A(s?.branches).length>0,`${A(s?.branches).length} registradas`);
 add("Usuarios",A(s?.users).length>0,`${A(s?.users).length} registrados`);
 for(const [name,rows] of [["productos",s?.products],["clientes",s?.customers],["proveedores",s?.suppliers],["ventas",s?.sales],["compras",s?.purchases]]){const d=duplicates(A(rows),"id");add(`IDs únicos: ${name}`,!d.length,d.length?d.join(", "):"OK");if(d.length)issues.push(`IDs duplicados en ${name}`)}
 const products=new Set(A(s?.products).map(x=>String(x.id))),branches=new Set(A(s?.branches).map(x=>String(x.id)));let orphan=0,neg=0;
 for(const x of A(s?.inventory)){if(x.productId&&!products.has(String(x.productId)))orphan++;if(x.branchId&&!branches.has(String(x.branchId)))orphan++;if(N(x.qty)<0)neg++}
 add("Inventario relacionado",!orphan,orphan?`${orphan} referencias huérfanas`:"OK");add("Stock no negativo",!neg,neg?`${neg} registros negativos`:"OK");if(orphan)issues.push("Referencias huérfanas en inventario");if(neg)warnings.push("Existencias negativas detectadas");
 let unbalanced=0;for(const j of A(s?.journalEntries)){const lines=A(j.lines||j.entries);if(!lines.length)continue;const dr=lines.reduce((a,l)=>a+N(l.debit),0),cr=lines.reduce((a,l)=>a+N(l.credit),0);if(Math.abs(dr-cr)>.01)unbalanced++}
 add("Asientos balanceados",!unbalanced,unbalanced?`${unbalanced} descuadrados`:"OK");if(unbalanced)issues.push("Asientos contables descuadrados");
 const sv=duplicates(A(s?.sales),"number"),pc=duplicates(A(s?.purchases),"number");add("Numeración ventas única",!sv.length,sv.length?sv.join(", "):"OK");add("Numeración compras única",!pc.length,pc.length?pc.join(", "):"OK");if(sv.length)issues.push("Números de venta duplicados");if(pc.length)issues.push("Números de compra duplicados");
 const ar=A(s?.receivables).filter(x=>N(x.balance)<-.01).length,ap=A(s?.payables).filter(x=>N(x.balance)<-.01).length;add("CxC válida",!ar,ar?`${ar} saldos negativos`:"OK");add("CxP válida",!ap,ap?`${ap} saldos negativos`:"OK");if(ar||ap)issues.push("Saldos anómalos en cuentas");
 return {ok:!issues.length,issues,warnings,checks,score:Math.round(100*checks.filter(x=>x.ok).length/Math.max(1,checks.length))};
}
