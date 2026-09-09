const A=v=>Array.isArray(v)?v:[],N=v=>Number(v||0);
const pick=(o,...ks)=>{for(const k of ks)if(o?.[k]!=null)return o[k];return null};
export function runWorkflowAudit(s){
 const checks=[],issues=[],warnings=[]; const add=(name,ok,detail)=>{checks.push({name,ok,detail});if(!ok)issues.push(`${name}: ${detail}`)};
 const sales=A(s.sales),purchases=A(s.purchases),ar=A(s.receivables),ap=A(s.payables),cash=A(s.cashMovements),returns=A(s.returns||s.saleReturns),preturns=A(s.purchaseReturns);
 let bad=0;
 for(const sale of sales){
   const total=N(pick(sale,"total","grandTotal")),paid=N(pick(sale,"paid","paidAmount"));
   const balance=Math.max(0,total-paid);
   if(balance>.01){
     const linked=ar.some(x=>String(pick(x,"saleId","documentId","sourceId"))===String(sale.id)||String(pick(x,"documentNumber","number"))===String(sale.number));
     if(!linked)bad++;
   }
 }
 add("Ventas a crédito generan CxC",bad===0,bad?`${bad} ventas con saldo sin CxC vinculada`:"OK");
 bad=0;
 for(const p of purchases){
   const total=N(pick(p,"total","grandTotal")),paid=N(pick(p,"paid","paidAmount")),balance=Math.max(0,total-paid);
   if(balance>.01){
     const linked=ap.some(x=>String(pick(x,"purchaseId","documentId","sourceId"))===String(p.id)||String(pick(x,"documentNumber","number"))===String(p.number));
     if(!linked)bad++;
   }
 }
 add("Compras a crédito generan CxP",bad===0,bad?`${bad} compras con saldo sin CxP vinculada`:"OK");
 const cashSales=sales.filter(x=>N(pick(x,"paid","paidAmount"))>0).length;
 const saleCash=cash.filter(x=>String(pick(x,"type","kind","source")).toLowerCase().includes("venta")||String(pick(x,"reference","description")).toLowerCase().includes("venta")).length;
 if(cashSales && !saleCash)warnings.push("Hay ventas cobradas pero no se reconocieron movimientos de caja por texto/referencia; revisar formato histórico.");
 checks.push({name:"Ventas y caja",ok:!cashSales||saleCash>0,detail:!cashSales||saleCash>0?"Movimiento de caja detectable":"Revisar movimientos históricos"});
 const cancelled=sales.filter(x=>["anulada","cancelled","void"].includes(String(x.status||"").toLowerCase()));
 const returnedSaleIds=new Set(returns.map(x=>String(pick(x,"saleId","documentId","sourceId"))));
 const duplicateCancel=cancelled.filter(x=>returnedSaleIds.has(String(x.id))).length;
 checks.push({name:"Anulaciones y devoluciones",ok:duplicateCancel===0,detail:duplicateCancel?`${duplicateCancel} documentos requieren revisión por doble reverso`:"Sin doble reverso detectable"});
 if(duplicateCancel)issues.push("Posible doble reverso entre anulación y devolución.");
 const negativeAR=ar.filter(x=>N(x.balance)<-.01).length,negativeAP=ap.filter(x=>N(x.balance)<-.01).length;
 add("Saldos CxC/CxP coherentes",negativeAR+negativeAP===0,negativeAR+negativeAP?`${negativeAR+negativeAP} saldos negativos`:"OK");
 const accountIds=new Set(A(s.cashAccounts).map(x=>String(x.id)));
 const orphanCash=cash.filter(x=>pick(x,"accountId","cashAccountId")&&!accountIds.has(String(pick(x,"accountId","cashAccountId")))).length;
 add("Movimientos de caja vinculados",orphanCash===0,orphanCash?`${orphanCash} movimientos sin cuenta válida`:"OK");
 const score=Math.round(100*checks.filter(x=>x.ok).length/Math.max(1,checks.length));
 return {ok:issues.length===0,checks,issues,warnings,score,counts:{sales:sales.length,purchases:purchases.length,receivables:ar.length,payables:ap.length,cash:cash.length,returns:returns.length,purchaseReturns:preturns.length}};
}
