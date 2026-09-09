
import { CONFIG } from "./config.js";


export const PERMISSIONS = [
  "dashboard","company","branches","customers","suppliers","products","inventory",
  "stockTransfers","sales","quotations","purchases","returns","cash","expenses",
  "receivables","payables","rates","paymentMethods","users","roles","accounting",
  "reports","audit","documents","settings","backup","system"
];


const KEY = "atlas_phase3_data";

const now = () => new Date().toISOString();

const seed = {
  session: { loggedIn:false, userId:"u1" },
  company:{
    id:"c1", name:"Mi Empresa", taxId:"J-00000000-0", phone:"", email:"",
    country:"Venezuela", baseCurrency:"VES", displayCurrency:"USD"
  },
  branches:[
    {id:"b1",name:"Sede Principal",city:"Valencia",status:"Activo"},
    {id:"b2",name:"Sucursal 2",city:"Maracay",status:"Activo"}
  ],
  roles:[
    {id:"r1",name:"Administrador",description:"Control total",permissions:["*"]},
    {id:"r2",name:"Ventas",description:"Ventas y clientes",permissions:["dashboard","customers","sales","cash"]},
    {id:"r3",name:"Almacén",description:"Productos e inventario",permissions:["dashboard","products","inventory","purchases"]}
  ],
  users:[
    {id:"u1",name:"Administrador",email:"admin@atlas.local",pin:"1234",roleId:"r1",branchId:"all",status:"Activo"},
    {id:"u2",name:"Vendedor Demo",email:"ventas@atlas.local",pin:"1111",roleId:"r2",branchId:"b1",status:"Activo"}
  ],
  customers:[
    {id:"cl1",code:"CLI-001",name:"Cliente Demo",taxId:"V-00000001",phone:"",email:"",city:"Valencia",creditLimit:200,status:"Activo",balance:0}
  ],
  suppliers:[
    {id:"pr1",code:"PRO-001",name:"Proveedor Demo",taxId:"J-00000001",phone:"",email:"",city:"Caracas",status:"Activo",balance:0}
  ],
  products:[
    {id:"p1",sku:"AT-001",name:"Producto Demo",category:"General",cost:5,price:10,tax:16,minStock:5,status:"Activo"}
  ],
  inventory:[
    {id:"i1",productId:"p1",branchId:"b1",stock:20,reserved:0},
    {id:"i2",productId:"p1",branchId:"b2",stock:8,reserved:0}
  ],
  movements:[
    {id:"m1",date:now(),type:"INICIAL",productId:"p1",branchId:"b1",qty:20,note:"Inventario inicial"},
    {id:"m2",date:now(),type:"INICIAL",productId:"p1",branchId:"b2",qty:8,note:"Inventario inicial"}
  ],
  exchangeRates:[
    {id:"fx1",date:new Date().toISOString().slice(0,10),currency:"USD",rate:36.50,source:"Manual"},
    {id:"fx2",date:new Date().toISOString().slice(0,10),currency:"EUR",rate:39.50,source:"Manual"},
    {id:"fx3",date:new Date().toISOString().slice(0,10),currency:"USDT",rate:37.10,source:"Manual"}
  ],
  sales:[],
  purchases:[],
  receivables:[],
  payables:[],
  cashAccounts:[
    {id:"ca1",name:"Caja Principal",type:"Caja",currency:"USD",branchId:"b1",balance:0,status:"Activo"},
    {id:"ca2",name:"Banco Principal",type:"Banco",currency:"VES",branchId:"b1",balance:0,status:"Activo"}
  ],
  cashMovements:[],
  cashTransfers:[],
  cashClosings:[],
  cashReconciliations:[],
  chartOfAccounts:[
    {id:"ac1",code:"1.1.01",name:"Caja y bancos",type:"Activo"},
    {id:"ac2",code:"1.1.02",name:"Cuentas por cobrar",type:"Activo"},
    {id:"ac3",code:"1.1.03",name:"Inventario",type:"Activo"},
    {id:"ac4",code:"2.1.01",name:"Cuentas por pagar",type:"Pasivo"},
    {id:"ac5",code:"4.1.01",name:"Ventas",type:"Ingreso"},
    {id:"ac6",code:"5.1.01",name:"Costo de ventas",type:"Costo"},
    {id:"ac7",code:"5.2.01",name:"Compras / Gastos",type:"Gasto"},
    {id:"ac8",code:"2.1.02",name:"IVA por pagar",type:"Pasivo"},
    {id:"ac9",code:"1.1.04",name:"IVA crédito fiscal",type:"Activo"},
    {id:"ac10",code:"2.1.03",name:"Créditos a clientes",type:"Pasivo"},
    {id:"ac11",code:"6.1.01",name:"Ajustes y diferencias de caja",type:"Resultado"},
    {id:"ac12",code:"1.1.07",name:"Créditos de proveedores",type:"Activo"}
  ],
  journalEntries:[],
  auditLog:[],
  documentSettings:{prefixSale:"V",prefixPurchase:"C",footer:"Generado por ATLAS — Sistema de Gestión Empresarial"},
  paymentMethods:[
    {id:"pm1",name:"Efectivo",type:"cash",active:true},
    {id:"pm2",name:"Transferencia",type:"bank",active:true},
    {id:"pm3",name:"Pago móvil",type:"mobile",active:true},
    {id:"pm4",name:"Zelle / equivalente",type:"other",active:true}
  ],
  expenses:[],
  quotations:[],
  stockTransfers:[],
  returns:[],
  purchaseReturns:[],
  supplierCredits:[],
  settings:{documentTemplates:{showAddress:true,showTaxId:true,showFooter:true,footerText:"Gracias por su preferencia.",paperSize:"A4"},
    lowStockAlerts:true,
    allowNegativeStock:false,
    defaultCreditDays:30,
    invoiceTaxIncluded:false
  },
  sync:{
    lastSync:null,
    status:"local",
    pending:0,
    lastError:null
  },
  branchAccess:{
    u1:["*"],
    u2:["b1"]
  },
  activity:[
    {id:"a1",date:now(),text:"ATLAS Fase 3 inicializado"}
  ]
};

function clone(x){return JSON.parse(JSON.stringify(x))}
function mergeDefaults(base,current){
  if(Array.isArray(base)) return Array.isArray(current)?current:clone(base);
  if(base && typeof base==="object"){
    const out={...clone(base),...(current&&typeof current==="object"?current:{})};
    for(const [k,v] of Object.entries(base)) out[k]=mergeDefaults(v,current?.[k]);
    return hardenState(out);
  }
  return current===undefined?base:current;
}

function hardenState(s){
  s = (s && typeof s==="object") ? s : {};
  const arrays=["branches","roles","users","customers","suppliers","products","inventory","movements",
    "activity","exchangeRates","sales","purchases","receivables","payables","cashAccounts","cashMovements",
    "chartOfAccounts","journalEntries","auditLog","paymentMethods","expenses","quotations","stockTransfers","returns","cashTransfers","cashClosings","cashReconciliations","purchaseReturns","supplierCredits"];
  for(const k of arrays) if(!Array.isArray(s[k])) s[k]=[];
  if(!s.settings || typeof s.settings!=="object") s.settings={};
  s.settings.allowNegativeStock=!!s.settings.allowNegativeStock;
  if(s.settings.allowNegativeCash===undefined) s.settings.allowNegativeCash=false;
  if(!s.sync || typeof s.sync!=="object") s.sync={lastSync:null,status:"local",pending:0,lastError:null};
  if(!s.branchAccess || typeof s.branchAccess!=="object") s.branchAccess={};
  if(!s.documentCounters||typeof s.documentCounters!=="object") s.documentCounters={sale:1,purchase:1,quote:1,return:1,expense:1};
  if(!Array.isArray(s.customerCredits)) s.customerCredits=[];
  if(!Array.isArray(s.supportedCurrencies)) s.supportedCurrencies=["USD","VES","EUR","USDT"];
  if(!s.settings.baseCurrency) s.settings.baseCurrency=s.company?.baseCurrency||"VES";
  if(!s.settings.displayCurrency) s.settings.displayCurrency=s.company?.displayCurrency||"USD";
  for(const v of s.sales||[]){
    if(!v.currency) v.currency="USD";
    if(v.documentTotal===undefined) v.documentTotal=Number(v.total||0);
    if(v.documentSubtotal===undefined) v.documentSubtotal=Number(v.subtotal||0);
    if(v.documentTax===undefined) v.documentTax=Number(v.tax||0);
    if(v.baseTotalUSD===undefined) v.baseTotalUSD=Number(v.total||0);
  }
  for(const p of s.purchases||[]){
    if(!p.currency) p.currency="USD";
    if(p.documentTotal===undefined) p.documentTotal=Number(p.total||0);
    if(p.documentSubtotal===undefined) p.documentSubtotal=Number(p.subtotal||0);
    if(p.documentTax===undefined) p.documentTax=Number(p.tax||0);
    if(p.baseTotalUSD===undefined) p.baseTotalUSD=Number(p.total||0);
  }
  for(const r of s.receivables||[]){
    if(!r.currency) r.currency="USD";
    if(r.baseBalanceUSD===undefined) r.baseBalanceUSD=Number(r.balance||0);
  }
  for(const r of s.payables||[]){
    if(!r.currency) r.currency="USD";
    if(r.baseBalanceUSD===undefined) r.baseBalanceUSD=Number(r.balance||0);
  }
  for(const v of s.sales||[]){
    if(v.status==="Anulada"&&!v.voidedAt)v.voidedAt=v.updatedAt||v.date;
  }
  for(const c of s.customerCredits||[]){
    if(c.currency===undefined)c.currency="USD";
    if(c.status===undefined)c.status=Number(c.balance||0)>0?"Disponible":"Utilizado";
  }
  if(!Array.isArray(s.cashTransfers)) s.cashTransfers=[];
  if(!Array.isArray(s.cashClosings)) s.cashClosings=[];
  if(!Array.isArray(s.cashReconciliations)) s.cashReconciliations=[];
  if(!s.chartOfAccounts.some(a=>a.name==="Ajustes y diferencias de caja"))
    s.chartOfAccounts.push({id:"ac11",code:"6.1.01",name:"Ajustes y diferencias de caja",type:"Resultado"});
  if(!s.settings.reporting)s.settings.reporting={};
  if(!s.settings.reporting.defaultRange)s.settings.reporting.defaultRange="month";
  if(!Number.isFinite(Number(s.settings.reporting.lowStockThreshold)))s.settings.reporting.lowStockThreshold=5;
  if(!Number.isFinite(Number(s.settings.reporting.staleReceivableDays)))s.settings.reporting.staleReceivableDays=30;
  if(!s.settings.documentTemplates)s.settings.documentTemplates={};
  if(s.settings.documentTemplates.showAddress===undefined)s.settings.documentTemplates.showAddress=true;
  if(s.settings.documentTemplates.showTaxId===undefined)s.settings.documentTemplates.showTaxId=true;
  if(s.settings.documentTemplates.showFooter===undefined)s.settings.documentTemplates.showFooter=true;
  if(!s.settings.documentTemplates.footerText)s.settings.documentTemplates.footerText="Gracias por su preferencia.";
  if(!s.settings.documentTemplates.paperSize)s.settings.documentTemplates.paperSize="A4";
  if(!s.settings.securityPolicy)s.settings.securityPolicy={};
  if(!Number.isFinite(Number(s.settings.securityPolicy.sessionTimeoutMinutes)))s.settings.securityPolicy.sessionTimeoutMinutes=30;
  if(s.settings.securityPolicy.requirePinForSensitive===undefined)s.settings.securityPolicy.requirePinForSensitive=true;
  if(!Number.isFinite(Number(s.settings.securityPolicy.lockAfterFailedAttempts)))s.settings.securityPolicy.lockAfterFailedAttempts=5;
  if(!Number.isFinite(Number(s.settings.securityPolicy.failedAttempts)))s.settings.securityPolicy.failedAttempts=0;
  if(!s.settings.fiscalConfig)s.settings.fiscalConfig={};
  const fc=s.settings.fiscalConfig;
  if(!fc.country)fc.country="VE";
  if(fc.ivaEnabled===undefined)fc.ivaEnabled=true;
  if(!Number.isFinite(Number(fc.ivaRate)))fc.ivaRate=16;
  if(fc.igtfEnabled===undefined)fc.igtfEnabled=false;
  if(!Number.isFinite(Number(fc.igtfRate)))fc.igtfRate=3;
  if(!Array.isArray(fc.igtfCurrencies))fc.igtfCurrencies=["USD","EUR","USDT"];
  if(!fc.taxIdLabel)fc.taxIdLabel="RIF";
  Object.assign(fc,{
   invoicePrefix:fc.invoicePrefix||"V",purchasePrefix:fc.purchasePrefix||"C",quotePrefix:fc.quotePrefix||"Q",
   expensePrefix:fc.expensePrefix||"G",returnPrefix:fc.returnPrefix||"DV",purchaseReturnPrefix:fc.purchaseReturnPrefix||"DC",
   stockTransferPrefix:fc.stockTransferPrefix||"TR",cashTransferPrefix:fc.cashTransferPrefix||"TF",cashClosingPrefix:fc.cashClosingPrefix||"CJ"
  });
  s.schemaVersion=47;
  return s;
}

function normalizeState(input){
  const next=mergeDefaults(seed,input||{});
  const ac10=next.chartOfAccounts.find(a=>a.id==="ac10"||a.name==="Créditos a clientes");
  if(!ac10) next.chartOfAccounts.push({id:"ac10",code:"2.1.03",name:"Créditos a clientes",type:"Pasivo"});
const ac9=next.chartOfAccounts.find(a=>a.id==="ac9"||a.name==="IVA crédito fiscal");
  if(!ac9) next.chartOfAccounts.push({id:"ac9",code:"1.1.04",name:"IVA crédito fiscal",type:"Activo"});
  for(const b of next.branches) if(b.status==="Activa") b.status="Activo";
  for(const u of next.users) if(!u.status) u.status="Activo";
  for(const p of next.products) if(!p.status) p.status="Activo";
  for(const c of next.customers) if(!c.status) c.status="Activo";
  for(const s of next.suppliers) if(!s.status) s.status="Activo";
  return next;
}
function load(){
  const raw=localStorage.getItem(KEY);
  if(!raw){ const initial=hardenState(normalizeState(seed)); localStorage.setItem(KEY,JSON.stringify(initial)); return clone(initial); }
  try{return hardenState(normalizeState(JSON.parse(raw)));}
  catch{return hardenState(normalizeState(seed));}
}
let state=load();

export const DB = {
  mode: CONFIG.mode,
  getState(){ return state; },
  save(){ localStorage.setItem(KEY,JSON.stringify(state)); },
  reset(){ state=hardenState(normalizeState(clone(seed))); this.save(); return state; },
  id(prefix="x"){return prefix+"_"+Math.random().toString(36).slice(2,10)},
  log(text, action="ACTIVITY", entity="system"){
    const user=this.currentUser();
    state.activity.unshift({id:this.id("a"),date:now(),text});
    state.activity=state.activity.slice(0,80);
    state.auditLog.unshift({id:this.id("au"),date:now(),userId:user?.id||null,action,entity,detail:text});
    state.auditLog=state.auditLog.slice(0,500);
    this.save();
  },
  login(email,pin){
    const user=state.users.find(u=>u.email.toLowerCase()===email.toLowerCase() && u.pin===pin && u.status==="Activo");
    if(!user) return null;
    state.session={loggedIn:true,userId:user.id}; this.log(`Inicio de sesión: ${user.name}`); return user;
  },
  logout(){ state.session.loggedIn=false; this.save(); },
  currentUser(){ return state.users.find(u=>u.id===state.session.userId)||null; },
  setRemoteSession(profile){
    const localId=profile.id;
    let user=state.users.find(u=>u.id===localId);
    if(!user){
      user={id:localId,name:profile.full_name||profile.email,email:profile.email,pin:"",roleId:profile.role_id,branchId:profile.branch_id||"all",status:profile.status||"Activo"};
      state.users.push(user);
    }else{
      user.name=profile.full_name||user.name;
      user.email=profile.email||user.email;
      user.roleId=profile.role_id||user.roleId;
      user.branchId=profile.branch_id||user.branchId;
      user.status=profile.status||user.status;
    }
    state.session={loggedIn:true,userId:localId};
    state.sync.status="connected";
    this.save();
    return user;
  },
  setSyncStatus(status,error=null){
    state.sync.status=status;
    state.sync.lastError=error;
    if(status==="synced") state.sync.lastSync=now();
    this.save();
  },
  markPending(delta=1){
    state.sync.pending=Math.max(0,Number(state.sync.pending||0)+delta);
    this.save();
  },
  replaceState(next){
    state=hardenState(normalizeState(next));
    this.save();
  },
  role(user){ return state.roles.find(r=>r.id===user?.roleId)||null; },
  can(permission){
    const user=this.currentUser(), role=this.role(user);
    if(!user||!role) return false;
    return role.permissions.includes("*")||role.permissions.includes(permission);
  },
  canBranch(branchId){
    const user=this.currentUser();
    if(!user) return false;
    if(user.branchId==="all") return true;
    const access=state.branchAccess[user.id]||[user.branchId].filter(Boolean);
    return access.includes("*")||access.includes(branchId);
  },
  visibleBranches(){
    return state.branches.filter(b=>this.canBranch(b.id));
  },
  exportBackup(){
    return JSON.stringify({version:47,exportedAt:now(),data:state},null,2);
  },
  importBackup(payload){
    const parsed=typeof payload==="string"?JSON.parse(payload):payload;
    if(!parsed?.data) throw new Error("Respaldo inválido");
    state=hardenState(normalizeState(parsed.data));
    this.log("Respaldo restaurado","IMPORT","backup");
    this.save();
    return state;
  },
  atomic(work){
    const snapshot=clone(state);
    try{
      const result=work();
      this.save();
      return result;
    }catch(error){
      state=clone(snapshot);
      localStorage.setItem(KEY,JSON.stringify(state));
      throw error;
    }
  },
  postJournal(reference, description, lines){
    if(!Array.isArray(lines)||!lines.length) throw new Error("El asiento no tiene líneas");
    for(const l of lines){
      if(!l.accountId || !state.chartOfAccounts.some(a=>a.id===l.accountId)) throw new Error("Cuenta contable inválida");
      if(Number(l.debit||0)<0 || Number(l.credit||0)<0) throw new Error("Debe/Haber no puede ser negativo");
      if(Number(l.debit||0)>0 && Number(l.credit||0)>0) throw new Error("Una línea no puede tener Debe y Haber al mismo tiempo");
    }
    const debit=lines.reduce((a,l)=>a+Number(l.debit||0),0);
    const credit=lines.reduce((a,l)=>a+Number(l.credit||0),0);
    if(Math.abs(debit-credit)>0.01) throw new Error("Asiento descuadrado");
    state.journalEntries.unshift({
      id:this.id("je"),date:now(),reference,description,status:"Contabilizado",
      lines:lines.map(l=>({...l,debit:Number(l.debit||0),credit:Number(l.credit||0)}))
    });
    this.log(`Asiento automático ${reference}: ${description}`,"CREATE","journal_entry");
    this.save();
  },
  latestRate(currency){
    const cur=String(currency||"").toUpperCase();
    const base=String(state.settings?.baseCurrency||state.company?.baseCurrency||"VES").toUpperCase();
    if(cur===base) return 1;
    const rows=(state.exchangeRates||[]).filter(r=>String(r.currency||"").toUpperCase()===cur&&Number(r.rate)>0)
      .sort((a,b)=>String(b.date||b.effectiveAt||"").localeCompare(String(a.date||a.effectiveAt||"")));
    return rows.length?Number(rows[0].rate):null;
  },
  convert(amount,fromCurrency,toCurrency){
    const n=Number(amount);
    if(!Number.isFinite(n)) throw new Error("Monto inválido para conversión");
    const base=String(state.settings?.baseCurrency||state.company?.baseCurrency||"VES").toUpperCase();
    const from=String(fromCurrency||base).toUpperCase(),to=String(toCurrency||base).toUpperCase();
    if(from===to) return n;
    const fr=from===base?1:this.latestRate(from),tr=to===base?1:this.latestRate(to);
    if(!fr||!tr) throw new Error(`Falta tasa para convertir ${from} → ${to}`);
    return (n*fr)/tr;
  },
  account(id){ return state.cashAccounts.find(x=>x.id===id) || null; },
  moveCash(accountId, type, amount, reference, note="", paymentMethodId=null, transactionCurrency=null, exchangeRate=null){
    const a=this.account(accountId);
    if(!a) throw new Error("Cuenta financiera inexistente");
    const n=Number(amount);
    if(!Number.isFinite(n)||n<=0) throw new Error("Monto inválido");
    if(type!=="IN"&&type!=="OUT") throw new Error("Tipo de movimiento inválido");
    const accountCurrency=String(a.currency||state.settings?.baseCurrency||"VES").toUpperCase();
    const txCurrency=String(transactionCurrency||accountCurrency).toUpperCase();
    if(txCurrency!==accountCurrency) throw new Error(`La cuenta ${a.name} está en ${accountCurrency} y no puede recibir un movimiento en ${txCurrency}.`);
    if(type==="OUT"&&!state.settings?.allowNegativeCash&&Number(a.balance||0)<n) throw new Error(`Saldo insuficiente en ${a.name}`);
    a.balance=Number(a.balance||0)+(type==="IN"?n:-n);
    state.cashMovements.unshift({id:this.id("cm"),date:now(),accountId,type,amount:n,reference,note,paymentMethodId,currency:accountCurrency,exchangeRate:exchangeRate||null});
    this.save();
  }
};
