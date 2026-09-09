import {cloudActivationState,verifyCloudActivation,enableCloudMode,disableCloudMode,isCloudMode} from "./cloud-mode.js";
import {releaseReadiness} from "./release-readiness.js";
import {runWorkflowAudit} from "./workflow-audit.js";
import {runIntegralAudit} from "./integral-audit.js";
import {buildIdMap,mappingCoverage,validateReferences} from "./migration-mapper.js";
import {verifyCloudTarget,compareCloudCounts,executeCloudImport} from "./cloud-import-executor.js";
import {buildImportPlan,validateImportPlan} from "./cloud-import.js";
import {cloudAuthAvailable,cloudSession,cloudProfile} from "./cloud-auth.js";
import {buildMigrationPackage,validateMigrationPackage,migrationStats} from "./migration.js";

import { DB, PERMISSIONS } from "./data.js";
import { CONFIG, isSupabaseConfigured } from "./config.js";
import { remoteLogin, remoteLogout, getRemoteProfile, healthCheck } from "./supabase.js";
import { pullCoreWorkspace, pullTransactions, pullAccounting } from "./sync.js";
import { RemoteRepo } from "./repositories.js";

let current="dashboard";
let cart=[];
const state=()=>DB.getState();
const esc=s=>String(s??"").replace(/[&<>"']/g,m=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[m]));
const money=n=>Number(n||0).toLocaleString("es-VE",{minimumFractionDigits:2,maximumFractionDigits:2});
const datefmt=d=>new Date(d).toLocaleString("es-VE",{dateStyle:"short",timeStyle:"short"});

const navGroups=[
 ["GENERAL",[["dashboard","Inicio"]]],
 ["OPERACIÓN",[["sales","Ventas"],["inventory","Inventario"],["purchases","Compras"]]],
 ["PERSONAS",[["customers","Clientes"],["suppliers","Proveedores"]]],
 ["FINANZAS",[["cash","Caja y bancos"],["receivables","Por cobrar"],["payables","Por pagar"],["expenses","Gastos"]]],
 ["CONTROL",[["reports","Reportes"],["controlCenter","Administración"]]]
];

const PAGE_PERMISSION={
 dashboard:"dashboard",company:"company",branches:"branches",customers:"customers",suppliers:"suppliers",
 products:"products",inventory:"inventory",stockTransfers:"stockTransfers",sales:"sales",quotations:"quotations",
 purchases:"purchases",returns:"returns",cash:"cash",expenses:"expenses",receivables:"receivables",
 payables:"payables",rates:"rates",paymentMethods:"paymentMethods",users:"users",roles:"roles",
 accounting:"accounting",reports:"reports",audit:"audit",documents:"documents",settings:"settings",
 backup:"backup",system:"system",security:"settings",fiscal:"settings",maintenance:"backup",cloudReadiness:"settings",migration:"backup",migrationReview:"backup",cloudAccess:"settings",cloudActivation:"settings",migrationMapping:"backup",integralAudit:"audit",workflowAudit:"audit",releaseReadiness:"audit",deploymentAudit:"audit",mountingStatus:"settings"
};

const ADVANCED_PAGES=[
 ["company","Empresa","Datos principales del negocio"],
 ["branches","Sucursales","Sedes y acceso por ubicación"],
 ["products","Productos","Catálogo, costos, precios e impuestos"],
 ["stockTransfers","Transferencias","Movimiento de inventario entre sedes"],
 ["quotations","Cotizaciones","Presupuestos antes de vender"],
 ["returns","Devoluciones","Reversos controlados de ventas"],
 ["rates","Tasas y monedas","USD, EUR, USDT y moneda base"],
 ["paymentMethods","Métodos de pago","Efectivo, banco, pago móvil y otros"],
 ["accounting","Contabilidad","Libro diario, mayor y balances"],
 ["documents","Documentos","Comprobantes de venta y compra"],
 ["audit","Auditoría","Quién hizo cada operación"],
 ["security","Seguridad y permisos","Accesos y operaciones sensibles"],
 ["users","Usuarios","Acceso de cada persona"],
 ["roles","Roles y permisos","Qué puede hacer cada usuario"],
 ["settings","Configuración","Reglas generales de operación"],
 ["backup","Respaldo","Exportar y restaurar información"],
 ["system","Sistema","Diagnóstico y estado técnico"]
];

function moduleAllowed(key){
 if(key==="controlCenter") return ADVANCED_PAGES.some(([k])=>DB.can(PAGE_PERMISSION[k]||k));
 const permission=PAGE_PERMISSION[key];
 return !permission || DB.can(permission);
}

function visibleNavGroups(){
 const groups=[];
 for(const entry of navGroups){
  const group=entry[0];
  const items=entry[1];
  const visible=[];
  for(const item of items){
   if(moduleAllowed(item[0])) visible.push(item);
  }
  if(visible.length) groups.push([group,visible]);
 }
 return groups;
}

function field(label,name,value,type="text",extra=""){return `<div class="field"><label>${label}</label><input name="${name}" type="${type}" value="${esc(value)}" ${extra}></div>`}
function table(headers,rows){
 return `<div class="card table-wrap"><table class="table"><thead><tr>${headers.map(h=>`<th>${h}</th>`).join("")}</tr></thead><tbody>${rows.map(r=>`<tr>${r.map(c=>`<td>${c}</td>`).join("")}</tr>`).join("")||`<tr><td colspan="${headers.length}">Sin registros</td></tr>`}</tbody></table></div>`;
}
function loginView(){
 return `<div class="login-page"><div class="login-card">
   <div class="logo-lockup"><div class="logo-mark">A</div><div><div class="logo-title">ATLAS</div><div class="logo-sub">Sistema de Gestión Empresarial</div></div></div>
   <form id="loginForm">
    <div class="field"><label>Correo</label><input name="email" type="email" value="admin@atlas.local" required></div>
    <div class="field"><label>${isSupabaseConfigured()?"Contraseña":"PIN"}</label><input name="pin" type="password" value="${isSupabaseConfigured()?"":"1234"}" required></div>
    <button class="btn btn-primary btn-block">Entrar</button>
   </form>
   <div class="hintbox">${isSupabaseConfigured()?'<strong>Modo Supabase activo.</strong><br>Usa tu correo y contraseña de ATLAS.':'<strong>Modo local.</strong><br>Administrador demo: admin@atlas.local · PIN 1234'}</div>
 </div></div>`;
}
function shell(content){
 const s=state(), user=DB.currentUser(), role=DB.role(user);
 return `<div class="layout"><aside class="sidebar" id="sidebar">
  <div class="brand"><div class="logo-mark">A</div><div><strong>ATLAS</strong><small>Gestión Empresarial</small></div></div>
  <nav class="nav">${visibleNavGroups().map(([g,items])=>`<div class="section">${g}</div>${items.map(([k,l])=>`<button data-nav="${k}" class="${current===k?"active":""}">${l}</button>`).join("")}`).join("")}</nav>
 </aside><main class="main">
  <header class="topbar"><div class="top-left"><button id="menuToggle" class="menu-toggle">☰</button><span class="company-pill">${esc(s.company.name)}</span><span class="sync-pill ${isSupabaseConfigured()?"cloud":"local"}">${isSupabaseConfigured()?"☁ Nube":"● Local"}</span></div>
   <div class="userbox"><div><strong>${esc(user?.name||"")}</strong><div style="font-size:11px;color:#667085">${esc(role?.name||"")}</div></div><div class="avatar">${esc((user?.name||"A")[0])}</div><button id="logout" class="btn btn-soft">Salir</button></div>
  </header><section class="content">${content}</section></main></div>`;
}

function inventory(){
 const s=state(),rows=(s.inventory||[]).filter(i=>DB.canBranch(i.branchId));
 return `<div class="hero"><div><h2>Inventario</h2><p>Existencias reales por producto y sucursal.</p></div>
 <div class="hero-actions">${moduleAllowed("products")?'<button class="btn btn-soft" data-nav="products">Productos</button>':""}${moduleAllowed("stockTransfers")?'<button class="btn btn-primary" data-nav="stockTransfers">Transferir stock</button>':""}</div></div>
 ${table(["Producto","Sucursal","Stock","Reservado","Disponible","Mínimo","Estado",""],rows.map(i=>{
  const p=s.products.find(x=>x.id===i.productId),b=s.branches.find(x=>x.id===i.branchId);
  const available=Number(i.stock||0)-Number(i.reserved||0),low=Number(i.stock||0)<=Number(p?.minStock||0);
  return [esc(p?.name||""),esc(b?.name||""),money(i.stock),money(i.reserved),money(available),money(p?.minStock||0),
   `<span class="badge ${low?"warn":"ok"}">${low?"Stock bajo":"Correcto"}</span>`,
   `<button class="btn btn-soft" data-adjust="${i.id}">Ajustar</button>`];
 }))}`;
}


function fiscalPage(){
 const f=fiscalConfig();
 return `<div class="hero"><div><h2>Fiscal y numeración</h2><p>Parámetros fiscales editables y secuencias de documentos.</p></div><button class="btn btn-primary" id="editFiscalConfig">Editar configuración</button></div>
 <div class="grid stats">
  <div class="card stat"><div class="label">País</div><div class="value">${esc(f.country||"VE")}</div></div>
  <div class="card stat"><div class="label">IVA</div><div class="value">${f.ivaEnabled!==false?money(f.ivaRate||0)+"%":"Desactivado"}</div></div>
  <div class="card stat"><div class="label">IGTF</div><div class="value">${f.igtfEnabled===true?money(f.igtfRate||0)+"%":"Desactivado"}</div></div>
  <div class="card stat"><div class="label">Etiqueta fiscal</div><div class="value">${esc(f.taxIdLabel||"RIF")}</div></div>
 </div>
 <div class="grid two"><div class="card">${table(["Documento","Prefijo"],[
  ["Venta",f.invoicePrefix],["Compra",f.purchasePrefix],["Cotización",f.quotePrefix],["Gasto",f.expensePrefix],
  ["Devolución venta",f.returnPrefix],["Devolución compra",f.purchaseReturnPrefix],["Transferencia stock",f.stockTransferPrefix],
  ["Transferencia caja",f.cashTransferPrefix],["Cierre caja",f.cashClosingPrefix]
 ].map(([a,b])=>[a,esc(b||"")]))}</div>
 <div class="card"><div class="notice">Las tasas fiscales son configurables. Antes del uso real deben confirmarse según la situación fiscal de la empresa.</div><div class="notice">IGTF solo se aplica cuando está activado y la moneda está incluida en la configuración.</div></div></div>`;
}
function editFiscalConfig(){
 requirePermission("settings","modificar configuración fiscal"); sensitiveConfirm("modificar la configuración fiscal");
 const s=state(),f=s.settings.fiscalConfig||{};
 modal("Configuración fiscal",`
  ${field("País","country",f.country||"VE")}
  ${field("Etiqueta fiscal","taxIdLabel",f.taxIdLabel||"RIF")}
  <label class="check"><input type="checkbox" name="ivaEnabled" ${f.ivaEnabled!==false?"checked":""}> Aplicar IVA</label>
  ${field("Tasa IVA (%)","ivaRate",f.ivaRate??16,"number",'step="0.01" min="0" max="100"')}
  <label class="check"><input type="checkbox" name="igtfEnabled" ${f.igtfEnabled===true?"checked":""}> Aplicar IGTF</label>
  ${field("Tasa IGTF (%)","igtfRate",f.igtfRate??3,"number",'step="0.01" min="0" max="100"')}
  ${field("Monedas IGTF (coma)","igtfCurrencies",(f.igtfCurrencies||["USD","EUR","USDT"]).join(","))}
  ${field("Prefijo venta","invoicePrefix",f.invoicePrefix||"V")}${field("Prefijo compra","purchasePrefix",f.purchasePrefix||"C")}
  ${field("Prefijo cotización","quotePrefix",f.quotePrefix||"Q")}${field("Prefijo gasto","expensePrefix",f.expensePrefix||"G")}
  ${field("Prefijo devolución venta","returnPrefix",f.returnPrefix||"DV")}${field("Prefijo devolución compra","purchaseReturnPrefix",f.purchaseReturnPrefix||"DC")}
  ${field("Prefijo transferencia stock","stockTransferPrefix",f.stockTransferPrefix||"TR")}${field("Prefijo transferencia caja","cashTransferPrefix",f.cashTransferPrefix||"TF")}
  ${field("Prefijo cierre caja","cashClosingPrefix",f.cashClosingPrefix||"CJ")}
 `,fd=>{
   f.country=String(fd.get("country")||"VE").trim().toUpperCase();
   f.taxIdLabel=String(fd.get("taxIdLabel")||"RIF").trim()||"RIF";
   f.ivaEnabled=fd.get("ivaEnabled")==="on"; f.ivaRate=Math.max(0,Math.min(100,Number(fd.get("ivaRate")||0)));
   f.igtfEnabled=fd.get("igtfEnabled")==="on"; f.igtfRate=Math.max(0,Math.min(100,Number(fd.get("igtfRate")||0)));
   f.igtfCurrencies=String(fd.get("igtfCurrencies")||"").split(",").map(x=>x.trim().toUpperCase()).filter(Boolean);
   for(const k of ["invoicePrefix","purchasePrefix","quotePrefix","expensePrefix","returnPrefix","purchaseReturnPrefix","stockTransferPrefix","cashTransferPrefix","cashClosingPrefix"])f[k]=String(fd.get(k)||f[k]||"").trim().toUpperCase().replace(/[^A-Z0-9-]/g,"").slice(0,8);
   DB.log("Configuración fiscal actualizada","UPDATE","fiscal");DB.save();
 });
}

function controlCenter(){
 const allowed=ADVANCED_PAGES.filter(([k])=>moduleAllowed(k));
 return `<div class="hero"><div><h2>Administración</h2><p>Configuraciones y módulos avanzados separados de la operación diaria.</p></div></div>
 <div class="control-grid">${allowed.map(([k,title,desc])=>`<button class="control-card control-card-pro" data-nav="${k}"><strong>${esc(title)}</strong><small>${esc(desc)}</small></button>`).join("")}</div>`;
}

function securityCenter(){
 const s=state(),user=DB.currentUser(),role=DB.role(user),p=s.settings.securityPolicy||{};
 return `<div class="hero"><div><h2>Seguridad y permisos</h2><p>Control de accesos y protección de operaciones sensibles.</p></div>
 <div class="quick-actions"><button class="btn btn-primary" id="editSecurityPolicy">Política de seguridad</button><button class="btn btn-soft" id="resetSecurityLock">Restablecer bloqueo</button></div></div>
 <div class="grid stats">
  <div class="card stat"><div class="label">Usuario actual</div><div class="value">${esc(user?.name||"—")}</div><div class="hint">${esc(role?.name||"Sin rol")}</div></div>
  <div class="card stat"><div class="label">Tiempo de sesión</div><div class="value">${Number(p.sessionTimeoutMinutes||30)} min</div><div class="hint">Por inactividad</div></div>
  <div class="card stat"><div class="label">PIN sensible</div><div class="value">${p.requirePinForSensitive!==false?"Activo":"Desactivado"}</div><div class="hint">Anulaciones y caja</div></div>
  <div class="card stat"><div class="label">Intentos fallidos</div><div class="value">${Number(p.failedAttempts||0)}</div><div class="hint">Registrados en auditoría</div></div>
 </div>
 <div class="grid two">
  <div class="card"><div class="section-title"><h3>Usuarios</h3><button class="btn btn-soft" data-nav="users">Administrar</button></div>
   ${table(["Usuario","Correo","Rol","Estado"],(s.users||[]).map(u=>[esc(u.name),esc(u.email),esc(s.roles.find(r=>r.id===u.roleId)?.name||""),`<span class="badge ${(u.status||"Activo")==="Activo"?"ok":"warn"}">${esc(u.status||"Activo")}</span>`]))}</div>
  <div class="card"><div class="section-title"><h3>Permisos del rol</h3><button class="btn btn-soft" data-nav="roles">Editar roles</button></div>
   <div class="permission-cloud">${role?.permissions?.includes("*")?'<span>Acceso total</span>':(role?.permissions||[]).map(x=>`<span>${esc(x)}</span>`).join("")||'<span>Sin permisos</span>'}</div></div>
 </div>`;
}

function requirePermission(permission,label){
 if(!DB.can(permission))throw new Error(`No tienes permiso para ${label}.`);
}
function sensitiveConfirm(label){
 const s=state(),p=s.settings.securityPolicy||{};
 if(p.requirePinForSensitive===false||isSupabaseConfigured())return true;
 const user=DB.currentUser(),pin=prompt(`Confirma tu PIN para ${label}:`);
 if(pin===null)throw new Error("Operación cancelada.");
 const limit=Math.max(3,Number(p.lockAfterFailedAttempts||5));
 if(Number(p.failedAttempts||0)>=limit)throw new Error("Operaciones sensibles bloqueadas. Un administrador debe restablecer los intentos fallidos.");
 if(String(pin)!==String(user?.pin||"")){
  p.failedAttempts=Number(p.failedAttempts||0)+1;DB.log(`PIN incorrecto al intentar ${label}`,"DENIED","security");DB.save();
  if(p.failedAttempts>=limit)throw new Error(`Operaciones sensibles bloqueadas. Se alcanzó el límite de ${limit} intentos fallidos.`);
  throw new Error(`PIN incorrecto. Intento ${p.failedAttempts} de ${limit}.`);
 }
 p.failedAttempts=0;DB.save();return true;
}
function editSecurityPolicy(){
 requirePermission("settings","modificar la seguridad");
 sensitiveConfirm("modificar la política de seguridad");
 const s=state(),p=s.settings.securityPolicy||{};
 modal("Política de seguridad",`
  ${field("Cerrar sesión tras inactividad (minutos)","sessionTimeoutMinutes",p.sessionTimeoutMinutes||30,"number",'min="5" max="240"')}
  ${field("Intentos fallidos permitidos","lockAfterFailedAttempts",p.lockAfterFailedAttempts||5,"number",'min="3" max="20"')}
  <label class="check"><input type="checkbox" name="requirePinForSensitive" ${p.requirePinForSensitive!==false?"checked":""}> Solicitar PIN en operaciones sensibles</label>
 `,f=>{
  p.sessionTimeoutMinutes=Math.max(5,Math.min(240,Number(f.get("sessionTimeoutMinutes")||30)));
  p.lockAfterFailedAttempts=Math.max(3,Math.min(20,Number(f.get("lockAfterFailedAttempts")||5)));
  p.requirePinForSensitive=f.get("requirePinForSensitive")==="on";
  DB.log("Política de seguridad actualizada","UPDATE","security");DB.save();
 });
}

function page(){
 const routes={dashboard,company,branches,customers,suppliers,products,inventory,stockTransfers,sales,quotations,purchases,returns,cash,expenses,receivables,payables,rates,paymentMethods,users,roles,accounting,reports,audit,documents,settings,backup,system,controlCenter,security:securityCenter,fiscal:fiscalPage,maintenance:maintenancePage,cloudReadiness:cloudReadinessPage,migration:migrationPage,migrationReview:migrationReviewPage,cloudAccess:cloudAccessPage,cloudActivation:cloudActivationPage,migrationMapping:migrationMappingPage,integralAudit:integralAuditPage,workflowAudit:workflowAuditPage,releaseReadiness:releaseReadinessPage,deploymentAudit:deploymentAuditPage,mountingStatus:mountingStatusPage};
 if(current==="controlCenter")return controlCenter();
 const permission=PAGE_PERMISSION[current];
 if(permission&&!DB.can(permission))return restrictedPage(current,permission);
 return (routes[current]||dashboard)();
}
function restrictedPage(route,permission){
 return `<div class="hero"><div><h2>Acceso restringido</h2><p>Tu rol no tiene permiso para abrir este módulo.</p></div></div><div class="card"><div class="notice danger">Módulo: ${esc(route)} · Permiso requerido: ${esc(permission)}</div><div style="height:12px"></div><button class="btn btn-primary" data-nav="dashboard">Volver al inicio</button></div>`;
}

function fiscalConfig(){return state().settings.fiscalConfig||{}}
function docPrefix(kind,fallback){
 const f=fiscalConfig(),map={sale:"invoicePrefix",purchase:"purchasePrefix",quote:"quotePrefix",expense:"expensePrefix",return:"returnPrefix",purchaseReturn:"purchaseReturnPrefix",stockTransfer:"stockTransferPrefix",cashTransfer:"cashTransferPrefix",cashClosing:"cashClosingPrefix"};
 return String(f[map[kind]]||fallback||"DOC").trim().toUpperCase();
}
function nextConfiguredDoc(kind,fallback){return nextLocalDoc(kind,docPrefix(kind,fallback))}
function configuredTaxRate(){const f=fiscalConfig();return f.ivaEnabled===false?0:Number(f.ivaRate||0)}
function configuredIgtfRate(currency){
 const f=fiscalConfig(),cur=String(currency||"USD").toUpperCase();
 return f.igtfEnabled===true&&(f.igtfCurrencies||[]).map(x=>String(x).toUpperCase()).includes(cur)?Number(f.igtfRate||0):0;
}


function backupEnvelope(){
 const s=state(),payload=JSON.parse(JSON.stringify(s));
 const raw=JSON.stringify(payload);
 let hash=2166136261;
 for(let i=0;i<raw.length;i++){hash^=raw.charCodeAt(i);hash=Math.imul(hash,16777619)}
 return {atlasBackup:true,formatVersion:1,schemaVersion:s.schemaVersion||31,createdAt:new Date().toISOString(),checksum:(hash>>>0).toString(16).padStart(8,"0"),payload};
}
function validateBackupEnvelope(doc){
 if(!doc||typeof doc!=="object")throw new Error("El archivo no contiene un respaldo válido.");
 const payload=doc.atlasBackup===true?doc.payload:(doc.data||doc.payload||doc);
 if(!payload||typeof payload!=="object")throw new Error("No se encontraron datos recuperables.");
 if(!payload.company||!Array.isArray(payload.users)||!Array.isArray(payload.products)||!Array.isArray(payload.sales))throw new Error("El respaldo está incompleto o no pertenece a ATLAS.");
 const schema=Number(doc.schemaVersion||payload.schemaVersion||0);
 if(schema>40)throw new Error("Este respaldo pertenece a una versión futura de ATLAS.");
 if(doc.atlasBackup===true){
  if(!doc.checksum)throw new Error("El respaldo no contiene firma de integridad.");
  const expected=backupChecksum(JSON.stringify(payload));
  if(String(doc.checksum)!==String(expected))throw new Error("El respaldo fue modificado o está dañado: la firma de integridad no coincide.");
 }
 return payload;
}
function downloadJSON(name,obj){
 const blob=new Blob([JSON.stringify(obj,null,2)],{type:"application/json"});
 const url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function exportSafeBackup(){
 requirePermission("backup","crear respaldos");
 const env=backupEnvelope(),stamp=new Date().toISOString().slice(0,10);
 downloadJSON(`ATLAS-respaldo-${stamp}.json`,env);
 DB.log("Respaldo integral exportado","EXPORT","backup");
 DB.save();
}
function restoreSafeBackup(file){
 requirePermission("backup","restaurar respaldos"); sensitiveConfirm("restaurar un respaldo");
 if(!file)throw new Error("Selecciona un archivo.");
 const reader=new FileReader();
 reader.onload=()=>{
  try{
   const doc=JSON.parse(String(reader.result||"{}")),payload=validateBackupEnvelope(doc);
   if(!confirm("La restauración reemplazará los datos locales actuales. ¿Deseas continuar?"))return;
   localStorage.setItem("atlas_phase3_data",JSON.stringify(payload));
   alert("Respaldo restaurado correctamente. ATLAS se recargará.");
   location.reload();
  }catch(e){alert(e.message||"No se pudo restaurar el respaldo.");}
 };
 reader.readAsText(file);
}
function installationHealth(){
 const s=state();
 const checks=[
  ["Datos locales",!!localStorage.getItem("atlas_phase3_data")],
  ["Versión de esquema",Number(s.schemaVersion)===31],
  ["Empresa configurada",!!s.company?.name],
  ["Administrador",!!(s.users||[]).length],
  ["Roles",(s.roles||[]).length>0],
  ["Sucursales",(s.branches||[]).length>0],
  ["Configuración fiscal",!!s.settings?.fiscalConfig],
  ["Política de seguridad",!!s.settings?.securityPolicy],
  ["Service Worker","serviceWorker" in navigator]
 ];
 return checks;
}
function maintenancePage(){
 const checks=installationHealth(),ok=checks.filter(x=>x[1]).length;
 return `<div class="hero"><div><h2>Instalación y recuperación</h2><p>Estado local, respaldo y preparación para publicación.</p></div>
 <div class="hero-actions"><button class="btn btn-primary" id="safeBackupBtn">Crear respaldo</button><label class="btn btn-soft">Restaurar respaldo<input id="safeRestoreInput" type="file" accept=".json,application/json" hidden></label></div></div>
 <div class="grid stats">
  <div class="card stat"><div class="label">Preparación local</div><div class="value">${ok}/${checks.length}</div><div class="hint">Controles superados</div></div>
  <div class="card stat"><div class="label">Versión</div><div class="value">31</div><div class="hint">Esquema local</div></div>
  <div class="card stat"><div class="label">PWA</div><div class="value">${"serviceWorker" in navigator?"Compatible":"No disponible"}</div><div class="hint">Instalación en dispositivo</div></div>
  <div class="card stat"><div class="label">Nube</div><div class="value">${isSupabaseConfigured()?"Configurada":"Pendiente"}</div><div class="hint">Se hará al final</div></div>
 </div>
 <div class="card">${table(["Comprobación","Estado"],checks.map(([n,v])=>[esc(n),`<span class="badge ${v?"ok":"warn"}">${v?"Correcto":"Revisar"}</span>`]))}</div>
 <div style="height:16px"></div><div class="card"><div class="notice"><strong>Actualizaciones:</strong> ATLAS mantiene la clave local histórica para no perder los datos al actualizar archivos del programa.</div>
 <div class="notice"><strong>Recomendación:</strong> crear un respaldo antes de publicar una versión nueva o antes de restaurar datos.</div></div>`;
}


function cloudReadinessPage(){
 const configured=isSupabaseConfigured();
 const checks=[
  ["Frontend sin service_role",!JSON.stringify(window.ATLAS_CONFIG||{}).toLowerCase().includes("service_role")],
  ["Supabase URL",configured],
  ["Clave pública",configured],
  ["SQL producción Fase 32","Preparado"],
  ["RLS por empresa","Preparado"],
  ["Acceso por sucursal","Preparado"],
  ["Auth real","Se activa al conectar"]
 ];
 return `<div class="hero"><div><h2>Preparación de Supabase</h2><p>ATLAS está listo para pasar del almacenamiento local a PostgreSQL y autenticación real.</p></div></div>
 <div class="grid stats">
  <div class="card stat"><div class="label">Estado</div><div class="value">${configured?"Conectado":"Preparado"}</div><div class="hint">${configured?"Credenciales públicas detectadas":"Falta crear/conectar el proyecto"}</div></div>
  <div class="card stat"><div class="label">Base de datos</div><div class="value">PostgreSQL</div><div class="hint">Esquema Fase 32</div></div>
  <div class="card stat"><div class="label">Seguridad</div><div class="value">RLS</div><div class="hint">Empresa + sucursal</div></div>
  <div class="card stat"><div class="label">Credencial privada</div><div class="value">No</div><div class="hint">service_role prohibida en frontend</div></div>
 </div>
 <div class="card">${table(["Comprobación","Estado"],checks.map(([a,b])=>[a,`<span class="badge ${(b===true||b==="Preparado")?"ok":"warn"}">${b===true?"Correcto":b===false?"Pendiente":esc(b)}</span>`]))}</div>
 <div style="height:16px"></div><div class="card"><div class="notice">El siguiente paso requiere crear el proyecto gratuito de Supabase. No hace falta hacerlo hasta que vayamos a conectarlo de verdad.</div></div>`;
}


function migrationPage(){
 const pkg=buildMigrationPackage(state()),check=validateMigrationPackage(pkg),stats=migrationStats(pkg);
 const rows=Object.entries(stats).map(([k,v])=>[k,String(v)]);
 return `<div class="hero"><div><h2>Migración a Supabase</h2><p>Preparación de los datos locales antes de crear la base real.</p></div><button class="btn btn-primary" id="exportMigrationBtn">Exportar paquete de migración</button></div>
 <div class="grid stats">
  <div class="card stat"><div class="label">Estado</div><div class="value">${check.ok?"Preparado":"Revisar"}</div><div class="hint">${check.errors.length} errores · ${check.warnings.length} advertencias</div></div>
  <div class="card stat"><div class="label">Origen</div><div class="value">Local v${state().schemaVersion}</div><div class="hint">No modifica tus datos</div></div>
  <div class="card stat"><div class="label">Destino</div><div class="value">Supabase</div><div class="hint">PostgreSQL + Auth</div></div>
  <div class="card stat"><div class="label">Usuarios</div><div class="value">${(pkg.users||[]).length}</div><div class="hint">Se convertirán a Auth real</div></div>
 </div>
 <div class="grid two"><div class="card">${table(["Conjunto","Registros"],rows)}</div>
 <div class="card"><div class="section-title"><h3>Validación</h3></div>
 ${check.errors.map(x=>`<div class="notice danger">${esc(x)}</div>`).join("")}
 ${check.warnings.map(x=>`<div class="notice">${esc(x)}</div>`).join("")}
 ${check.ok&&!check.warnings.length?'<div class="notice">El paquete local está estructuralmente listo para migración.</div>':""}
 <div class="notice">Las contraseñas/PIN locales no se exportan. Los usuarios se crearán mediante Supabase Auth.</div></div></div>`;
}
function exportMigrationPackage(){
 requirePermission("backup","exportar migración");
 const pkg=buildMigrationPackage(state()),check=validateMigrationPackage(pkg);
 if(!check.ok)throw new Error("Corrige primero los errores de migración.");
 downloadJSON(`ATLAS-migracion-${new Date().toISOString().slice(0,10)}.json`,pkg);
 DB.log("Paquete de migración generado","EXPORT","migration");DB.save();
}


async function testCloudSession(){try{const session=await cloudSession();if(!session){alert("Supabase está preparado, pero todavía no hay una sesión real.");return;}const profile=await cloudProfile();alert(`Sesión válida: ${profile?.full_name||session.user.email}`);}catch(e){alert(e.message||"No se pudo validar la sesión.");}}
function cloudAccessPage(){const available=cloudAuthAvailable();return `<div class="hero"><div><h2>Acceso real de ATLAS</h2><p>Preparación del inicio de sesión mediante Supabase Auth.</p></div><button class="btn btn-primary" id="testCloudSessionBtn" ${available?"":"disabled"}>Comprobar sesión</button></div><div class="grid stats"><div class="card stat"><div class="label">Cliente Supabase</div><div class="value">${available?"Detectado":"Pendiente"}</div><div class="hint">Se activará al conectar el proyecto</div></div><div class="card stat"><div class="label">Contraseña local</div><div class="value">No migrada</div><div class="hint">Se reemplaza por Auth real</div></div><div class="card stat"><div class="label">Sesiones</div><div class="value">Seguras</div><div class="hint">Administradas por Supabase</div></div><div class="card stat"><div class="label">Modo actual</div><div class="value">${available?"Nube preparada":"Local"}</div><div class="hint">No se cambia hasta validar</div></div></div><div class="card"><div class="notice">ATLAS mantiene el acceso local mientras preparamos la nube. No se forzará el cambio hasta que la base, usuarios y migración estén verificados.</div></div>`;}
function migrationReviewPage(){let plan,check;try{plan=buildImportPlan(buildMigrationPackage(state()));check=validateImportPlan(plan);}catch(e){return `<div class="card"><div class="notice danger">${esc(e.message)}</div></div>`;}return `<div class="hero"><div><h2>Revisión previa a importación</h2><p>Orden exacto en que ATLAS cargará los datos en Supabase.</p></div></div><div class="grid stats"><div class="card stat"><div class="label">Registros</div><div class="value">${plan.totalRows}</div><div class="hint">Total preparado</div></div><div class="card stat"><div class="label">Pasos</div><div class="value">${plan.steps.length}</div><div class="hint">Importación ordenada</div></div><div class="card stat"><div class="label">Validación</div><div class="value">${check.ok?"Correcta":"Revisar"}</div><div class="hint">${check.errors.length} errores</div></div><div class="card stat"><div class="label">Ejecución</div><div class="value">Bloqueada</div><div class="hint">Hasta conectar Supabase</div></div></div><div class="card">${table(["Orden","Conjunto","Registros"],plan.steps.map((s,i)=>[String(i+1),esc(s.table),String(s.count)]))}</div><div style="height:16px"></div><div class="card"><div class="notice">Esta pantalla solo prepara y valida. Todavía no escribe nada en la nube.</div></div>`;}


async function runCloudDryRun(){
 try{
  const plan=buildImportPlan(buildMigrationPackage(state()));
  const valid=validateImportPlan(plan);if(!valid.ok)throw new Error(valid.errors.join("\n"));
  const result=await executeCloudImport(plan,{confirmToken:"IMPORTAR-ATLAS",dryRun:true});
  alert(`Prueba segura completada.\nEmpresa: ${result.companyId}\nPasos: ${result.steps.length}\nNo se escribió ningún dato.`);
 }catch(e){alert(e.message||"No se pudo ejecutar la prueba.");}
}
async function compareCloudMigration(){
 try{
  const plan=buildImportPlan(buildMigrationPackage(state())),rows=await compareCloudCounts(plan);
  const text=rows.map(r=>`${r.table}: local ${r.local} / nube ${r.error?"error":r.cloud}`).join("\n");
  alert(text||"Sin conjuntos para comparar.");
 }catch(e){alert(e.message||"No se pudieron comparar los conteos.");}
}
function cloudActivationPage(){
 const available=cloudAuthAvailable();
 return `<div class="hero"><div><h2>Activación controlada de nube</h2><p>Últimos controles antes de permitir una migración real.</p></div></div>
 <div class="grid stats">
  <div class="card stat"><div class="label">Supabase</div><div class="value">${available?"Conectado":"Pendiente"}</div><div class="hint">Cliente público</div></div>
  <div class="card stat"><div class="label">Prueba de importación</div><div class="value">Dry-run</div><div class="hint">No escribe datos</div></div>
  <div class="card stat"><div class="label">Comparación</div><div class="value">Local ↔ Nube</div><div class="hint">Conteo por tabla</div></div>
  <div class="card stat"><div class="label">Importación real</div><div class="value">Protegida</div><div class="hint">Pendiente de mapa de IDs</div></div>
 </div>
 <div class="card"><div class="section-title"><h3>Controles de activación</h3></div>
 <div class="quick-actions"><button class="btn btn-primary" id="cloudDryRunBtn" ${available?"":"disabled"}>Ejecutar prueba segura</button>
 <button class="btn btn-soft" id="cloudCompareBtn" ${available?"":"disabled"}>Comparar conteos</button></div>
 <div class="notice">La importación real permanece detenida hasta convertir correctamente los identificadores locales a UUID de producción. ATLAS no intentará insertar datos con relaciones incorrectas.</div></div>`;
}


function migrationMappingPage(){
 const pkg=buildMigrationPackage(state()),refs=validateReferences(pkg),maps=buildIdMap(pkg),cov=mappingCoverage(maps);
 return `<div class="hero"><div><h2>Mapa de relaciones</h2><p>Verificación final de vínculos antes de convertir IDs locales a UUID.</p></div></div>
 <div class="grid stats">
  <div class="card stat"><div class="label">IDs detectados</div><div class="value">${cov.total}</div><div class="hint">Entidades principales</div></div>
  <div class="card stat"><div class="label">Relaciones</div><div class="value">${refs.ok?"Correctas":"Revisar"}</div><div class="hint">${refs.errors.length} inconsistencias</div></div>
  <div class="card stat"><div class="label">UUID asignados</div><div class="value">${cov.mapped}</div><div class="hint">Se generan al importar</div></div>
  <div class="card stat"><div class="label">Importación real</div><div class="value">${cov.pending===0&&refs.ok?"Lista":"Protegida"}</div><div class="hint">${cov.pending} IDs pendientes</div></div>
 </div>
 <div class="card"><div class="section-title"><h3>Integridad referencial local</h3></div>
 ${refs.ok?'<div class="notice">No se encontraron referencias huérfanas en inventario, ventas ni compras.</div>':refs.errors.slice(0,30).map(e=>`<div class="notice danger">${esc(e)}</div>`).join("")}
 </div><div style="height:16px"></div>
 <div class="card"><div class="notice">Los UUID definitivos se asignarán durante la importación controlada. Esta etapa no modifica la información local.</div></div>`;
}

function integralAuditPage(){const a=runIntegralAudit(state());return `<div class="hero"><div><h2>Revisión integral interna</h2><p>Control de consistencia antes de la prueba general de ATLAS.</p></div></div><div class="grid stats"><div class="card stat"><div class="label">Puntuación</div><div class="value">${a.score}%</div><div class="hint">Controles estructurales</div></div><div class="card stat"><div class="label">Estado</div><div class="value">${a.ok?"Correcto":"Requiere corrección"}</div><div class="hint">${a.issues.length} errores críticos</div></div><div class="card stat"><div class="label">Advertencias</div><div class="value">${a.warnings.length}</div><div class="hint">Revisión preventiva</div></div><div class="card stat"><div class="label">Prueba del usuario</div><div class="value">${a.ok?"Más cerca":"Aún no"}</div><div class="hint">Después del cierre interno</div></div></div><div class="card">${table(["Control","Resultado","Detalle"],a.checks.map(c=>[esc(c.name),c.ok?"Correcto":"Revisar",esc(c.detail)]))}</div>${a.issues.length?`<div style="height:16px"></div><div class="card"><h3>Correcciones necesarias</h3>${a.issues.map(x=>`<div class="notice danger">${esc(x)}</div>`).join("")}</div>`:""}${a.warnings.length?`<div style="height:16px"></div><div class="card"><h3>Advertencias</h3>${a.warnings.map(x=>`<div class="notice">${esc(x)}</div>`).join("")}</div>`:""}`;}

function workflowAuditPage(){
 const a=runWorkflowAudit(state()),c=a.counts;
 return `<div class="hero"><div><h2>Auditoría de flujos</h2><p>Revisión cruzada entre ventas, compras, caja, inventario y cuentas.</p></div></div>
 <div class="grid stats"><div class="card stat"><div class="label">Puntuación</div><div class="value">${a.score}%</div><div class="hint">Coherencia entre módulos</div></div>
 <div class="card stat"><div class="label">Ventas / Compras</div><div class="value">${c.sales} / ${c.purchases}</div><div class="hint">Documentos revisados</div></div>
 <div class="card stat"><div class="label">CxC / CxP</div><div class="value">${c.receivables} / ${c.payables}</div><div class="hint">Saldos relacionados</div></div>
 <div class="card stat"><div class="label">Caja</div><div class="value">${c.cash}</div><div class="hint">Movimientos revisados</div></div></div>
 <div class="card">${table(["Flujo","Resultado","Detalle"],a.checks.map(x=>[esc(x.name),x.ok?"Correcto":"Revisar",esc(x.detail)]))}</div>
 ${a.issues.length?`<div style="height:16px"></div><div class="card"><h3>Incidencias</h3>${a.issues.map(x=>`<div class="notice danger">${esc(x)}</div>`).join("")}</div>`:""}
 ${a.warnings.length?`<div style="height:16px"></div><div class="card"><h3>Observaciones</h3>${a.warnings.map(x=>`<div class="notice">${esc(x)}</div>`).join("")}</div>`:""}`;
}


function printPurchase(id){
 const s=state(),p=s.purchases.find(x=>x.id===id);if(!p)return alert("Compra no encontrada.");
 const supplier=s.suppliers.find(x=>x.id===p.supplierId),currency=p.currency||"USD";
 const rows=(p.items||[]).map(i=>{const prod=s.products.find(x=>x.id===i.productId);return [esc(prod?.name||i.name||"Producto"),fmt(i.qty),money(i.cost||i.price||0,currency),money((i.qty||0)*(i.cost||i.price||0),currency)]});
 const voided=["anulada","cancelled","void"].includes(String(p.status||"").toLowerCase());
 docPrint(`Compra ${p.number||""}`,`${voided?'<div style="font-size:54px;font-weight:800;opacity:.15;text-align:center">ANULADA</div>':""}<h1>Compra ${esc(p.number||"")}</h1><p><b>Proveedor:</b> ${esc(supplier?.name||"")}</p><p><b>Fecha:</b> ${esc(p.date||"")}</p>${table(["Producto","Cant.","Costo","Total"],rows)}<h2>Total: ${money(p.total||0,currency)}</h2>`);
}
function printExpense(id){
 const s=state(),e=(s.expenses||[]).find(x=>x.id===id);if(!e)return alert("Gasto no encontrado.");
 const currency=e.currency||"USD";
 docPrint(`Comprobante ${e.reference||e.number||""}`,`<h1>Comprobante de gasto</h1><p><b>Referencia:</b> ${esc(e.reference||e.number||"")}</p><p><b>Fecha:</b> ${esc(e.date||"")}</p><p><b>Concepto:</b> ${esc(e.description||e.concept||"")}</p><h2>Monto: ${money(e.amount||e.total||0,currency)}</h2>`);
}


function releaseReadinessPage(){
 const r=releaseReadiness(state());
 return `<div class="hero"><div><h2>Preparación para revisión</h2><p>Puertas de control antes de publicar ATLAS para tu prueba general.</p></div></div>
 <div class="grid stats"><div class="card stat"><div class="label">Estado</div><div class="value">${r.ready?"Preparado":"En revisión"}</div><div class="hint">Control interno</div></div>
 <div class="card stat"><div class="label">Estructura</div><div class="value">${r.structural.score}%</div><div class="hint">Integridad</div></div>
 <div class="card stat"><div class="label">Flujos</div><div class="value">${r.workflow.score}%</div><div class="hint">Módulos conectados</div></div>
 <div class="card stat"><div class="label">Publicación</div><div class="value">${r.ready?"Siguiente":"Bloqueada"}</div><div class="hint">No publica con fallos</div></div></div>
 <div class="card">${table(["Puerta de control","Resultado","Detalle"],r.gates.map(g=>[esc(g.name),g.ok?"Correcto":"Revisar",esc(g.detail)]))}</div>
 <div style="height:16px"></div><div class="card"><div class="notice">${r.ready?"Las puertas automáticas están correctas. Falta la comprobación final de ejecución y el despliegue de revisión.":"ATLAS no se publicará para revisión mientras exista una puerta pendiente."}</div></div>`;
}

function deploymentAuditPage(){
 const s=state(),r=releaseReadiness(s),checks=[["Empresa configurada",!!s.company?.name],["Sucursal disponible",(s.branches||[]).length>0],["Usuarios",(s.users||[]).length>0],["Inventario",Array.isArray(s.inventory)],["Ventas",Array.isArray(s.sales)],["Compras",Array.isArray(s.purchases)],["Caja",Array.isArray(s.cashMovements)],["Contabilidad",Array.isArray(s.journalEntries)],["Preparación 5/5",r.ready]],ok=checks.filter(x=>x[1]).length;
 return `<div class="hero"><div><h2>Control de despliegue</h2><p>Última comprobación local antes de publicar ATLAS.</p></div></div><div class="card"><h3>${ok}/${checks.length} controles correctos</h3>${table(["Comprobación","Estado"],checks.map(x=>[x[0],x[1]?"Correcto":"Revisar"]))}</div>`;
}


function mountingStatusPage(){
 const c=cloudActivationState(),ready=releaseReadiness(state());
 return `<div class="hero"><div><h2>Montaje final</h2><p>Estado de ATLAS antes de activar la base de datos real.</p></div></div>
 <div class="grid stats">
 <div class="card stat"><div class="label">Aplicación</div><div class="value">${ready.ready?"Lista":"Revisar"}</div><div class="hint">Controles internos</div></div>
 <div class="card stat"><div class="label">Supabase</div><div class="value">${c.verified?"Verificado":"Pendiente"}</div><div class="hint">Sesión + empresa</div></div>
 <div class="card stat"><div class="label">Modo nube</div><div class="value">${isCloudMode()?"Activo":"Inactivo"}</div><div class="hint">Activación protegida</div></div>
 <div class="card stat"><div class="label">Publicación</div><div class="value">${ready.ready&&c.verified?"Preparada":"Protegida"}</div><div class="hint">No se activa por accidente</div></div></div>
 <div class="card"><h3>Activación controlada</h3><p>ATLAS continuará trabajando en modo local hasta verificar una sesión real de Supabase y su empresa.</p>
 <div class="quick-actions"><button class="btn btn-primary" id="verifyCloudActivationBtn">Verificar nube</button><button class="btn btn-soft" id="enableCloudModeBtn">Activar modo nube</button><button class="btn btn-soft" id="disableCloudModeBtn">Volver a modo local</button></div></div>`;
}

function dashboard(){
 const s=state(),range=defaultReportRange(),m=reportMetrics(range.from,range.to),audit=runIntegrityAudit();
 const low=(s.inventory||[]).filter(i=>Number(i.stock||0)<=Number(s.settings.reporting?.lowStockThreshold||5));
 const overdue=agedReceivables().filter(r=>r.days>Number(s.settings.reporting?.staleReceivableDays||30));
 const cashDiff=(s.cashClosings||[]).filter(c=>c.status==="Con diferencia");
 const recent=(s.sales||[]).slice().reverse().slice(0,6),top=topProductsReport(m.sales).slice(0,5);
 const quick=[["Nueva venta","sales","＋"],["Nueva compra","purchases","↗"],["Registrar gasto","expenses","−"],["Cobrar cliente","receivables","✓"],["Pagar proveedor","payables","⇩"],["Ver reportes","reports","▥"]];
 return `<div class="atlas-dashboard">
 <div class="dash-top"><div><div class="eyebrow">ATLAS · Sistema de Gestión Empresarial</div><h1>Bienvenido a ATLAS</h1><p>Control total para hacer crecer tu negocio.</p></div><div class="dash-context"><span>${esc(s.company?.name||"Empresa")}</span><span>${new Date().toLocaleDateString("es-VE",{day:"2-digit",month:"short",year:"numeric"})}</span></div></div>
 <div class="kpi-grid">
  <div class="kpi-card"><div class="kpi-icon">↗</div><div><span>Ventas del mes</span><strong>USD ${money(m.netSales)}</strong><small>Después de devoluciones</small></div></div>
  <div class="kpi-card"><div class="kpi-icon">◎</div><div><span>Utilidad estimada</span><strong>USD ${money(m.netProfit)}</strong><small>Ventas - costo - gastos</small></div></div>
  <div class="kpi-card"><div class="kpi-icon">▦</div><div><span>Inventario valorizado</span><strong>USD ${money(m.inventoryValue)}</strong><small>${low.length} con stock bajo</small></div></div>
  <div class="kpi-card"><div class="kpi-icon">◷</div><div><span>Cuentas por cobrar</span><strong>USD ${money(m.ar)}</strong><small>${overdue.length} vencidas</small></div></div>
  <div class="kpi-card"><div class="kpi-icon">⇩</div><div><span>Cuentas por pagar</span><strong>USD ${money(m.ap)}</strong><small>Saldo actual</small></div></div>
  <div class="kpi-card"><div class="kpi-icon">✓</div><div><span>Integridad</span><strong>${audit.issues.length?"Revisar":"Correcta"}</strong><small>${audit.issues.length} incidencia(s)</small></div></div>
 </div>
 <div class="dashboard-grid">
  <div class="dash-panel wide"><div class="panel-head"><div><h3>Resumen del período</h3><p>Mes actual</p></div><button class="btn btn-soft" data-nav="reports">Ver reporte</button></div><div class="metric-strip"><div><span>Ventas brutas</span><strong>USD ${money(m.salesGross)}</strong></div><div><span>Devoluciones</span><strong>USD ${money(m.returnsSales)}</strong></div><div><span>Ventas netas</span><strong>USD ${money(m.netSales)}</strong></div><div><span>Utilidad bruta</span><strong>USD ${money(m.grossProfit)}</strong></div></div></div>
  <div class="dash-panel"><div class="panel-head"><div><h3>Productos más vendidos</h3><p>Por valor vendido</p></div></div><div class="rank-list">${top.length?top.map((x,i)=>`<div class="rank-row"><span class="rank">${i+1}</span><div><strong>${esc(x.name)}</strong><small>${money(x.qty)} unidades</small></div><b>USD ${money(x.total)}</b></div>`).join(""):'<div class="empty-state">Todavía no hay ventas.</div>'}</div></div>
  <div class="dash-panel"><div class="panel-head"><div><h3>Estado de cuentas</h3><p>Lo que entra y lo que debes</p></div></div><div class="account-bars"><div><div class="account-label"><span>Por cobrar</span><b>USD ${money(m.ar)}</b></div><div class="bar"><i style="width:${Math.min(100,m.ar?70:0)}%"></i></div></div><div><div class="account-label"><span>Por pagar</span><b>USD ${money(m.ap)}</b></div><div class="bar"><i style="width:${Math.min(100,m.ap?55:0)}%"></i></div></div></div></div>
 </div>
 <div class="quick-section"><div class="section-heading"><div><h3>Acciones rápidas</h3><p>Lo más usado, siempre a mano.</p></div></div><div class="quick-grid">${quick.map(([label,page,icon])=>`<button class="quick-action" data-nav="${page}"><span>${icon}</span><b>${label}</b></button>`).join("")}</div></div>
 <div class="dashboard-grid bottom-grid">
  <div class="dash-panel wide"><div class="panel-head"><div><h3>Últimas ventas</h3><p>Actividad reciente</p></div><button class="btn btn-soft" data-nav="sales">Ver ventas</button></div>${recent.length?table(["N°","Fecha","Cliente","Total","Estado"],recent.map(v=>[esc(v.number),datefmt(v.date),esc(s.customers.find(c=>c.id===v.customerId)?.name||"Consumidor final"),moneyWithCurrency(v.documentTotal??v.total,v.currency||"USD"),`<span class="badge ${v.status==="Anulada"?"warn":"ok"}">${esc(v.status)}</span>`])):'<div class="empty-state">No hay ventas registradas.</div>'}</div>
  <div class="dash-panel alerts-panel"><div class="panel-head"><div><h3>Alertas y notificaciones</h3><p>Solo lo importante</p></div></div><div class="alert-stack">${low.length?`<button data-nav="inventory"><span>Stock bajo</span><b>${low.length}</b></button>`:""}${overdue.length?`<button data-nav="receivables"><span>CxC vencidas</span><b>${overdue.length}</b></button>`:""}${cashDiff.length?`<button data-nav="cash"><span>Diferencias de caja</span><b>${cashDiff.length}</b></button>`:""}${audit.issues.length?`<button data-nav="system"><span>Integridad</span><b>${audit.issues.length}</b></button>`:""}${!low.length&&!overdue.length&&!cashDiff.length&&!audit.issues.length?'<div class="empty-state">Sin alertas críticas.</div>':""}</div></div>
 </div></div>`;
}
function company(){
 const c=state().company;
 return `<div class="hero"><div><h2>Empresa</h2><p>Identidad y configuración principal.</p></div></div>
 <div class="card"><form id="companyForm" class="form-grid">
 ${field("Nombre","name",c.name)}${field("RIF / ID fiscal","taxId",c.taxId)}${field("Teléfono","phone",c.phone)}${field("Correo","email",c.email)}
 ${field("País","country",c.country)}
 <div class="field"><label>Moneda base</label><select name="baseCurrency">${["VES","USD","EUR"].map(x=>`<option ${x===c.baseCurrency?"selected":""}>${x}</option>`).join("")}</select></div>
 <div class="field"><label>Moneda visual</label><select name="displayCurrency">${["USD","VES","EUR","USDT"].map(x=>`<option ${x===c.displayCurrency?"selected":""}>${x}</option>`).join("")}</select></div>
 <div></div><div><button class="btn btn-primary">Guardar cambios</button></div></form></div>`;
}
function branches(){
 const s=state();
 return `<div class="hero"><div><h2>Sucursales</h2><p>Operaciones separadas por sede.</p></div><button class="btn btn-primary" data-add="branch">+ Nueva sucursal</button></div>${table(["Nombre","Ciudad","Estado",""],s.branches.map(b=>[
  `<strong>${esc(b.name)}</strong>`,esc(b.city),
  `<span class="badge ${(b.status||"Activo")==="Activo"?"ok":"warn"}">${esc(b.status||"Activo")}</span>`,
  `<button class="btn ${(b.status||"Activo")==="Inactivo"?"btn-soft":"btn-danger"}" data-delete="branch:${b.id}">${(b.status||"Activo")==="Inactivo"?"Reactivar":"Desactivar"}</button>`
 ]))}`;
}
function customers(){return partyPage("customer","Clientes","customers")}
function suppliers(){return partyPage("supplier","Proveedores","suppliers")}
function partyPage(kind,title,key){
 const arr=state()[key];
 return `<div class="hero"><div><h2>${title}</h2><p>Registro y búsqueda centralizada.</p></div><button class="btn btn-primary" data-add="${kind}">+ Nuevo</button></div>
 <div class="toolbar"><input data-search="${kind}" placeholder="Buscar por nombre, código, RIF..."></div><div id="${kind}Table">${partyTable(kind,arr)}</div>`;
}
function partyTable(kind,arr){
 return table(["Código","Nombre","RIF / ID","Teléfono","Ciudad","Saldo","Estado",""],arr.map(x=>[
  esc(x.code),`<strong>${esc(x.name)}</strong>`,esc(x.taxId),esc(x.phone),esc(x.city),`$ ${money(x.balance||0)}`,
  `<span class="badge ${(x.status||"Activo")==="Activo"?"ok":"warn"}">${esc(x.status||"Activo")}</span>`,
  `<button class="btn ${(x.status||"Activo")==="Inactivo"?"btn-soft":"btn-danger"}" data-delete="${kind}:${x.id}">${(x.status||"Activo")==="Inactivo"?"Reactivar":"Desactivar"}</button>`
 ]));
}
function products(){
 const p=state().products;
 return `<div class="hero"><div><h2>Productos</h2><p>Catálogo, precios e impuestos.</p></div><button class="btn btn-primary" data-add="product">+ Nuevo producto</button></div>
 <div class="toolbar"><input data-search="product" placeholder="Buscar SKU, producto o categoría..."></div><div id="productTable">${productTable(p)}</div>`;
}
function productTable(arr){
 return table(["SKU","Producto","Categoría","Costo","Precio","IVA","Mínimo","Estado",""],arr.map(p=>[
  esc(p.sku),`<strong>${esc(p.name)}</strong>`,esc(p.category),money(p.cost),money(p.price),`${esc(p.tax)}%`,esc(p.minStock),
  `<span class="badge ${(p.status||"Activo")==="Activo"?"ok":"warn"}">${esc(p.status||"Activo")}</span>`,
  `<button class="btn ${(p.status||"Activo")==="Inactivo"?"btn-soft":"btn-danger"}" data-delete="product:${p.id}">${(p.status||"Activo")==="Inactivo"?"Reactivar":"Desactivar"}</button>`
 ]));
}

function sales(){
 const s=state();
 return `<div class="hero"><div><h2>Ventas</h2><p>Venta rápida conectada con inventario, caja y cuentas por cobrar.</p></div>
    <div class="hero-actions">${moduleAllowed("quotations")?'<button class="btn btn-soft" data-nav="quotations">Cotizaciones</button>':""}${moduleAllowed("returns")?'<button class="btn btn-soft" data-nav="returns">Devoluciones</button>':""}</div></div>
 <div class="pos-grid">
  <div class="card"><div class="section-title"><h3>Productos</h3><span class="badge ok">${s.products.length} disponibles</span></div>
   <div class="pos-products">${s.products.filter(p=>(p.status||"Activo")!=="Inactivo").map(p=>`<div class="product-tile" data-cart-add="${p.id}"><strong>${esc(p.name)}</strong><small>${esc(p.sku)}</small><div style="margin-top:8px;font-weight:900">$ ${money(p.price)}</div></div>`).join("")}</div>
  </div>
  <div class="card"><div class="section-title"><h3>Venta actual</h3><button class="btn btn-soft" id="clearCart">Vaciar</button></div>
   <div class="form-grid">
    <div class="field"><label>Cliente</label><select id="saleCustomer">${s.customers.filter(c=>(c.status||"Activo")!=="Inactivo").map(c=>`<option value="${c.id}">${esc(c.name)}</option>`).join("")}</select></div>
    <div class="field"><label>Sucursal</label><select id="saleBranch">${DB.visibleBranches().filter(b=>(b.status||"Activo")!=="Inactivo").map(b=>`<option value="${b.id}">${esc(b.name)}</option>`).join("")}</select></div>
   </div>
   <div id="cartRows">${renderCartRows()}</div>
   <div class="total-box">${saleTotalsHtml()}</div>
   <div class="form-grid" style="margin-top:12px">
    <div class="field"><label>Moneda del documento</label><select id="saleCurrency">${currencyOptions("USD")}</select></div>
    <div class="field"><label>Condición</label><select id="saleCondition"><option value="cash">Contado</option><option value="credit">Crédito</option></select></div>
    <div class="field"><label>Método de pago</label><select id="salePaymentMethod">${activePaymentMethods().map(m=>`<option value="${m.id}">${esc(m.name)}</option>`).join("")}</select></div>
    <div class="field"><label>Cuenta de cobro</label><select id="saleAccount">${activeCashAccounts().map(a=>`<option value="${a.id}">${esc(a.name)} (${esc(a.currency)})</option>`).join("")}</select></div>
   </div>
   <button class="btn btn-primary btn-block" id="completeSale">Completar venta</button>
  </div>
 </div>
 <div style="height:16px"></div>
 ${table(["N°","Fecha","Cliente","Sucursal","Total documento","Base USD","Condición","Estado",""],s.sales.slice().reverse().map(x=>[
   esc(x.number),datefmt(x.date),esc(s.customers.find(c=>c.id===x.customerId)?.name||""),esc(s.branches.find(b=>b.id===x.branchId)?.name||""),moneyWithCurrency(x.documentTotal??x.total,x.currency||"USD"),`USD ${money(x.baseTotalUSD??x.total)}`,x.condition==="cash"?"Contado":"Crédito",`<span class="badge ${x.status==="Anulada"?"warn":"ok"}">${esc(x.status)}</span>`,
   `<button class="btn btn-soft" data-print-sale="${x.id}">Imprimir</button> ${x.status!=="Anulada"?`<button class="btn btn-danger" data-void-sale="${x.id}">Anular</button>`:""}`
 ]))}`;
}
function cartTotals(){
 const subtotal=cart.reduce((a,i)=>a+i.qty*i.price,0);
 const tax=cart.reduce((a,i)=>a+(i.qty*i.price)*(i.tax/100),0);
 return {subtotal,tax,total:subtotal+tax};
}
function saleTotalsHtml(){const t=cartTotals();return `<div class="line"><span>Subtotal</span><strong>$ ${money(t.subtotal)}</strong></div><div class="line"><span>Impuestos</span><strong>$ ${money(t.tax)}</strong></div><div class="line grand"><span>Total</span><span>$ ${money(t.total)}</span></div>`}
function renderCartRows(){
 if(!cart.length)return `<div class="notice" style="margin:12px 0">Haz clic en un producto para agregarlo a la venta.</div>`;
 return cart.map(i=>`<div class="cart-row"><div><strong>${esc(i.name)}</strong><small style="display:block;color:#667085">$ ${money(i.price)} c/u</small></div><input data-cart-qty="${i.productId}" type="number" min="1" value="${i.qty}"><div><strong>$ ${money(i.qty*i.price*(1+i.tax/100))}</strong></div><button class="btn btn-danger" data-cart-remove="${i.productId}">×</button></div>`).join("");
}
function refreshCart(){
 const rows=document.getElementById("cartRows"),tb=document.querySelector(".total-box");if(rows)rows.innerHTML=renderCartRows();if(tb)tb.innerHTML=saleTotalsHtml();bindCart();
}
function bindCart(){
 document.querySelectorAll("[data-cart-qty]").forEach(i=>i.oninput=()=>{const item=cart.find(x=>x.productId===i.dataset.cartQty);if(item)item.qty=Math.max(1,Number(i.value||1));refreshCart()});
 document.querySelectorAll("[data-cart-remove]").forEach(b=>b.onclick=()=>{cart=cart.filter(x=>x.productId!==b.dataset.cartRemove);refreshCart()});
}

function purchases(){
 const s=state();
 return `<div class="hero"><div><h2>Compras</h2><p>Entrada de mercancía conectada con inventario y cuentas por pagar.</p></div><button class="btn btn-primary" id="newPurchase">+ Registrar compra</button></div>
 ${table(["N°","Fecha","Proveedor","Sucursal","Total documento","Base USD","Condición","Estado",""],s.purchases.slice().reverse().map(x=>[
 esc(x.number),datefmt(x.date),esc(s.suppliers.find(p=>p.id===x.supplierId)?.name||""),esc(s.branches.find(b=>b.id===x.branchId)?.name||""),moneyWithCurrency(x.documentTotal??x.total,x.currency||"USD"),`USD ${money(x.baseTotalUSD??x.total)}`,x.condition==="cash"?"Contado":"Crédito",`<span class="badge ok">${esc(x.status)}</span>`
 ]))}`;
}
function cash(){
 const s=state();
 const accounts=activeCashAccounts();
 const openDiffs=(s.cashClosings||[]).filter(c=>c.status==="Con diferencia");
 return `<div class="hero"><div><h2>Caja y bancos</h2><p>Control de saldos, transferencias, cierres y diferencias.</p></div>
 <div class="hero-actions">
  ${moduleAllowed("paymentMethods")?'<button class="btn btn-soft" data-nav="paymentMethods">Métodos de pago</button>':""}
  ${moduleAllowed("rates")?'<button class="btn btn-soft" data-nav="rates">Tasas</button>':""}
  <button class="btn btn-soft" id="newCashTransfer">Transferir</button>
  <button class="btn btn-soft" id="newCashClosing">Cerrar caja</button>
  <button class="btn btn-primary" data-add="cashaccount">+ Nueva cuenta</button>
 </div></div>
 <div class="grid stats">${accounts.map(a=>`<div class="card stat"><div class="label">${esc(a.type)} · ${esc(a.currency)}</div><div class="value">${moneyWithCurrency(a.balance,a.currency)}</div><div class="hint">${esc(a.name)}</div></div>`).join("")}</div>
 ${openDiffs.length?`<div class="notice"><strong>${openDiffs.length} cierre(s) con diferencia pendiente.</strong> Revisa y concilia antes de cerrar el período.</div>`:""}
 <div class="grid two">
  <div class="card"><div class="section-title"><h3>Últimas transferencias</h3></div>
   ${(s.cashTransfers||[]).length?table(["Fecha","Origen","Destino","Enviado","Recibido"],s.cashTransfers.slice(0,8).map(t=>[
    datefmt(t.date),esc(s.cashAccounts.find(a=>a.id===t.fromAccountId)?.name||""),esc(s.cashAccounts.find(a=>a.id===t.toAccountId)?.name||""),
    moneyWithCurrency(t.fromAmount,t.fromCurrency),moneyWithCurrency(t.toAmount,t.toCurrency)
   ])):'<div class="notice">Todavía no hay transferencias entre cuentas.</div>'}
  </div>
  <div class="card"><div class="section-title"><h3>Últimos cierres</h3></div>
   ${(s.cashClosings||[]).length?table(["Fecha","Cuenta","Sistema","Contado","Diferencia","Estado",""],s.cashClosings.slice(0,8).map(c=>[
    datefmt(c.date),esc(s.cashAccounts.find(a=>a.id===c.accountId)?.name||""),moneyWithCurrency(c.systemBalance,c.currency),
    moneyWithCurrency(c.countedBalance,c.currency),moneyWithCurrency(c.difference,c.currency),
    `<span class="badge ${c.status==="Cuadrado"?"ok":c.status==="Conciliado"?"ok":"warn"}">${esc(c.status)}</span>`,
    c.status==="Con diferencia"?`<button class="btn btn-soft" data-reconcile-cash="${c.id}">Conciliar</button>`:""
   ])):'<div class="notice">Todavía no hay cierres de caja.</div>'}
  </div>
 </div>
 <div style="height:16px"></div>
 ${table(["Fecha","Cuenta","Moneda","Método","Tipo","Monto","Referencia","Nota"],s.cashMovements.slice(0,40).map(m=>[
 datefmt(m.date),esc(s.cashAccounts.find(a=>a.id===m.accountId)?.name||""),esc(m.currency||s.cashAccounts.find(a=>a.id===m.accountId)?.currency||"—"),esc(s.paymentMethods.find(pm=>pm.id===m.paymentMethodId)?.name||"—"),m.type==="IN"?'<span class="badge ok">Entrada</span>':'<span class="badge danger">Salida</span>',money(m.amount),esc(m.reference),esc(m.note)
 ]))}`;
}
function receivables(){
 const s=state();
 const credits=(s.customerCredits||[]).filter(c=>Number(c.balance||0)>0);
 return `<div class="hero"><div><h2>Cuentas por cobrar</h2><p>Créditos pendientes de clientes y saldos a favor.</p></div></div>
 ${table(["Documento","Cliente","Fecha","Vence","Documento","Saldo USD","Estado",""],s.receivables.map(r=>[
 esc(r.reference),esc(s.customers.find(c=>c.id===r.customerId)?.name||""),new Date(r.date).toLocaleDateString("es-VE"),new Date(r.dueDate).toLocaleDateString("es-VE"),moneyWithCurrency(r.documentTotal??r.total,r.currency||"USD"),`USD ${money(r.balance)}`,`<span class="badge ${r.balance>0?"warn":"ok"}">${esc(r.status)}</span>`,r.balance>0?`<button class="btn btn-soft" data-pay-ar="${r.id}">Cobrar</button>`:""
 ]))}
 <div style="height:18px"></div>
 <div class="card"><div class="section-title"><h3>Créditos a favor de clientes</h3><span class="badge ${credits.length?"warn":"ok"}">${credits.length} disponible(s)</span></div>
 ${credits.length?table(["Cliente","Origen","Fecha","Crédito original","Disponible",""],credits.map(c=>[
   esc(s.customers.find(x=>x.id===c.customerId)?.name||""),esc(c.reference||""),datefmt(c.date),`USD ${money(c.amount)}`,`USD ${money(c.balance)}`,
   `<button class="btn btn-soft" data-use-credit="${c.id}">Aplicar a deuda</button>`
 ])):'<div class="notice">No hay créditos a favor pendientes.</div>'}</div>`;
}
function payables(){
 const s=state();
 const credits=(s.supplierCredits||[]).filter(c=>Number(c.balance||0)>0);
 return `<div class="hero"><div><h2>Cuentas por pagar</h2><p>Deudas con proveedores, devoluciones y créditos disponibles.</p></div></div>
 ${table(["Documento","Proveedor","Fecha","Vence","Documento","Saldo USD","Estado",""],s.payables.map(r=>[
 esc(r.reference),esc(s.suppliers.find(c=>c.id===r.supplierId)?.name||""),new Date(r.date).toLocaleDateString("es-VE"),new Date(r.dueDate).toLocaleDateString("es-VE"),moneyWithCurrency(r.documentTotal??r.total,r.currency||"USD"),`USD ${money(r.balance)}`,`<span class="badge ${r.balance>0?"warn":"ok"}">${esc(r.status)}</span>`,r.balance>0?`<button class="btn btn-soft" data-pay-ap="${r.id}">Pagar</button>`:""
 ]))}
 <div style="height:18px"></div>
 <div class="card"><div class="section-title"><h3>Créditos de proveedores</h3><span class="badge ${credits.length?"warn":"ok"}">${credits.length} disponible(s)</span></div>
 ${credits.length?table(["Proveedor","Origen","Fecha","Crédito original","Disponible",""],credits.map(c=>[
  esc(s.suppliers.find(x=>x.id===c.supplierId)?.name||""),esc(c.reference||""),datefmt(c.date),`USD ${money(c.amount)}`,`USD ${money(c.balance)}`,
  `<button class="btn btn-soft" data-use-supplier-credit="${c.id}">Aplicar a deuda</button>`
 ])):'<div class="notice">No hay créditos de proveedores disponibles.</div>'}</div>`;
}
function rates(){
 const s=state();
 return `<div class="hero"><div><h2>Tasas y monedas</h2><p>Histórico de tasas para operaciones multimoneda.</p></div><button class="btn btn-primary" data-add="rate">+ Nueva tasa</button></div>
 <div class="grid stats">${["USD","EUR","USDT"].map(c=>`<div class="card stat"><div class="label">${c}</div><div class="value">${money(DB.latestRate(c))}</div><div class="hint">VES por ${c}</div></div>`).join("")}</div>
 ${table(["Fecha","Moneda","Tasa VES","Fuente"],s.exchangeRates.slice().sort((a,b)=>String(b.date).localeCompare(String(a.date))).map(r=>[esc(r.date),esc(r.currency),money(r.rate),esc(r.source)]))}`;
}
function users(){
 const s=state();
 return `<div class="hero"><div><h2>Usuarios</h2><p>Accesos, PIN, rol y sucursal.</p></div><button class="btn btn-primary" data-add="user">+ Nuevo usuario</button></div>
 ${table(["Usuario","Rol","Sucursal","Estado",""],s.users.map(u=>{
  const r=s.roles.find(r=>r.id===u.roleId),b=s.branches.find(b=>b.id===u.branchId);
  return [`<strong>${esc(u.name)}</strong><br><small>${esc(u.email)}</small>`,esc(r?.name||""),esc(u.branchId==="all"?"Todas":b?.name||""),
   `<span class="badge ${(u.status||"Activo")==="Activo"?"ok":"warn"}">${esc(u.status||"Activo")}</span>`,
   `<button class="btn ${(u.status||"Activo")==="Inactivo"?"btn-soft":"btn-danger"}" data-delete="user:${u.id}">${(u.status||"Activo")==="Inactivo"?"Reactivar":"Desactivar"}</button>`];
 }))}`;
}
function roles(){
 const s=state();
 return `<div class="hero"><div><h2>Roles y permisos</h2><p>Controla exactamente qué puede ver y usar cada tipo de usuario.</p></div><button class="btn btn-primary" id="newRole">+ Nuevo rol</button></div>
 ${table(["Rol","Permisos","Usuarios",""],s.roles.map(r=>[
   `<strong>${esc(r.name)}</strong>`,
   r.permissions.includes("*")?"Todos":`${r.permissions.length} permisos`,
   s.users.filter(u=>u.roleId===r.id).length,
   `<button class="btn btn-soft" data-edit-role="${r.id}">Editar permisos</button>`
 ]))}`;
}


function stockTransfers(){
 const s=state();
 return `<div class="hero"><div><h2>Transferencias de stock</h2><p>Mueve inventario entre sucursales sin alterar el total general.</p></div><button class="btn btn-primary" id="newTransfer">+ Nueva transferencia</button></div>
 ${table(["N°","Fecha","Producto","Origen","Destino","Cantidad","Estado"],s.stockTransfers.slice().reverse().map(t=>[
  esc(t.number),datefmt(t.date),esc(s.products.find(p=>p.id===t.productId)?.name||""),esc(s.branches.find(b=>b.id===t.fromBranchId)?.name||""),esc(s.branches.find(b=>b.id===t.toBranchId)?.name||""),esc(t.qty),`<span class="badge ok">${esc(t.status)}</span>`
 ]))}`;
}
function quotations(){
 const s=state();
 return `<div class="hero"><div><h2>Cotizaciones</h2><p>Presupuestos previos a la venta, sin afectar inventario ni caja.</p></div><button class="btn btn-primary" id="newQuote">+ Nueva cotización</button></div>
 ${table(["N°","Fecha","Cliente","Total","Estado",""],s.quotations.slice().reverse().map(q=>[
  esc(q.number),datefmt(q.date),esc(s.customers.find(c=>c.id===q.customerId)?.name||""),`$ ${money(q.total)}`,`<span class="badge ${q.status==="Convertida"?"ok":"warn"}">${esc(q.status)}</span>`,q.status!=="Convertida"?`<button class="btn btn-soft" data-quote-sale="${q.id}">Convertir en venta</button>`:""
 ]))}`;
}
function returns(){
 const s=state();
 return `<div class="hero"><div><h2>Devoluciones</h2><p>Reintegros de ventas con devolución automática al inventario.</p></div><button class="btn btn-primary" id="newReturn">+ Registrar devolución</button></div>
 ${table(["N°","Fecha","Venta","Producto","Cantidad","Monto","Estado"],s.returns.slice().reverse().map(r=>[
  esc(r.number),datefmt(r.date),esc(r.saleNumber),esc(s.products.find(p=>p.id===r.productId)?.name||""),esc(r.qty),`$ ${money(r.amount)}`,`<span class="badge ok">${esc(r.status)}</span>`
 ]))}`;
}
function expenses(){
 const s=state(),total=s.expenses.reduce((a,x)=>a+Number(x.amount||0),0);
 return `<div class="hero"><div><h2>Gastos</h2><p>Registra egresos y contabilízalos automáticamente.</p></div><button class="btn btn-primary" id="newExpense">+ Nuevo gasto</button></div>
 <div class="grid stats"><div class="card stat"><div class="label">Gastos acumulados</div><div class="value">$ ${money(total)}</div><div class="hint">${s.expenses.length} registros</div></div></div>
 ${table(["Fecha","Categoría","Descripción","Cuenta","Monto","Referencia"],s.expenses.slice().reverse().map(x=>[
  datefmt(x.date),esc(x.category),esc(x.description),esc(s.cashAccounts.find(a=>a.id===x.accountId)?.name||""),`$ ${money(x.amount)}`,esc(x.reference)
 ]))}`;
}
function paymentMethods(){
 const s=state();
 return `<div class="hero"><div><h2>Métodos de pago</h2><p>Opciones disponibles para cobros y pagos.</p></div><button class="btn btn-primary" id="newPaymentMethod">+ Nuevo método</button></div>
 ${table(["Nombre","Tipo","Estado",""],s.paymentMethods.map(m=>[
  `<strong>${esc(m.name)}</strong>`,esc(m.type),`<span class="badge ${m.active?"ok":"warn"}">${m.active?"Activo":"Inactivo"}</span>`,`<button class="btn btn-soft" data-toggle-pm="${m.id}">${m.active?"Desactivar":"Activar"}</button>`
 ]))}`;
}
function settings(){
 const s=state(),x=s.settings;
 return `<div class="hero"><div><h2>Configuración</h2><p>Reglas generales de operación de ATLAS.</p></div></div>
 <div class="card"><form id="settingsForm" class="form-grid">
  <div class="field"><label>Días de crédito por defecto</label><input name="defaultCreditDays" type="number" min="0" value="${esc(x.defaultCreditDays)}"></div>
  <div class="field"><label>Alertas de stock bajo</label><select name="lowStockAlerts"><option value="true" ${x.lowStockAlerts?"selected":""}>Activadas</option><option value="false" ${!x.lowStockAlerts?"selected":""}>Desactivadas</option></select></div>
  <div class="field"><label>Permitir stock negativo</label><select name="allowNegativeStock"><option value="false" ${!x.allowNegativeStock?"selected":""}>No</option><option value="true" ${x.allowNegativeStock?"selected":""}>Sí</option></select></div>
  <div class="field"><label>Impuestos incluidos en precio</label><select name="invoiceTaxIncluded"><option value="false" ${!x.invoiceTaxIncluded?"selected":""}>No</option><option value="true" ${x.invoiceTaxIncluded?"selected":""}>Sí</option></select></div>
  <div></div><div><button class="btn btn-primary">Guardar configuración</button></div>
 </form></div>`;
}
function backup(){
 return `<div class="hero"><div><h2>Respaldo</h2><p>Copia y restauración completa de los datos locales.</p></div></div>
 <div class="grid two">
  <div class="card"><div class="section-title"><h3>Crear respaldo</h3></div><p style="color:#667085">Descarga un archivo JSON con los datos actuales de ATLAS.</p><button class="btn btn-primary" id="downloadBackup">Descargar respaldo</button></div>
  <div class="card"><div class="section-title"><h3>Restaurar respaldo</h3></div><p style="color:#667085">Selecciona un respaldo generado por ATLAS.</p><input id="backupFile" type="file" accept=".json,application/json"><div style="margin-top:12px"><button class="btn btn-soft" id="restoreBackup">Restaurar</button></div></div>
 </div>`;
}


function system(){
 const s=state();
 const configured=isSupabaseConfigured();
 return `<div class="hero"><div><h2>Sistema y nube</h2><p>Estado de la arquitectura, seguridad y conexión multiusuario.</p></div><div style="display:flex;gap:8px;flex-wrap:wrap"><button class="btn btn-soft" id="syncCore">Sincronizar maestros</button><button class="btn btn-soft" id="syncTransactions">Sincronizar operaciones</button><button class="btn btn-primary" id="testCloud">Probar conexión</button></div></div>
 <div class="grid two">
  <div class="card">
   <div class="section-title"><h3>Modo actual</h3><span class="badge ${configured?"ok":"warn"}">${configured?"Supabase":"Local"}</span></div>
   <div class="list">
    <div class="list-item"><strong>Frontend</strong><span>GitHub Pages / PWA</span></div>
    <div class="list-item"><strong>Base de datos</strong><span>${configured?"PostgreSQL / Supabase":"LocalStorage demo"}</span></div>
    <div class="list-item"><strong>Autenticación</strong><span>${configured?"Supabase Auth":"PIN local demo"}</span></div>
    <div class="list-item"><strong>RLS</strong><span>${configured?"Activo / preparado":"No aplica local"}</span></div>
    <div class="list-item"><strong>Operaciones remotas</strong><span>${configured?"Ventas · Compras · CxC · CxP · Stock · Gastos":"En espera de Supabase"}</span></div>
    <div class="list-item"><strong>Permisos</strong><span>Por rol y sucursal</span></div>
   </div>
  </div>
  <div class="card">
   <div class="section-title"><h3>Sincronización</h3></div>
   <div class="metric-mini"><small>Estado</small><strong>${esc(s.sync.status||"local")}</strong></div>
   <div class="metric-mini" style="margin-top:10px"><small>Última sincronización</small><strong style="font-size:15px">${s.sync.lastSync?datefmt(s.sync.lastSync):"Aún no"}</strong></div>
   <div class="metric-mini" style="margin-top:10px"><small>Pendientes locales</small><strong>${Number(s.sync.pending||0)}</strong></div>
   ${s.sync.lastError?`<div class="notice" style="margin-top:10px">${esc(s.sync.lastError)}</div>`:""}
  </div>
 </div>
 <div class="card" style="margin-top:15px">
  <div class="section-title"><h3>Activar Supabase</h3></div>
  <p style="color:#667085">Para activar la nube solo se colocan la URL pública del proyecto y la clave <strong>anon</strong> en <code>assets/config.js</code>, y se cambia <code>mode</code> a <code>supabase</code>. Nunca se debe colocar una clave <code>service_role</code> en el navegador.</p>
  <div class="notice">La Fase 6 incluye el SQL de seguridad, funciones RLS, perfiles, acceso por sucursal y las funciones de diagnóstico para conectar el proyecto real cuando tengas Supabase.</div>
 </div>`;
}


function accountByName(name){return state().chartOfAccounts.find(a=>a.name===name)?.id}
function accountTotals(){
 const s=state(),totals={};
 s.chartOfAccounts.forEach(a=>totals[a.id]={debit:0,credit:0,balance:0});
 s.journalEntries.forEach(e=>(e.lines||[]).forEach(l=>{
  if(!totals[l.accountId])return;
  totals[l.accountId].debit+=Number(l.debit||0);
  totals[l.accountId].credit+=Number(l.credit||0);
 }));
 s.chartOfAccounts.forEach(a=>{
  const t=totals[a.id],normalDebit=["Activo","Costo","Gasto"].includes(a.type);
  t.balance=normalDebit?t.debit-t.credit:t.credit-t.debit;
 });
 return totals;
}
function ledgerRows(){
 const s=state(),rows=[];
 for(const e of s.journalEntries){
  for(const l of (e.lines||[])){
   const a=s.chartOfAccounts.find(x=>x.id===l.accountId);
   rows.push({date:e.date,reference:e.reference,description:e.description,code:a?.code||"",account:a?.name||"",debit:Number(l.debit||0),credit:Number(l.credit||0)});
  }
 }
 return rows.sort((a,b)=>String(b.date).localeCompare(String(a.date)));
}
function accountingSummary(){
 const s=state(),t=accountTotals();
 const by=n=>{const a=s.chartOfAccounts.find(x=>x.name===n);return a?t[a.id]?.balance||0:0};
 return {
  cash:by("Caja y bancos"),ar:by("Cuentas por cobrar"),inventory:by("Inventario"),
  ap:by("Cuentas por pagar"),sales:by("Ventas"),cogs:by("Costo de ventas"),
  expenses:by("Compras / Gastos"),vatPay:by("IVA por pagar"),vatCredit:by("IVA crédito fiscal")
 };
}

function accounting(){
 const s=state(),totals=accountTotals(),sum=accountingSummary(),ledger=ledgerRows();
 const debitTotal=Object.values(totals).reduce((a,x)=>a+x.debit,0),creditTotal=Object.values(totals).reduce((a,x)=>a+x.credit,0);
 const netIncome=sum.sales-sum.cogs-sum.expenses;
 const vatNet=sum.vatPay-sum.vatCredit;
 return `<div class="hero"><div><h2>Contabilidad</h2><p>Libro diario, mayor, balance de comprobación, resultado e IVA.</p></div><div style="display:flex;gap:8px;flex-wrap:wrap"><button class="btn btn-soft" id="syncAccounting">Sincronizar contabilidad</button><button class="btn btn-primary" id="manualJournal">+ Asiento manual</button></div></div>
 <div class="kpi-row">
  <div class="card stat"><div class="label">Ventas</div><div class="value">$ ${money(sum.sales)}</div></div>
  <div class="card stat"><div class="label">Costo de ventas</div><div class="value">$ ${money(sum.cogs)}</div></div>
  <div class="card stat"><div class="label">Resultado</div><div class="value">$ ${money(netIncome)}</div></div>
  <div class="card stat"><div class="label">IVA neto</div><div class="value">$ ${money(vatNet)}</div></div>
 </div>
 <div class="grid two">
  <div class="card"><div class="section-title"><h3>Balance de comprobación</h3><span class="badge ${Math.abs(debitTotal-creditTotal)<.01?"ok":"warn"}">${Math.abs(debitTotal-creditTotal)<.01?"Cuadrado":"Revisar"}</span></div>
   ${table(["Código","Cuenta","Tipo","Débitos","Créditos","Saldo"],s.chartOfAccounts.map(a=>[
     esc(a.code),`<strong>${esc(a.name)}</strong>`,esc(a.type),money(totals[a.id]?.debit||0),money(totals[a.id]?.credit||0),money(totals[a.id]?.balance||0)
   ]))}
  </div>
  <div class="card"><div class="section-title"><h3>Resumen fiscal y financiero</h3></div>
   <div class="list">
    <div class="list-item"><strong>IVA débito fiscal</strong><span>$ ${money(sum.vatPay)}</span></div>
    <div class="list-item"><strong>IVA crédito fiscal</strong><span>$ ${money(sum.vatCredit)}</span></div>
    <div class="list-item"><strong>IVA neto estimado</strong><span>$ ${money(vatNet)}</span></div>
    <div class="list-item"><strong>Cuentas por cobrar</strong><span>$ ${money(sum.ar)}</span></div>
    <div class="list-item"><strong>Cuentas por pagar</strong><span>$ ${money(sum.ap)}</span></div>
    <div class="list-item"><strong>Inventario contable</strong><span>$ ${money(sum.inventory)}</span></div>
   </div>
  </div>
 </div>
 <div style="height:15px"></div>
 <div class="card"><div class="section-title"><h3>Libro diario</h3><span>${s.journalEntries.length} asientos</span></div>
 ${table(["Fecha","Referencia","Descripción","Débito","Crédito","Estado"],s.journalEntries.map(e=>{
   const d=(e.lines||[]).reduce((a,l)=>a+Number(l.debit||0),0),c=(e.lines||[]).reduce((a,l)=>a+Number(l.credit||0),0);
   return [datefmt(e.date),esc(e.reference),esc(e.description),money(d),money(c),`<span class="badge ${Math.abs(d-c)<.01?"ok":"warn"}">${Math.abs(d-c)<.01?"Cuadrado":"Revisar"}</span>`]
 }))}</div>
 <div style="height:15px"></div>
 <div class="card"><div class="section-title"><h3>Libro mayor</h3><span>${ledger.length} movimientos</span></div>
 ${table(["Fecha","Cuenta","Referencia","Descripción","Debe","Haber"],ledger.map(r=>[
  datefmt(r.date),`${esc(r.code)} · ${esc(r.account)}`,esc(r.reference),esc(r.description),money(r.debit),money(r.credit)
 ]))}</div>`;
}

function reportDateValue(v){return new Date(v||0).getTime()||0}
function inRange(v,from,to){
 const t=reportDateValue(v);
 const a=from?new Date(from+"T00:00:00").getTime():-Infinity;
 const b=to?new Date(to+"T23:59:59").getTime():Infinity;
 return t>=a&&t<=b;
}
function defaultReportRange(){
 const now=new Date(),from=new Date(now.getFullYear(),now.getMonth(),1);
 return {from:from.toISOString().slice(0,10),to:now.toISOString().slice(0,10)};
}
function reportMetrics(from,to){
 const s=state();
 const sales=(s.sales||[]).filter(x=>x.status!=="Anulada"&&inRange(x.date,from,to));
 const purchases=(s.purchases||[]).filter(x=>x.status!=="Anulada"&&inRange(x.date,from,to));
 const expenses=(s.expenses||[]).filter(x=>x.status!=="Anulada"&&inRange(x.date,from,to));
 const saleReturns=(s.returns||[]).filter(x=>x.status!=="Anulada"&&inRange(x.date,from,to));
 const purchaseReturns=(s.purchaseReturns||[]).filter(x=>x.status!=="Anulada"&&inRange(x.date,from,to));
 const salesGross=sales.reduce((a,x)=>a+Number(x.baseTotalUSD??x.total||0),0);
 const returnsSales=saleReturns.reduce((a,x)=>a+Number(x.amount||0),0);
 const netSales=safeMoney(salesGross-returnsSales);
 const purchasesGross=purchases.reduce((a,x)=>a+Number(x.baseTotalUSD??x.total||0),0);
 const returnsPurchases=purchaseReturns.reduce((a,x)=>a+Number(x.amount||0),0);
 const netPurchases=safeMoney(purchasesGross-returnsPurchases);
 const expenseTotal=expenses.reduce((a,x)=>a+Number(x.amount||0),0);
 let cogs=0;
 for(const sale of sales){
  for(const item of sale.items||[])cogs+=Number(item.cost??s.products.find(p=>p.id===item.productId)?.cost||0)*Number(item.qty||0);
 }
 for(const ret of saleReturns)cogs-=Number(ret.cost||0);
 cogs=safeMoney(Math.max(0,cogs));
 const grossProfit=safeMoney(netSales-cogs);
 const netProfit=safeMoney(grossProfit-expenseTotal);
 const ar=(s.receivables||[]).reduce((a,x)=>a+Number(x.balance||0),0);
 const ap=(s.payables||[]).reduce((a,x)=>a+Number(x.balance||0),0);
 let inventoryValue=0;
 for(const inv of s.inventory||[]){
  const p=s.products.find(x=>x.id===inv.productId);
  inventoryValue+=Number(inv.stock||0)*Number(p?.cost||0);
 }
 return {sales,purchases,expenses,saleReturns,purchaseReturns,salesGross,returnsSales,netSales,purchasesGross,returnsPurchases,netPurchases,expenseTotal,cogs,grossProfit,netProfit,ar,ap,inventoryValue};
}
function groupedSalesByBranch(rows){
 const s=state(),map=new Map();
 for(const x of rows){
  const name=s.branches.find(b=>b.id===x.branchId)?.name||"Sin sucursal";
  map.set(name,(map.get(name)||0)+Number(x.baseTotalUSD??x.total||0));
 }
 return [...map.entries()].sort((a,b)=>b[1]-a[1]);
}
function topProductsReport(rows){
 const s=state(),map=new Map();
 for(const sale of rows){
  for(const item of sale.items||[]){
   const cur=map.get(item.productId)||{qty:0,total:0};
   cur.qty+=Number(item.qty||0);
   cur.total+=Number(item.price||0)*Number(item.qty||0);
   map.set(item.productId,cur);
  }
 }
 return [...map.entries()].map(([id,v])=>({name:s.products.find(p=>p.id===id)?.name||id,...v})).sort((a,b)=>b.total-a.total);
}
function agedReceivables(){
 const s=state(),now=Date.now();
 return (s.receivables||[]).filter(r=>Number(r.balance||0)>0).map(r=>{
  const due=reportDateValue(r.dueDate||r.date);
  return {...r,days:Math.max(0,Math.floor((now-due)/86400000))};
 }).sort((a,b)=>b.days-a.days);
}
function inventoryValuation(){
 const s=state();
 return (s.inventory||[]).map(inv=>{
  const p=s.products.find(x=>x.id===inv.productId);
  const cost=Number(p?.cost||0),stock=Number(inv.stock||0);
  return {product:p?.name||inv.productId,branch:s.branches.find(b=>b.id===inv.branchId)?.name||"",stock,cost,value:safeMoney(stock*cost)};
 }).sort((a,b)=>b.value-a.value);
}
function reportCSV(){
 const r=defaultReportRange(),m=reportMetrics(r.from,r.to);
 const rows=[["Métrica","USD"],["Ventas netas",m.netSales],["Costo de ventas",m.cogs],["Utilidad bruta",m.grossProfit],["Gastos",m.expenseTotal],["Utilidad estimada",m.netProfit],["CxC",m.ar],["CxP",m.ap],["Inventario valorizado",m.inventoryValue]];
 const csv=rows.map(row=>row.map(v=>`"${String(v).replaceAll('"','""')}"`).join(",")).join("\n");
 const blob=new Blob([csv],{type:"text/csv;charset=utf-8"});
 const a=document.createElement("a");a.href=URL.createObjectURL(blob);a.download=`ATLAS-reporte-${r.to}.csv`;a.click();URL.revokeObjectURL(a.href);
}


function documentCompanyBlock(){
 const s=state(),c=s.company||{},cfg=s.settings.documentTemplates||{};
 return `<div class="doc-company"><div><div class="doc-brand">ATLAS</div><div class="doc-company-name">${esc(c.name||"Empresa")}</div></div><div class="doc-company-meta">${cfg.showTaxId&&c.taxId?`<div>${esc(fiscalConfig().taxIdLabel||"RIF")}: ${esc(c.taxId)}</div>`:""}${cfg.showAddress&&c.address?`<div>${esc(c.address)}</div>`:""}${c.phone?`<div>${esc(c.phone)}</div>`:""}${c.email?`<div>${esc(c.email)}</div>`:""}</div></div>`;
}
function documentFooter(){const cfg=state().settings.documentTemplates||{};return cfg.showFooter?`<div class="doc-footer">${esc(cfg.footerText||"Gracias por su preferencia.")}<br><small>Generado por ATLAS · Sistema de Gestión Empresarial</small></div>`:""}
function docPrint(title,html){
 const w=window.open("","_blank","width=900,height=1100");if(!w)return alert("El navegador bloqueó la ventana de impresión.");
 w.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title><style>*{box-sizing:border-box}body{font-family:Arial,Helvetica,sans-serif;margin:0;background:#f4f6f8;color:#172033}.sheet{max-width:820px;margin:24px auto;background:#fff;padding:34px;box-shadow:0 4px 20px #0001}.doc-company{display:flex;justify-content:space-between;gap:20px;border-bottom:2px solid #1f4fd1;padding-bottom:18px;margin-bottom:24px}.doc-brand{font-size:12px;font-weight:800;letter-spacing:3px;color:#1f4fd1}.doc-company-name{font-size:22px;font-weight:800;margin-top:4px}.doc-company-meta{text-align:right;font-size:12px;line-height:1.5;color:#566070}.doc-title{display:flex;justify-content:space-between;gap:20px;align-items:flex-start;margin-bottom:22px}.doc-title h1{font-size:24px;margin:0}.doc-meta{font-size:12px;line-height:1.6;text-align:right}.doc-party{border:1px solid #dce2ea;border-radius:8px;padding:14px;margin-bottom:18px}table{width:100%;border-collapse:collapse;font-size:12px}th{background:#f2f5f9;text-align:left;padding:9px;border-bottom:1px solid #dce2ea}td{padding:9px;border-bottom:1px solid #edf0f4}.num{text-align:right}.totals{margin-left:auto;width:320px;margin-top:18px}.totals div{display:flex;justify-content:space-between;padding:5px 0}.totals .grand{font-size:18px;font-weight:800;border-top:2px solid #172033;margin-top:5px;padding-top:10px}.doc-note{margin-top:20px;padding:12px;background:#f7f9fb;border-radius:8px;font-size:12px}.doc-footer{text-align:center;margin-top:34px;border-top:1px solid #dce2ea;padding-top:16px;font-size:12px;color:#657080}.badge{display:inline-block;padding:4px 8px;border-radius:999px;background:#eef3ff;color:#1f4fd1;font-weight:700}@media print{body{background:#fff}.sheet{box-shadow:none;margin:0;max-width:none;padding:18mm}}</style></head><body><div class="sheet">${html}</div><script>window.onload=()=>setTimeout(()=>window.print(),250)</script></body></html>`);w.document.close();
}
function saleDocumentHTML(sale){
 const s=state(),customer=s.customers.find(c=>c.id===sale.customerId),branch=s.branches.find(b=>b.id===sale.branchId);
 const rows=(sale.items||[]).map(i=>{const p=s.products.find(x=>x.id===i.productId),line=Number(i.price||0)*Number(i.qty||0);return `<tr><td>${esc(p?.name||i.productId)}</td><td class="num">${money(i.qty)}</td><td class="num">USD ${money(i.price)}</td><td class="num">USD ${money(line)}</td></tr>`}).join("");
 return `${documentCompanyBlock()}<div class="doc-title"><div><h1>FACTURA / VENTA</h1><span class="badge">${esc(sale.status||"Completada")}</span></div><div class="doc-meta"><strong>${esc(sale.number)}</strong><br>${datefmt(sale.date)}<br>${esc(branch?.name||"")}</div></div><div class="doc-party"><strong>Cliente:</strong> ${esc(customer?.name||"Consumidor final")}${customer?.taxId?`<br><strong>${esc(fiscalConfig().taxIdLabel||"RIF")}:</strong> ${esc(customer.taxId)}`:""}${customer?.phone?`<br><strong>Tel.:</strong> ${esc(customer.phone)}`:""}</div><table><thead><tr><th>Producto</th><th class="num">Cant.</th><th class="num">Precio</th><th class="num">Total</th></tr></thead><tbody>${rows}</tbody></table><div class="totals"><div><span>Subtotal</span><strong>USD ${money(sale.subtotal||0)}</strong></div><div><span>Impuestos</span><strong>USD ${money(sale.tax||0)}</strong></div><div class="grand"><span>Total</span><strong>${moneyWithCurrency(sale.documentTotal??sale.total,sale.currency||"USD")}</strong></div></div><div class="doc-note"><strong>Condición:</strong> ${(sale.condition||sale.paymentCondition)==="credit"?"Crédito":"Contado"}</div>${documentFooter()}`;
}
function quotationDocumentHTML(q){
 const s=state(),customer=s.customers.find(c=>c.id===q.customerId);const rows=(q.items||[]).map(i=>{const p=s.products.find(x=>x.id===i.productId),line=Number(i.price||0)*Number(i.qty||0);return `<tr><td>${esc(p?.name||i.productId)}</td><td class="num">${money(i.qty)}</td><td class="num">USD ${money(i.price)}</td><td class="num">USD ${money(line)}</td></tr>`}).join("");
 return `${documentCompanyBlock()}<div class="doc-title"><div><h1>COTIZACIÓN</h1><span class="badge">${esc(q.status||"Vigente")}</span></div><div class="doc-meta"><strong>${esc(q.number)}</strong><br>${datefmt(q.date)}</div></div><div class="doc-party"><strong>Cliente:</strong> ${esc(customer?.name||"")}</div><table><thead><tr><th>Producto</th><th class="num">Cant.</th><th class="num">Precio</th><th class="num">Total</th></tr></thead><tbody>${rows}</tbody></table><div class="totals"><div><span>Subtotal</span><strong>USD ${money(q.subtotal||0)}</strong></div><div><span>Impuestos</span><strong>USD ${money(q.tax||0)}</strong></div><div class="grand"><span>Total</span><strong>USD ${money(q.total||0)}</strong></div></div><div class="doc-note">Esta cotización no representa una factura hasta ser convertida en venta.</div>${documentFooter()}`;
}
function cashReceiptHTML(m,typeLabel){const s=state(),acc=s.cashAccounts.find(a=>a.id===m.accountId),pm=s.paymentMethods.find(p=>p.id===m.paymentMethodId);return `${documentCompanyBlock()}<div class="doc-title"><div><h1>${esc(typeLabel)}</h1><span class="badge">${m.type==="IN"?"INGRESO":"EGRESO"}</span></div><div class="doc-meta"><strong>${esc(m.reference||"")}</strong><br>${datefmt(m.date)}</div></div><div class="doc-party"><strong>Cuenta:</strong> ${esc(acc?.name||"")} · ${esc(acc?.currency||m.currency||"")}<br><strong>Método:</strong> ${esc(pm?.name||"No especificado")}</div><div class="totals"><div class="grand"><span>Monto</span><strong>${moneyWithCurrency(m.amount,m.currency||acc?.currency||"USD")}</strong></div></div><div class="doc-note">${esc(m.note||"")}</div>${documentFooter()}`}
function returnDocumentHTML(r,isPurchase=false){const s=state(),party=isPurchase?s.suppliers.find(x=>x.id===r.supplierId):s.customers.find(x=>x.id===s.sales.find(v=>v.id===r.saleId)?.customerId),product=s.products.find(p=>p.id===r.productId);return `${documentCompanyBlock()}<div class="doc-title"><div><h1>${isPurchase?"DEVOLUCIÓN DE COMPRA":"DEVOLUCIÓN DE VENTA"}</h1><span class="badge">${esc(r.status||"Completada")}</span></div><div class="doc-meta"><strong>${esc(r.number)}</strong><br>${datefmt(r.date)}</div></div><div class="doc-party"><strong>${isPurchase?"Proveedor":"Cliente"}:</strong> ${esc(party?.name||"")}<br><strong>Documento origen:</strong> ${esc(isPurchase?r.purchaseNumber:r.saleNumber)}</div><table><thead><tr><th>Producto</th><th class="num">Cantidad</th><th class="num">Base USD</th></tr></thead><tbody><tr><td>${esc(product?.name||r.productId)}</td><td class="num">${money(r.qty)}</td><td class="num">USD ${money(r.amount)}</td></tr></tbody></table>${r.refundAmount?`<div class="doc-note"><strong>Reembolso:</strong> ${moneyWithCurrency(r.refundAmount,r.refundCurrency||"USD")}</div>`:""}${documentFooter()}`}

function reports(){
 const s=state(),range=defaultReportRange(),m=reportMetrics(range.from,range.to);
 const top=topProductsReport(m.sales).slice(0,8),branches=groupedSalesByBranch(m.sales).slice(0,8),aged=agedReceivables().slice(0,10),inv=inventoryValuation();
 const low=(s.inventory||[]).filter(i=>Number(i.stock||0)<=Number(s.settings.reporting?.lowStockThreshold||5));
 const stale=aged.filter(r=>r.days>Number(s.settings.reporting?.staleReceivableDays||30)).length;
 const cashDiff=(s.cashClosings||[]).filter(c=>c.status==="Con diferencia").length;
 const alerts=[...(low.length?[`${low.length} producto(s) con stock bajo`]:[]),...(stale?[`${stale} cuenta(s) por cobrar vencidas`]:[]),...(cashDiff?[`${cashDiff} cierre(s) de caja con diferencia`]:[])];
 return `<div class="hero"><div><h2>Reportes y control gerencial</h2><p>Resumen ejecutivo del negocio para tomar decisiones rápidas.</p></div>
 <div class="hero-actions"><button class="btn btn-soft" id="exportReportCSV">Exportar CSV</button><button class="btn btn-primary" id="printManagerReport">Imprimir / PDF</button></div></div>
 <div class="notice">Período actual: <strong>${range.from}</strong> al <strong>${range.to}</strong>.</div>
 <div class="grid stats">
  <div class="card stat"><div class="label">Ventas netas</div><div class="value">USD ${money(m.netSales)}</div><div class="hint">Después de devoluciones</div></div>
  <div class="card stat"><div class="label">Utilidad bruta</div><div class="value">USD ${money(m.grossProfit)}</div><div class="hint">Ventas menos costo</div></div>
  <div class="card stat"><div class="label">Gastos</div><div class="value">USD ${money(m.expenseTotal)}</div><div class="hint">Período actual</div></div>
  <div class="card stat"><div class="label">Utilidad estimada</div><div class="value">USD ${money(m.netProfit)}</div><div class="hint">Bruta menos gastos</div></div>
  <div class="card stat"><div class="label">Inventario valorizado</div><div class="value">USD ${money(m.inventoryValue)}</div><div class="hint">Stock × costo</div></div>
  <div class="card stat"><div class="label">CxC / CxP</div><div class="value">USD ${money(m.ar)} / ${money(m.ap)}</div><div class="hint">Saldos actuales</div></div>
 </div>
 <div class="grid two">
  <div class="card"><div class="section-title"><h3>Productos más vendidos</h3></div>${top.length?table(["Producto","Cantidad","Ventas USD"],top.map(x=>[esc(x.name),money(x.qty),money(x.total)])):'<div class="notice">Sin ventas en el período.</div>'}</div>
  <div class="card"><div class="section-title"><h3>Ventas por sucursal</h3></div>${branches.length?table(["Sucursal","Ventas USD"],branches.map(([name,total])=>[esc(name),money(total)])):'<div class="notice">Sin ventas por sucursal.</div>'}</div>
 </div>
 <div style="height:16px"></div>
 <div class="grid two">
  <div class="card"><div class="section-title"><h3>Cuentas por cobrar vencidas</h3></div>${aged.length?table(["Documento","Cliente","Saldo USD","Días vencida"],aged.map(r=>[esc(r.reference),esc(s.customers.find(c=>c.id===r.customerId)?.name||""),money(r.balance),String(r.days)])):'<div class="notice">No hay cuentas pendientes.</div>'}</div>
  <div class="card"><div class="section-title"><h3>Alertas importantes</h3></div>${alerts.length?alerts.map(a=>`<div class="notice">${esc(a)}</div>`).join(""):'<div class="notice">No hay alertas críticas.</div>'}</div>
 </div>
 <div style="height:16px"></div>
 <div class="card"><div class="section-title"><h3>Inventario valorizado</h3><span class="badge">${inv.length} líneas</span></div>${inv.length?table(["Producto","Sucursal","Stock","Costo USD","Valor USD"],inv.slice(0,30).map(x=>[esc(x.product),esc(x.branch),money(x.stock),money(x.cost),money(x.value)])):'<div class="notice">Inventario vacío.</div>'}</div>`;
}
function audit(){
 const s=state();
 return `<div class="hero"><div><h2>Auditoría</h2><p>Quién hizo qué y cuándo dentro de ATLAS.</p></div></div>
 ${table(["Fecha","Usuario","Acción","Módulo","Detalle"],s.auditLog.map(a=>[
   datefmt(a.date),esc(s.users.find(u=>u.id===a.userId)?.name||"Sistema"),esc(a.action),esc(a.entity),esc(a.detail)
 ]))}`;
}
function documents(){
 const s=state(),sales=s.sales.slice().reverse().slice(0,20),quotes=(s.quotations||[]).slice().reverse().slice(0,20),cashMoves=(s.cashMovements||[]).slice(0,20),rets=(s.returns||[]).slice(0,20),prets=(s.purchaseReturns||[]).slice(0,20);
 const allReturns=[...rets.map(r=>({...r,_type:"sale"})),...prets.map(r=>({...r,_type:"purchase"}))].sort((a,b)=>reportDateValue(b.date)-reportDateValue(a.date)).slice(0,20);
 return `<div class="hero"><div><h2>Documentos</h2><p>Facturas, cotizaciones, comprobantes y devoluciones listos para imprimir.</p></div><div class="hero-actions"><button class="btn btn-soft" id="documentSettingsBtn">Formato</button></div></div><div class="grid two"><div class="card"><div class="section-title"><h3>Ventas / Facturas</h3></div>${sales.length?table(["N°","Fecha","Cliente","Total",""],sales.map(v=>[esc(v.number),datefmt(v.date),esc(s.customers.find(c=>c.id===v.customerId)?.name||""),moneyWithCurrency(v.documentTotal??v.total,v.currency||"USD"),`<button class="btn btn-soft" data-print-sale="${v.id}">Imprimir</button>`])):'<div class="notice">No hay ventas.</div>'}</div><div class="card"><div class="section-title"><h3>Cotizaciones</h3></div>${quotes.length?table(["N°","Fecha","Cliente","Total",""],quotes.map(q=>[esc(q.number),datefmt(q.date),esc(s.customers.find(c=>c.id===q.customerId)?.name||""),`USD ${money(q.total||0)}`,`<button class="btn btn-soft" data-print-quote="${q.id}">Imprimir</button>`])):'<div class="notice">No hay cotizaciones.</div>'}</div></div><div style="height:16px"></div><div class="grid two"><div class="card"><div class="section-title"><h3>Comprobantes de caja</h3></div>${cashMoves.length?table(["Fecha","Referencia","Tipo","Monto",""],cashMoves.map(m=>[datefmt(m.date),esc(m.reference||""),m.type==="IN"?"Ingreso":"Egreso",moneyWithCurrency(m.amount,m.currency||"USD"),`<button class="btn btn-soft" data-print-cash="${m.id}">Imprimir</button>`])):'<div class="notice">No hay movimientos de caja.</div>'}</div><div class="card"><div class="section-title"><h3>Devoluciones</h3></div>${allReturns.length?table(["Fecha","N°","Tipo","Monto",""],allReturns.map(r=>[datefmt(r.date),esc(r.number),r._type==="purchase"?"Compra":"Venta",`USD ${money(r.amount||0)}`,`<button class="btn btn-soft" data-print-return="${r.id}" data-return-type="${r._type}">Imprimir</button>`])):'<div class="notice">No hay devoluciones.</div>'}</div></div>`;
}
function render(){document.getElementById("app").innerHTML=state().session.loggedIn?shell(page()):loginView();bind()}

let atlasLastActivity=Date.now();
["click","keydown","touchstart"].forEach(evt=>document.addEventListener(evt,()=>{atlasLastActivity=Date.now()},{passive:true}));
setInterval(async()=>{
 const s=state();if(!s.session?.loggedIn)return;
 const mins=Number(s.settings.securityPolicy?.sessionTimeoutMinutes||30);
 if(Date.now()-atlasLastActivity>mins*60000){
  try{if(isSupabaseConfigured())await remoteLogout()}catch{}
  DB.logout();alert("La sesión se cerró por inactividad.");render();
 }
},60000);

function modal(title,body,onSave){
 const bg=document.createElement("div");bg.className="modal-bg";bg.innerHTML=`<div class="modal"><h3>${title}</h3><form id="modalForm">${body}<div class="modal-actions"><button type="button" class="btn btn-soft" id="cancelModal">Cancelar</button><button class="btn btn-primary">Guardar</button></div></form></div>`;
 document.body.appendChild(bg);document.getElementById("cancelModal").onclick=()=>bg.remove();document.getElementById("modalForm").onsubmit=async e=>{e.preventDefault();try{await onSave(new FormData(e.target));bg.remove();render()}catch(err){alert(err.message||"No se pudo completar la operación")}};
}

function editDocumentSettings(){const s=state(),cfg=s.settings.documentTemplates||{};modal("Formato de documentos",`<div class="field"><label>Texto de pie</label><input name="footerText" value="${esc(cfg.footerText||"Gracias por su preferencia.")}"></div><div class="field"><label>Tamaño de papel</label><select name="paperSize"><option value="A4" ${cfg.paperSize==="A4"?"selected":""}>A4</option><option value="Letter" ${cfg.paperSize==="Letter"?"selected":""}>Carta</option></select></div><label class="check"><input type="checkbox" name="showAddress" ${cfg.showAddress!==false?"checked":""}> Mostrar dirección</label><label class="check"><input type="checkbox" name="showTaxId" ${cfg.showTaxId!==false?"checked":""}> Mostrar RIF / identificación</label><label class="check"><input type="checkbox" name="showFooter" ${cfg.showFooter!==false?"checked":""}> Mostrar pie de documento</label>`,f=>{cfg.footerText=String(f.get("footerText")||"").trim()||"Gracias por su preferencia.";cfg.paperSize=f.get("paperSize")||"A4";cfg.showAddress=f.get("showAddress")==="on";cfg.showTaxId=f.get("showTaxId")==="on";cfg.showFooter=f.get("showFooter")==="on";DB.log("Formato de documentos actualizado","UPDATE","document_settings");DB.save()})}

function bind(){
 const lf=document.getElementById("loginForm");if(lf)lf.onsubmit=async e=>{e.preventDefault();const f=new FormData(lf);try{
   if(isSupabaseConfigured()){
     await remoteLogin(f.get("email"),f.get("pin"));
     const profile=await getRemoteProfile();
     if(!profile)throw new Error("Tu usuario no tiene perfil de ATLAS.");
     DB.setRemoteSession(profile);
   }else{
     if(!DB.login(f.get("email"),f.get("pin")))return alert("Correo o PIN incorrecto");
   }
   render();
 }catch(err){alert("No se pudo iniciar sesión: "+err.message)}};
 const lo=document.getElementById("logout");if(lo)lo.onclick=async()=>{try{if(isSupabaseConfigured())await remoteLogout()}catch{}DB.logout();render()};
 const mt=document.getElementById("menuToggle");if(mt)mt.onclick=()=>document.getElementById("sidebar").classList.toggle("open");
 document.querySelectorAll("[data-nav]").forEach(b=>b.onclick=()=>{current=b.dataset.nav;render()});
 const cf=document.getElementById("companyForm");if(cf)cf.onsubmit=e=>{e.preventDefault();const f=new FormData(cf),c=state().company;["name","taxId","phone","email","country","baseCurrency","displayCurrency"].forEach(k=>c[k]=f.get(k));DB.log("Configuración de empresa actualizada");alert("Guardado");render()};
 const rd=document.getElementById("resetDemo");if(rd)rd.onclick=()=>{if(confirm("¿Restablecer toda la demostración?")){DB.reset();cart=[];render()}};
 document.querySelectorAll("[data-add]").forEach(b=>b.onclick=()=>openAdd(b.dataset.add));
 document.querySelectorAll("[data-delete]").forEach(b=>b.onclick=()=>deleteItem(b.dataset.delete));
 document.querySelectorAll("[data-search]").forEach(i=>i.oninput=()=>search(i.dataset.search,i.value));
 document.querySelectorAll("[data-adjust]").forEach(b=>b.onclick=()=>adjustStock(b.dataset.adjust));
 document.querySelectorAll("[data-cart-add]").forEach(b=>b.onclick=()=>addCart(b.dataset.cartAdd));
 const cc=document.getElementById("clearCart");if(cc)cc.onclick=()=>{cart=[];refreshCart()};
 const cs=document.getElementById("completeSale");if(cs)cs.onclick=completeSale;
 const np=document.getElementById("newPurchase");if(np)np.onclick=newPurchase;
 const npr=document.getElementById("newPurchaseReturn");if(npr)npr.onclick=newPurchaseReturn;
 const er=document.getElementById("exportReportCSV");if(er)er.onclick=reportCSV;
 const ds=document.getElementById("documentSettingsBtn");if(ds)ds.onclick=editDocumentSettings;
 const esp=document.getElementById("editSecurityPolicy");if(esp)esp.onclick=editSecurityPolicy;
 const efc=document.getElementById("editFiscalConfig");if(efc)efc.onclick=editFiscalConfig;
 const sb=document.getElementById("safeBackupBtn");if(sb)sb.onclick=exportSafeBackup;
 const sri=document.getElementById("safeRestoreInput");if(sri)sri.onchange=e=>restoreSafeBackup(e.target.files?.[0]);
 const emb=document.getElementById("exportMigrationBtn");if(emb)emb.onclick=exportMigrationPackage;
 const tcs=document.getElementById("testCloudSessionBtn");if(tcs)tcs.onclick=testCloudSession;
 const vca=document.getElementById("verifyCloudActivationBtn");if(vca)vca.onclick=async()=>{try{const r=await verifyCloudActivation();if(!r.ok)throw new Error(r.reason);alert("Nube verificada correctamente. El modo nube sigue inactivo hasta activarlo.");render()}catch(e){alert(e.message)}};
 const ecm=document.getElementById("enableCloudModeBtn");if(ecm)ecm.onclick=()=>{try{enableCloudMode();DB.log("Modo nube activado","CLOUD_ON","system");DB.save();alert("Modo nube activado.");render()}catch(e){alert(e.message)}};
 const dcm=document.getElementById("disableCloudModeBtn");if(dcm)dcm.onclick=()=>{disableCloudMode();DB.log("Modo nube desactivado","CLOUD_OFF","system");DB.save();alert("ATLAS volvió al modo local.");render()}; const rsl=document.getElementById("resetSecurityLock");if(rsl)rsl.onclick=()=>{try{requirePermission("settings","restablecer el bloqueo");state().settings.securityPolicy.failedAttempts=0;DB.log("Bloqueo de seguridad restablecido","UNLOCK","security");DB.save();alert("Bloqueo restablecido.");render()}catch(e){alert(e.message)}};
 const cdr=document.getElementById("cloudDryRunBtn");if(cdr)cdr.onclick=runCloudDryRun;
 const ccp=document.getElementById("cloudCompareBtn");if(ccp)ccp.onclick=compareCloudMigration;
 document.querySelectorAll("[data-print-sale]").forEach(b=>b.onclick=()=>{const x=state().sales.find(v=>v.id===b.dataset.printSale);if(x)docPrint(`Factura ${x.number}`,saleDocumentHTML(x))});
 document.querySelectorAll("[data-print-quote]").forEach(b=>b.onclick=()=>{const x=(state().quotations||[]).find(v=>v.id===b.dataset.printQuote);if(x)docPrint(`Cotización ${x.number}`,quotationDocumentHTML(x))});
 document.querySelectorAll("[data-print-cash]").forEach(b=>b.onclick=()=>{const x=(state().cashMovements||[]).find(v=>v.id===b.dataset.printCash);if(x)docPrint(`${x.type==="IN"?"Recibo de ingreso":"Comprobante de pago"} ${x.reference}`,cashReceiptHTML(x,x.type==="IN"?"RECIBO DE INGRESO":"COMPROBANTE DE PAGO"))});
 document.querySelectorAll("[data-print-return]").forEach(b=>b.onclick=()=>{const isPurchase=b.dataset.returnType==="purchase";const x=(isPurchase?state().purchaseReturns:state().returns||[]).find(v=>v.id===b.dataset.printReturn);if(x)docPrint(`${isPurchase?"Devolución de compra":"Devolución de venta"} ${x.number}`,returnDocumentHTML(x,isPurchase))});
 const pr=document.getElementById("printManagerReport");if(pr)pr.onclick=()=>window.print();
 document.querySelectorAll("[data-void-purchase]").forEach(b=>b.onclick=()=>voidPurchase(b.dataset.voidPurchase));
 document.querySelectorAll("[data-use-supplier-credit]").forEach(b=>b.onclick=()=>applySupplierCredit(b.dataset.useSupplierCredit));
 const nct=document.getElementById("newCashTransfer");if(nct)nct.onclick=newCashTransfer;
 const ncc=document.getElementById("newCashClosing");if(ncc)ncc.onclick=newCashClosing;
 document.querySelectorAll("[data-reconcile-cash]").forEach(b=>b.onclick=()=>reconcileCashClosing(b.dataset.reconcileCash));
 document.querySelectorAll("[data-pay-ar]").forEach(b=>b.onclick=()=>payReceivable(b.dataset.payAr));
 document.querySelectorAll("[data-use-credit]").forEach(b=>b.onclick=()=>applyCustomerCredit(b.dataset.useCredit));
 document.querySelectorAll("[data-void-sale]").forEach(b=>b.onclick=()=>voidSale(b.dataset.voidSale));
 document.querySelectorAll("[data-pay-ap]").forEach(b=>b.onclick=()=>payPayable(b.dataset.payAp));
 const mj=document.getElementById("manualJournal");if(mj)mj.onclick=manualJournal;
 const er=document.getElementById("exportReport");if(er)er.onclick=exportReport;
 document.querySelectorAll("[data-print-sale]").forEach(b=>b.onclick=()=>printDocument("sale",b.dataset.printSale));
 document.querySelectorAll("[data-print-purchase]").forEach(b=>b.onclick=()=>printDocument("purchase",b.dataset.printPurchase));
 const nt=document.getElementById("newTransfer");if(nt)nt.onclick=newStockTransfer;
 const nq=document.getElementById("newQuote");if(nq)nq.onclick=newQuotation;
 document.querySelectorAll("[data-quote-sale]").forEach(b=>b.onclick=()=>convertQuoteToSale(b.dataset.quoteSale));
 const nr=document.getElementById("newReturn");if(nr)nr.onclick=newReturn;
 const ne=document.getElementById("newExpense");if(ne)ne.onclick=newExpense;
 const npm=document.getElementById("newPaymentMethod");if(npm)npm.onclick=newPaymentMethod;
 document.querySelectorAll("[data-edit-role]").forEach(b=>b.onclick=()=>editRolePermissions(b.dataset.editRole));
 document.querySelectorAll("[data-toggle-pm]").forEach(b=>b.onclick=()=>togglePaymentMethod(b.dataset.togglePm));
 const sf=document.getElementById("settingsForm");if(sf)sf.onsubmit=saveSettings;
 const dbu=document.getElementById("downloadBackup");if(dbu)dbu.onclick=downloadBackup;
 const rb=document.getElementById("restoreBackup");if(rb)rb.onclick=restoreBackup;
 const tc=document.getElementById("testCloud");if(tc)tc.onclick=testCloud;
 const sc=document.getElementById("syncCore");if(sc)sc.onclick=syncCoreNow;
 const st=document.getElementById("syncTransactions");if(st)st.onclick=syncTransactionsNow;
 const sa=document.getElementById("syncAccounting");if(sa)sa.onclick=syncAccountingNow;
 bindCart();
}




function activeCashAccounts(){
 return (state().cashAccounts||[]).filter(a=>(a.status||"Activa")!=="Inactiva");
}
function currencyOptions(selected="USD"){
 return (state().supportedCurrencies||["USD","VES","EUR","USDT"]).map(c=>`<option value="${c}" ${c===selected?"selected":""}>${c}</option>`).join("");
}
function convertedPayment(baseUsdAmount,accountId){
 const acc=ensureActive(activeCashAccounts().find(a=>a.id===accountId),"Cuenta financiera");
 const amount=convertMoney(baseUsdAmount,"USD",acc.currency);
 return {account:acc,amount,rate:latestRateFor(acc.currency)||1};
}
function documentAmountsFromUSD(t,currency){
 const cur=String(currency||"USD").toUpperCase();
 return {
   currency:cur,
   subtotal:convertMoney(t.subtotal,"USD",cur),
   tax:convertMoney(t.tax,"USD",cur),
   total:convertMoney(t.total,"USD",cur),
   rate:latestRateFor(cur)||1
 };
}

function latestRateFor(currency){
 const cur=String(currency||"").toUpperCase();
 const base=String(state().settings?.baseCurrency||state().company?.baseCurrency||"VES").toUpperCase();
 if(cur===base)return 1;
 const rows=(state().exchangeRates||[]).filter(r=>String(r.currency||"").toUpperCase()===cur&&Number(r.rate)>0)
  .sort((a,b)=>String(b.date||b.effectiveAt||"").localeCompare(String(a.date||a.effectiveAt||"")));
 return rows.length?Number(rows[0].rate):null;
}
function convertMoney(amount,fromCurrency,toCurrency){
 const n=Number(amount),base=String(state().settings?.baseCurrency||state().company?.baseCurrency||"VES").toUpperCase();
 const from=String(fromCurrency||base).toUpperCase(),to=String(toCurrency||base).toUpperCase();
 if(from===to)return n;
 const fr=from===base?1:latestRateFor(from),tr=to===base?1:latestRateFor(to);
 if(!fr||!tr)throw new Error(`Falta tasa para convertir ${from} → ${to}`);
 return (n*fr)/tr;
}
function ensureAccountCurrency(accountId,currency){
 const a=(state().cashAccounts||[]).find(x=>x.id===accountId);
 if(!a)throw new Error("Cuenta financiera inexistente");
 const ac=String(a.currency||"").toUpperCase(),tx=String(currency||ac).toUpperCase();
 if(ac!==tx)throw new Error(`La cuenta ${a.name} está en ${ac}; selecciona una cuenta ${tx}.`);
 return a;
}
function moneyWithCurrency(amount,currency){return `${String(currency||"USD").toUpperCase()} ${money(amount)}`;}

function requireSelection(value,label){
 if(value===null||value===undefined||String(value).trim()==="") throw new Error(`Selecciona ${label}.`);
 return value;
}
function requirePositiveNumber(value,label){
 const n=Number(value);
 if(!Number.isFinite(n)||n<=0) throw new Error(`${label} debe ser mayor que cero.`);
 return n;
}
function requireNonNegativeNumber(value,label){
 const n=Number(value);
 if(!Number.isFinite(n)||n<0) throw new Error(`${label} no puede ser negativo.`);
 return n;
}
function localAtomic(label,work){
 try{return DB.atomic(work)}
 catch(error){console.error(`ATLAS · ${label}`,error);throw error}
}

function nextLocalDoc(kind,prefix){
 const s=state();
 if(!s.documentCounters||typeof s.documentCounters!=="object")
   s.documentCounters={sale:1,purchase:1,quote:1,return:1,expense:1};
 const n=Math.max(1,Number(s.documentCounters[kind]||1));
 s.documentCounters[kind]=n+1;
 DB.save(s);
 return `${prefix}-${String(n).padStart(5,"0")}`;
}
function activePaymentMethods(){
 return (state().paymentMethods||[]).filter(x=>x.active!==false&&x.status!=="Inactivo");
}
function reconcileReceivableForReturn(sale,amount){
 const s=state();
 if(!sale||sale.paymentCondition!=="credit") return {arReduction:0,excess:safeMoney(amount)};
 const ref=sale.number||sale.documentNumber;
 const r=(s.receivables||[]).find(x=>x.reference===ref);
 if(!r) return {arReduction:0,excess:safeMoney(amount)};
 const reduction=Math.min(Number(r.balance||0),Number(amount||0));
 r.balance=safeMoney(Number(r.balance||0)-reduction);
 r.status=r.balance<=0?"Pagada":"Parcial";
 return {arReduction:reduction,excess:safeMoney(Number(amount||0)-reduction)};
}
function addCustomerCredit(customerId,amount,reference){
 const n=safeMoney(amount);
 if(n<=0)return null;
 const s=state();
 s.customerCredits ||= [];
 const item={id:DB.id("cc"),customerId,amount:n,balance:n,reference,date:new Date().toISOString(),status:"Disponible"};
 s.customerCredits.push(item);
 return item;
}
function assertJournalBalanced(lines){
 const debit=(lines||[]).reduce((n,l)=>n+Number(l.debit||0),0);
 const credit=(lines||[]).reduce((n,l)=>n+Number(l.credit||0),0);
 if(Math.abs(debit-credit)>.009)
   throw new Error(`Asiento descuadrado: Debe ${debit.toFixed(2)} / Haber ${credit.toFixed(2)}`);
 return true;
}

function ensureActive(entity,label){
 if(!entity) throw new Error(`${label} no existe.`);
 if(entity.active===false || entity.status==="Inactivo") throw new Error(`${label} está inactivo.`);
 return entity;
}
function ensurePositive(value,label){
 const n=Number(value);
 if(!Number.isFinite(n)||n<=0) throw new Error(`${label} debe ser mayor que cero.`);
 return n;
}
function safeMoney(value){
 const n=Number(value);
 return Number.isFinite(n)?Math.round(n*100)/100:0;
}

function requiredText(value,label){
 const v=String(value??"").trim();
 if(!v)throw new Error(`${label} es obligatorio`);
 return v;
}
function nonNegative(value,label){
 const n=Number(value);
 if(!Number.isFinite(n)||n<0)throw new Error(`${label} no es válido`);
 return n;
}
function uniqueValue(arr,field,value,label){
 const v=String(value??"").trim().toLowerCase();
 if(v && arr.some(x=>String(x[field]??"").trim().toLowerCase()===v && (x.status||"Activo")!=="Inactivo"))
  throw new Error(`${label} ya existe`);
}

function openAdd(kind){
 const s=state();
 if(kind==="branch")return modal("Nueva sucursal",`${field("Nombre","name","")}${field("Ciudad","city","")}`,f=>{
   const name=requiredText(f.get("name"),"Nombre");uniqueValue(s.branches,"name",name,"Sucursal");
   const b={id:DB.id("b"),name,city:String(f.get("city")||"").trim(),status:"Activo"};s.branches.push(b);
   s.products.forEach(p=>s.inventory.push({id:DB.id("i"),productId:p.id,branchId:b.id,stock:0,reserved:0}));
   DB.log("Sucursal creada");
 });
 if(kind==="customer"||kind==="supplier"){
   const key=kind==="customer"?"customers":"suppliers",prefix=kind==="customer"?"CLI":"PRO";
   return modal(kind==="customer"?"Nuevo cliente":"Nuevo proveedor",`${field("Código","code",`${prefix}-${String(s[key].length+1).padStart(3,"0")}`)}${field("Nombre","name","")}${field("RIF / ID","taxId","")}${field("Teléfono","phone","")}${field("Correo","email","")}${field("Ciudad","city","")}`,f=>{
    const code=requiredText(f.get("code"),"Código"),name=requiredText(f.get("name"),"Nombre");uniqueValue(s[key],"code",code,"Código");
    s[key].push({id:DB.id(kind[0]),code,name,taxId:String(f.get("taxId")||"").trim(),phone:String(f.get("phone")||"").trim(),email:String(f.get("email")||"").trim(),city:String(f.get("city")||"").trim(),creditLimit:0,status:"Activo",balance:0});
    DB.log(`${kind==="customer"?"Cliente":"Proveedor"} creado: ${name}`);
   });
 }
 if(kind==="product")return modal("Nuevo producto",`${field("SKU","sku","")}${field("Nombre","name","")}${field("Categoría","category","General")}${field("Costo","cost","0","number")}${field("Precio","price","0","number")}${field("IVA %","tax","16","number")}${field("Stock mínimo","minStock","0","number")}`,f=>{
   const sku=requiredText(f.get("sku"),"SKU"),name=requiredText(f.get("name"),"Nombre");uniqueValue(s.products,"sku",sku,"SKU");
   const cost=nonNegative(f.get("cost"),"Costo"),price=nonNegative(f.get("price"),"Precio"),tax=nonNegative(f.get("tax"),"IVA"),minStock=nonNegative(f.get("minStock"),"Stock mínimo");
   if(tax>100)throw new Error("IVA no puede superar 100%");
   const pid=DB.id("p");s.products.push({id:pid,sku,name,category:String(f.get("category")||"General").trim(),cost,price,tax,minStock,status:"Activo"});
   s.branches.forEach(b=>s.inventory.push({id:DB.id("i"),productId:pid,branchId:b.id,stock:0,reserved:0}));
   DB.log(`Producto creado: ${name}`);
 });
 if(kind==="cashaccount")return modal("Nueva cuenta",`${field("Nombre","name","")}${field("Tipo","type","Caja")}<div class="field"><label>Moneda</label><select name="currency">${["USD","VES","EUR","USDT"].map(x=>`<option>${x}</option>`).join("")}</select></div><div class="field"><label>Sucursal</label><select name="branchId">${DB.visibleBranches().filter(b=>(b.status||"Activo")!=="Inactivo").map(b=>`<option value="${b.id}">${esc(b.name)}</option>`).join("")}</select></div>`,f=>{
   const name=requiredText(f.get("name"),"Nombre");s.cashAccounts.push({id:DB.id("ca"),name,type:f.get("type"),currency:f.get("currency"),branchId:f.get("branchId"),balance:0,status:"Activa"});DB.log(`Cuenta financiera creada: ${name}`);
 });
 if(kind==="rate")return modal("Nueva tasa",`${field("Fecha","date",new Date().toISOString().slice(0,10),"date")}<div class="field"><label>Moneda</label><select name="currency"><option>USD</option><option>EUR</option><option>USDT</option></select></div>${field("Tasa VES","rate","0","number",'step="0.0001"')}${field("Fuente","source","Manual")}`,f=>{
   const rate=nonNegative(f.get("rate"),"Tasa");if(rate<=0)throw new Error("La tasa debe ser mayor a cero");
   s.exchangeRates.push({id:DB.id("fx"),date:f.get("date"),currency:f.get("currency"),rate,source:String(f.get("source")||"Manual").trim()});DB.log(`Tasa actualizada: ${f.get("currency")}`);
 });
 if(kind==="user")return modal("Nuevo usuario",`${field("Nombre","name","")}${field("Correo","email","")}${field("PIN","pin","1234")}<div class="field"><label>Rol</label><select name="roleId">${s.roles.map(r=>`<option value="${r.id}">${esc(r.name)}</option>`).join("")}</select></div><div class="field"><label>Sucursal</label><select name="branchId"><option value="all">Todas</option>${DB.visibleBranches().filter(b=>(b.status||"Activo")!=="Inactivo").map(b=>`<option value="${b.id}">${esc(b.name)}</option>`).join("")}</select></div>`,f=>{
   const name=requiredText(f.get("name"),"Nombre"),email=requiredText(f.get("email"),"Correo");uniqueValue(s.users,"email",email,"Correo");
   s.users.push({id:DB.id("u"),name,email,pin:requiredText(f.get("pin"),"PIN"),roleId:f.get("roleId"),branchId:f.get("branchId"),status:"Activo"});DB.log(`Usuario creado: ${name}`);
 });
 if(kind==="role")return modal("Nuevo rol",`${field("Nombre","name","")}${field("Descripción","description","")}${field("Permisos separados por coma","permissions","dashboard")}`,f=>{
   const name=requiredText(f.get("name"),"Nombre");uniqueValue(s.roles,"name",name,"Rol");
   s.roles.push({id:DB.id("r"),name,description:String(f.get("description")||"").trim(),permissions:String(f.get("permissions")||"dashboard").split(",").map(x=>x.trim()).filter(Boolean)});DB.log(`Rol creado: ${name}`);
 });
}
async function deleteItem(token){
 const [kind,id]=token.split(":"),s=state();
 const map={branch:"branches",customer:"customers",supplier:"suppliers",product:"products",user:"users"};
 const key=map[kind];if(!key)return;
 const item=s[key].find(x=>x.id===id);if(!item)return;

 if(kind==="user"&&id===s.session.userId)return alert("No puedes desactivar tu propio usuario mientras la sesión está abierta.");

 const inactive=(item.status||"Activo")==="Inactivo";
 const nextActive=inactive;
 if(!inactive){
   const deps=[];
   if(kind==="branch"){
    if(s.sales.some(x=>x.branchId===id))deps.push("ventas");
    if(s.purchases.some(x=>x.branchId===id))deps.push("compras");
    if(s.movements.some(x=>x.branchId===id))deps.push("movimientos");
    if(s.users.some(x=>x.branchId===id&&(x.status||"Activo")!=="Inactivo"))deps.push("usuarios activos");
   }
   if(kind==="product"){
    if(s.sales.some(x=>(x.items||[]).some(i=>i.productId===id)))deps.push("ventas");
    if(s.purchases.some(x=>(x.items||[]).some(i=>i.productId===id)))deps.push("compras");
    if(s.movements.some(x=>x.productId===id))deps.push("movimientos");
   }
   if(kind==="customer"){
    if(s.sales.some(x=>x.customerId===id))deps.push("ventas");
    if(s.receivables.some(x=>x.customerId===id))deps.push("CxC");
   }
   if(kind==="supplier"){
    if(s.purchases.some(x=>x.supplierId===id))deps.push("compras");
    if(s.payables.some(x=>x.supplierId===id))deps.push("CxP");
   }
   const extra=deps.length?`

Tiene historial relacionado: ${deps.join(", ")}. ATLAS conservará todo ese historial.`:"";
   if(!confirm(`¿Desactivar este registro?${extra}`))return;
 }else if(!confirm("¿Reactivar este registro?"))return;

 if(isSupabaseConfigured()&&kind!=="user"){
   try{
    await RemoteRepo.rpc("atlas_set_master_active",{p_entity:kind,p_id:id,p_active:nextActive});
    if(kind==="customer"||kind==="supplier"||kind==="product")await pullCoreWorkspace(state());
    DB.setSyncStatus("synced");
   }catch(e){return alert("No se pudo cambiar el estado: "+e.message)}
 }else{
   item.status=nextActive?"Activo":"Inactivo";
   DB.log(`Registro ${nextActive?"reactivado":"desactivado"}: ${kind}`,"UPDATE",kind);
   DB.save();
 }
 render();
}
function search(kind,q){q=q.toLowerCase();const s=state();if(kind==="customer")document.getElementById("customerTable").innerHTML=partyTable(kind,s.customers.filter(x=>Object.values(x).join(" ").toLowerCase().includes(q)));if(kind==="supplier")document.getElementById("supplierTable").innerHTML=partyTable(kind,s.suppliers.filter(x=>Object.values(x).join(" ").toLowerCase().includes(q)));if(kind==="product")document.getElementById("productTable").innerHTML=productTable(s.products.filter(x=>Object.values(x).join(" ").toLowerCase().includes(q)));bind()}
function adjustStock(invId){const s=state(),i=s.inventory.find(x=>x.id===invId),p=s.products.find(x=>x.id===i.productId),b=s.branches.find(x=>x.id===i.branchId);modal(`Ajustar stock — ${esc(p?.name||"")}`,`${field("Nueva existencia","stock",i.stock,"number")}${field("Motivo","note","Ajuste manual")}`,f=>{const old=Number(i.stock),neu=Number(f.get("stock"));if(!Number.isFinite(neu))throw new Error("Existencia inválida");if(neu<0&&!s.settings.allowNegativeStock)throw new Error("ATLAS no permite stock negativo con la configuración actual");i.stock=neu;s.movements.unshift({id:DB.id("m"),date:new Date().toISOString(),type:"AJUSTE",productId:i.productId,branchId:i.branchId,qty:neu-old,note:f.get("note")});DB.log(`Inventario ajustado: ${p?.name} / ${b?.name}`)})}
function addCart(productId){const p=state().products.find(x=>x.id===productId);if(!p||p.status==="Inactivo")return;const existing=cart.find(x=>x.productId===productId);if(existing)existing.qty+=1;else cart.push({productId:p.id,name:p.name,price:Number(p.price),cost:Number(p.cost||0),tax:Number(p.tax),qty:1});refreshCart()}
async function completeSale(){
 const s=state();if(!cart.length)return alert("Agrega productos a la venta.");
 const customerId=document.getElementById("saleCustomer").value,branchId=document.getElementById("saleBranch").value,condition=document.getElementById("saleCondition").value,accountId=document.getElementById("saleAccount").value,paymentMethodId=document.getElementById("salePaymentMethod")?.value||null,documentCurrency=document.getElementById("saleCurrency")?.value||"USD";
 requireSelection(customerId,"un cliente");requireSelection(branchId,"una sucursal");
 ensureActive(s.customers.find(x=>x.id===customerId),"Cliente");ensureActive(s.branches.find(x=>x.id===branchId),"Sucursal");
 if(condition==="cash"){requireSelection(accountId,"una cuenta de cobro");if(activePaymentMethods().length)requireSelection(paymentMethodId,"un método de pago");ensureActive(activeCashAccounts().find(a=>a.id===accountId),"Cuenta financiera");}
 if(isSupabaseConfigured()){
   try{
     const result=await RemoteRepo.createSale({
       p_branch_id:branchId,p_customer_id:customerId,p_payment_condition:condition,
       p_cash_account_id:condition==="cash"?accountId:null,
       p_items:cart.map(i=>({product_id:i.productId,qty:Number(i.qty)}))
     });
     cart=[];DB.setSyncStatus("syncing");await pullCoreWorkspace(state());await pullTransactions(state());await pullAccounting(state());DB.setSyncStatus("synced");
     DB.log(`Venta remota ${result.number} completada`,"CREATE","sale");
     render();return alert(`Venta ${result.number} registrada en la nube.`);
   }catch(e){DB.setSyncStatus("error",e.message);render();return alert("No se pudo completar la venta: "+e.message)}
 }
 for(const item of cart){
 const inv=s.inventory.find(i=>i.productId===item.productId&&i.branchId===branchId);
 if(!inv)return alert(`No existe inventario para ${item.name}`);
 if(inv.stock<item.qty&&!s.settings.allowNegativeStock)return alert(`Stock insuficiente para ${item.name}`);
 const p=s.products.find(p=>p.id===item.productId);if(item.cost===undefined)item.cost=Number(p?.cost||0);
}
 return localAtomic("Venta",()=>{ 
 const t=cartTotals(),number=nextConfiguredDoc("sale","V"),date=new Date().toISOString();
 const doc=documentAmountsFromUSD(t,documentCurrency);
 s.sales.push({id:DB.id("v"),number,date,customerId,branchId,items:JSON.parse(JSON.stringify(cart)),subtotal:t.subtotal,tax:t.tax,total:t.total,baseTotalUSD:t.total,currency:doc.currency,documentSubtotal:doc.subtotal,documentTax:doc.tax,documentTotal:doc.total,exchangeRate:doc.rate,condition,paymentMethodId,status:"Completada"});
 for(const item of cart){const inv=s.inventory.find(i=>i.productId===item.productId&&i.branchId===branchId);inv.stock-=item.qty;s.movements.unshift({id:DB.id("m"),date,type:"VENTA",productId:item.productId,branchId,qty:-item.qty,note:number})}
 if(condition==="cash"){
  const payment=convertedPayment(t.total,accountId);
  DB.moveCash(accountId,"IN",payment.amount,number,`Venta de contado · Documento ${doc.currency} ${money(doc.total)}`,paymentMethodId,payment.account.currency,payment.rate);
 }else{
  const due=new Date();due.setDate(due.getDate()+Number(s.settings.defaultCreditDays||30));s.receivables.push({id:DB.id("ar"),reference:number,customerId,date,dueDate:due.toISOString(),total:t.total,balance:t.total,baseBalanceUSD:t.total,currency:doc.currency,documentTotal:doc.total,exchangeRate:doc.rate,status:"Pendiente"});
  const c=s.customers.find(c=>c.id===customerId);if(c)c.balance=Number(c.balance||0)+t.total;
 }
 const cashAcc=accountByName("Caja y bancos");
 const arAcc=accountByName("Cuentas por cobrar");
 const salesAcc=accountByName("Ventas");
 const taxAcc=accountByName("IVA por pagar");
 const cogsAcc=accountByName("Costo de ventas");
 const invAcc=accountByName("Inventario");
 const debitAcc=condition==="cash"?cashAcc:arAcc;
 const cogs=cart.reduce((a,i)=>a+Number(i.cost||0)*Number(i.qty||0),0);
 const saleLines=[
   {accountId:debitAcc,debit:t.total,credit:0},
   {accountId:salesAcc,debit:0,credit:t.subtotal},
   {accountId:taxAcc,debit:0,credit:t.tax}
 ];
 if(cogs>0){saleLines.push({accountId:cogsAcc,debit:cogs,credit:0},{accountId:invAcc,debit:0,credit:cogs})}
 DB.postJournal(number,"Venta",saleLines);
 DB.log(`Venta registrada ${number} por $${money(t.total)}`,"CREATE","sale");DB.save();cart=[];render();alert(`Venta ${number} registrada correctamente`);
 return number;
 });
}
function newPurchase(){
 const s=state();
 modal("Registrar compra",`
 <div class="field"><label>Proveedor</label><select name="supplierId">${s.suppliers.map(x=>`<option value="${x.id}">${esc(x.name)}</option>`).join("")}</select></div>
 <div class="field"><label>Sucursal</label><select name="branchId">${s.branches.map(x=>`<option value="${x.id}">${esc(x.name)}</option>`).join("")}</select></div>
 <div class="field"><label>Producto</label><select name="productId">${s.products.map(x=>`<option value="${x.id}">${esc(x.name)}</option>`).join("")}</select></div>
 ${field("Cantidad","qty","1","number",'min="1"')}${field("Costo unitario USD","cost","0","number",'step="0.01"')}
 <div class="field"><label>Moneda del documento</label><select name="documentCurrency">${currencyOptions("USD")}</select></div>
 <div class="field"><label>Condición</label><select name="condition"><option value="cash">Contado</option><option value="credit">Crédito</option></select></div>
 <div class="field"><label>Método de pago</label><select name="paymentMethodId">${activePaymentMethods().map(m=>`<option value="${m.id}">${esc(m.name)}</option>`).join("")}</select></div>
 <div class="field"><label>Cuenta para pago</label><select name="accountId">${activeCashAccounts().map(a=>`<option value="${a.id}">${esc(a.name)} (${esc(a.currency)})</option>`).join("")}</select></div>
 `,async f=>{
   const supplierId=requireSelection(f.get("supplierId"),"un proveedor"),branchId=requireSelection(f.get("branchId"),"una sucursal"),productId=requireSelection(f.get("productId"),"un producto"),qty=requirePositiveNumber(f.get("qty"),"Cantidad"),cost=requireNonNegativeNumber(f.get("cost"),"Costo"),condition=f.get("condition"),accountId=f.get("accountId"),paymentMethodId=f.get("paymentMethodId")||null,documentCurrency=f.get("documentCurrency")||"USD",product=s.products.find(p=>p.id===productId),subtotal=qty*cost,tax=subtotal*Number(product?.tax||0)/100,total=subtotal+tax,date=new Date().toISOString(),doc=documentAmountsFromUSD({subtotal,tax,total},documentCurrency);
   ensureActive(s.suppliers.find(x=>x.id===supplierId),"Proveedor");ensureActive(s.branches.find(x=>x.id===branchId),"Sucursal");ensureActive(product,"Producto");
   if(condition==="cash"){requireSelection(accountId,"una cuenta para pago");if(activePaymentMethods().length)requireSelection(paymentMethodId,"un método de pago");ensureActive(activeCashAccounts().find(a=>a.id===accountId),"Cuenta financiera");}
   if(isSupabaseConfigured()){
     const result=await RemoteRepo.createPurchase({p_branch_id:branchId,p_supplier_id:supplierId,p_payment_condition:condition,p_cash_account_id:condition==="cash"?accountId:null,p_product_id:productId,p_qty:qty,p_cost:cost});
     await pullCoreWorkspace(state());await pullTransactions(state());await pullAccounting(state());DB.setSyncStatus("synced");
     DB.log(`Compra remota ${result.number} completada`,"CREATE","purchase");return;
   }
   return localAtomic("Compra",()=>{
   const number=nextConfiguredDoc("purchase","C");
   s.purchases.push({id:DB.id("pu"),number,date,supplierId,branchId,items:[{productId,qty,cost,taxRate:Number(product?.tax||0)}],subtotal,tax,total,baseTotalUSD:total,currency:doc.currency,documentSubtotal:doc.subtotal,documentTax:doc.tax,documentTotal:doc.total,exchangeRate:doc.rate,condition,paymentMethodId,status:"Recibida"});
   let inv=s.inventory.find(i=>i.productId===productId&&i.branchId===branchId);if(!inv){inv={id:DB.id("i"),productId,branchId,stock:0,reserved:0};s.inventory.push(inv)}inv.stock+=qty;
   const p=s.products.find(p=>p.id===productId);if(p)p.cost=cost;
   s.movements.unshift({id:DB.id("m"),date,type:"COMPRA",productId,branchId,qty,note:number});
   if(condition==="cash"){
     const payment=convertedPayment(total,accountId);
     DB.moveCash(accountId,"OUT",payment.amount,number,`Compra de contado · Documento ${doc.currency} ${money(doc.total)}`,paymentMethodId,payment.account.currency,payment.rate);
   }else{const due=new Date();due.setDate(due.getDate()+Number(s.settings.defaultCreditDays||30));s.payables.push({id:DB.id("ap"),reference:number,supplierId,date,dueDate:due.toISOString(),total,balance:total,baseBalanceUSD:total,currency:doc.currency,documentTotal:doc.total,exchangeRate:doc.rate,status:"Pendiente"});const pr=s.suppliers.find(x=>x.id===supplierId);if(pr)pr.balance=Number(pr.balance||0)+total}
   const invAcc=accountByName("Inventario"),cashAcc=accountByName("Caja y bancos"),apAcc=accountByName("Cuentas por pagar"),vatCreditAcc=accountByName("IVA crédito fiscal");
   const purchaseLines=[{accountId:invAcc,debit:subtotal,credit:0}];
   if(tax>0)purchaseLines.push({accountId:vatCreditAcc,debit:tax,credit:0});
   purchaseLines.push({accountId:condition==="cash"?cashAcc:apAcc,debit:0,credit:total});
   DB.postJournal(number,"Compra de mercancía",purchaseLines);
   DB.log(`Compra registrada ${number} por $${money(total)}`,"CREATE","purchase");DB.save();
   return number;
   });
 });
}



function addSupplierCredit(supplierId,amount,reference){
 const s=state(),n=Number(amount||0);
 if(n<=0)return null;
 const c={id:DB.id("sc"),supplierId,reference,date:new Date().toISOString(),amount:n,balance:n,currency:"USD",status:"Disponible"};
 s.supplierCredits.unshift(c);
 return c;
}

function applySupplierCredit(creditId){
 const s=state(),credit=(s.supplierCredits||[]).find(c=>c.id===creditId);
 if(!credit||Number(credit.balance||0)<=0)throw new Error("El crédito del proveedor ya no está disponible.");
 const debts=(s.payables||[]).filter(r=>r.supplierId===credit.supplierId&&Number(r.balance||0)>0);
 if(!debts.length)return alert("Este proveedor no tiene cuentas pendientes.");
 modal("Aplicar crédito de proveedor",`
  <div class="notice">Disponible: USD ${money(credit.balance)}</div>
  <div class="field"><label>Cuenta por pagar</label><select name="payableId">${debts.map(r=>`<option value="${r.id}">${esc(r.reference)} · USD ${money(r.balance)}</option>`).join("")}</select></div>
  ${field("Monto a aplicar (USD)","amount",Math.min(Number(credit.balance||0),Number(debts[0]?.balance||0)),"number",'step="0.01" min="0.01"')}
 `,f=>{
  const p=debts.find(x=>x.id===requireSelection(f.get("payableId"),"una cuenta por pagar"));
  if(!p)throw new Error("Cuenta por pagar inexistente.");
  const requested=requirePositiveNumber(f.get("amount"),"Monto");
  const amount=Math.min(requested,Number(credit.balance||0),Number(p.balance||0));
  if(amount<=0)throw new Error("No hay saldo disponible para aplicar.");
  return localAtomic("Aplicación de crédito proveedor",()=>{
   credit.balance=safeMoney(Number(credit.balance||0)-amount);
   credit.status=credit.balance<=0?"Utilizado":"Parcial";
   credit.usedAt=new Date().toISOString();
   p.balance=safeMoney(Number(p.balance||0)-amount);
   p.status=p.balance<=0?"Pagada":"Parcial";
   const supplier=s.suppliers.find(x=>x.id===credit.supplierId);
   if(supplier)supplier.balance=Math.max(0,safeMoney(Number(supplier.balance||0)-amount));
   const lines=[
    {accountId:accountByName("Cuentas por pagar"),debit:amount,credit:0},
    {accountId:accountByName("Créditos de proveedores"),debit:0,credit:amount}
   ];
   assertJournalBalanced(lines);
   const applicationRef=nextLocalDoc("supplierCreditApplication","CP");
   DB.postJournal(applicationRef,"Aplicación de crédito de proveedor",lines);
   DB.log(`Crédito de proveedor aplicado a ${p.reference}: USD ${money(amount)}`,"CREATE","supplier_credit_application");
   DB.save();
   return amount;
  });
 });
}

function newPurchaseReturn(){
 const s=state(),eligible=(s.purchases||[]).filter(p=>p.status!=="Anulada");
 if(!eligible.length)return alert("No hay compras disponibles para devolver.");
 modal("Devolución de compra",`
  <div class="field"><label>Compra</label><select name="purchaseId">${eligible.map(p=>`<option value="${p.id}">${esc(p.number)} · ${esc(s.suppliers.find(x=>x.id===p.supplierId)?.name||"")}</option>`).join("")}</select></div>
  <div class="field"><label>Producto</label><select name="productId">${s.products.filter(p=>p.status!=="Inactivo").map(p=>`<option value="${p.id}">${esc(p.name)}</option>`).join("")}</select></div>
  ${field("Cantidad","qty","1","number",'step="1" min="1"')}
  <div class="notice">Si la compra fue de contado, selecciona dónde recibiste el reembolso. Si fue a crédito, ATLAS reducirá la cuenta por pagar y generará crédito del proveedor si sobra importe.</div>
  <div class="field"><label>Cuenta que recibe reembolso</label><select name="refundAccountId"><option value="">— Solo si aplica —</option>${activeCashAccounts().map(a=>`<option value="${a.id}">${esc(a.name)} (${esc(a.currency)})</option>`).join("")}</select></div>
  <div class="field"><label>Método de pago</label><select name="paymentMethodId"><option value="">— Solo si aplica —</option>${activePaymentMethods().map(m=>`<option value="${m.id}">${esc(m.name)}</option>`).join("")}</select></div>
 `,f=>{
  const purchase=s.purchases.find(p=>p.id===requireSelection(f.get("purchaseId"),"una compra"));
  if(!purchase)throw new Error("Compra inexistente.");
  const productId=requireSelection(f.get("productId"),"un producto");
  const item=(purchase.items||[]).find(i=>i.productId===productId);
  if(!item)throw new Error("Ese producto no pertenece a la compra.");
  const qty=requirePositiveNumber(f.get("qty"),"Cantidad");
  const already=(s.purchaseReturns||[]).filter(r=>r.purchaseId===purchase.id&&r.productId===productId&&r.status!=="Anulada").reduce((a,r)=>a+Number(r.qty||0),0);
  if(qty+already>Number(item.qty||0)+1e-9)throw new Error("La cantidad devuelta supera la cantidad comprada.");
  return localAtomic("Devolución de compra",()=>{
   const unitCost=Number(item.cost||0),taxRate=Number(item.taxRate||0);
   const net=safeMoney(unitCost*qty),tax=safeMoney(net*taxRate/100),amount=safeMoney(net+tax);
   const number=nextConfiguredDoc("purchaseReturn","DC");
   let inv=s.inventory.find(i=>i.productId===productId&&i.branchId===purchase.branchId);
   if(!inv)throw new Error("Inventario inexistente para esta compra.");
   if(Number(inv.stock||0)<qty)throw new Error("No hay suficiente existencia para devolver al proveedor.");
   inv.stock-=qty;
   s.movements.unshift({id:DB.id("m"),date:new Date().toISOString(),type:"DEVOLUCIÓN COMPRA",productId,branchId:purchase.branchId,qty:-qty,note:number});
   const creditPurchase=(purchase.paymentCondition||purchase.condition)==="credit";
   let payableReduction=0,supplierCredit=0,refundAccountId=null,refundAmount=null,refundCurrency=null,refundRate=null,paymentMethodId=null;
   if(creditPurchase){
    const payable=(s.payables||[]).find(r=>r.reference===purchase.number);
    if(payable&&Number(payable.balance||0)>0){
      payableReduction=Math.min(Number(payable.balance||0),amount);
      payable.balance=safeMoney(Number(payable.balance||0)-payableReduction);
      payable.status=payable.balance<=0?"Pagada":"Parcial";
      const supplier=s.suppliers.find(x=>x.id===purchase.supplierId);
      if(supplier)supplier.balance=Math.max(0,safeMoney(Number(supplier.balance||0)-payableReduction));
    }
    supplierCredit=safeMoney(amount-payableReduction);
    if(supplierCredit>0)addSupplierCredit(purchase.supplierId,supplierCredit,number);
   }else{
    refundAccountId=requireSelection(f.get("refundAccountId"),"una cuenta para recibir el reembolso");
    paymentMethodId=f.get("paymentMethodId")||null;
    if(activePaymentMethods().length)requireSelection(paymentMethodId,"un método de pago");
    const refund=convertedPayment(amount,refundAccountId);
    DB.moveCash(refundAccountId,"IN",refund.amount,number,`Reembolso devolución compra ${purchase.number}`,paymentMethodId,refund.account.currency,refund.rate);
    refundAmount=refund.amount;refundCurrency=refund.account.currency;refundRate=refund.rate;
   }
   const lines=[
    {accountId:accountByName("Cuentas por pagar"),debit:creditPurchase?payableReduction:0,credit:0},
    {accountId:accountByName("Créditos de proveedores"),debit:supplierCredit,credit:0},
    {accountId:accountByName("Inventario"),debit:0,credit:net},
    {accountId:accountByName("IVA crédito fiscal"),debit:0,credit:tax}
   ];
   if(!creditPurchase)lines.push({accountId:accountByName("Caja y bancos"),debit:amount,credit:0});
   const clean=lines.filter(l=>Number(l.debit||0)>0||Number(l.credit||0)>0);
   assertJournalBalanced(clean);
   DB.postJournal(number,`Devolución de compra ${purchase.number}`,clean);
   s.purchaseReturns.unshift({
    id:DB.id("pr"),number,date:new Date().toISOString(),purchaseId:purchase.id,purchaseNumber:purchase.number,
    supplierId:purchase.supplierId,branchId:purchase.branchId,productId,qty,net,tax,amount,
    payableReduction,supplierCredit,refundAccountId,refundAmount,refundCurrency,refundRate,paymentMethodId,status:"Completada"
   });
   DB.log(`Devolución de compra ${number} registrada`,"CREATE","purchase_return");
   DB.save();
   return number;
  });
 });
}

function voidPurchase(id){
 requirePermission("purchases","anular compras"); sensitiveConfirm("anular una compra");
 const s=state(),purchase=s.purchases.find(p=>p.id===id);
 if(!purchase)return;
 if(purchase.status==="Anulada")return alert("La compra ya está anulada.");
 if((s.purchaseReturns||[]).some(r=>r.purchaseId===purchase.id&&r.status!=="Anulada"))return alert("La compra tiene devoluciones activas. Usa el proceso de devolución en lugar de anular.");
 const creditPurchase=(purchase.paymentCondition||purchase.condition)==="credit";
 const payable=(s.payables||[]).find(r=>r.reference===purchase.number);
 if(creditPurchase&&payable&&Number(payable.balance||0)<Number(payable.total||purchase.total)-0.01)
   return alert("Esta compra a crédito ya tiene pagos aplicados. Para proteger los saldos, usa Devolución de compra.");
 modal("Anular compra",`
  <div class="notice">ATLAS retirará del inventario lo recibido y revertirá cuentas y contabilidad. Si fue una compra de contado, se registrará la entrada del reembolso.</div>
  ${field("Motivo","reason","Error de operación")}
  ${!creditPurchase?`<div class="field"><label>Cuenta que recibe reembolso</label><select name="refundAccountId">${activeCashAccounts().map(a=>`<option value="${a.id}">${esc(a.name)} (${esc(a.currency)})</option>`).join("")}</select></div>
  <div class="field"><label>Método</label><select name="paymentMethodId">${activePaymentMethods().map(m=>`<option value="${m.id}">${esc(m.name)}</option>`).join("")}</select></div>`:""}
 `,f=>{
  const reason=requiredText(f.get("reason"),"Motivo");
  return localAtomic("Anulación de compra",()=>{
   const total=Number(purchase.baseTotalUSD??purchase.total||0);
   const subtotal=Number(purchase.subtotal||0),tax=Number(purchase.tax||0);
   for(const item of purchase.items||[]){
    const inv=s.inventory.find(i=>i.productId===item.productId&&i.branchId===purchase.branchId);
    if(!inv||Number(inv.stock||0)<Number(item.qty||0))throw new Error("No se puede anular: parte del inventario recibido ya no está disponible.");
   }
   for(const item of purchase.items||[]){
    const inv=s.inventory.find(i=>i.productId===item.productId&&i.branchId===purchase.branchId);
    inv.stock-=Number(item.qty||0);
    s.movements.unshift({id:DB.id("m"),date:new Date().toISOString(),type:"ANULACIÓN COMPRA",productId:item.productId,branchId:purchase.branchId,qty:-Number(item.qty||0),note:purchase.number});
   }
   const lines=[
    {accountId:accountByName("Inventario"),debit:0,credit:subtotal},
    {accountId:accountByName("IVA crédito fiscal"),debit:0,credit:tax}
   ];
   if(creditPurchase){
    if(payable){payable.balance=0;payable.status="Anulada";payable.cancelledAt=new Date().toISOString()}
    const supplier=s.suppliers.find(x=>x.id===purchase.supplierId);
    if(supplier)supplier.balance=Math.max(0,safeMoney(Number(supplier.balance||0)-total));
    lines.push({accountId:accountByName("Cuentas por pagar"),debit:total,credit:0});
   }else{
    const accountId=requireSelection(f.get("refundAccountId"),"una cuenta para recibir el reembolso");
    const payment=convertedPayment(total,accountId);
    const pm=f.get("paymentMethodId")||null;
    if(activePaymentMethods().length&&!pm)throw new Error("Selecciona un método para registrar el reembolso de la compra.");
    DB.moveCash(accountId,"IN",payment.amount,`AN-${purchase.number}`,`Anulación: ${reason}`,pm,payment.account.currency,payment.rate);
    lines.push({accountId:accountByName("Caja y bancos"),debit:total,credit:0});
   }
   assertJournalBalanced(lines);
   DB.postJournal(`AN-${purchase.number}`,`Anulación de compra · ${reason}`,lines);
   purchase.status="Anulada";purchase.voidedAt=new Date().toISOString();purchase.voidReason=reason;
   DB.log(`Compra ${purchase.number} anulada · ${reason}`,"VOID","purchase");
   DB.save();
   return purchase.number;
  });
 });
}

function newCashTransfer(){
 requirePermission("cash","transferir entre cuentas"); sensitiveConfirm("transferir entre cuentas");
 const s=state(),accounts=activeCashAccounts();
 if(accounts.length<2)return alert("Necesitas al menos dos cuentas activas para hacer una transferencia.");
 modal("Transferencia entre cuentas",`
  <div class="notice">ATLAS convierte automáticamente si las cuentas usan monedas distintas.</div>
  <div class="field"><label>Cuenta origen</label><select name="fromAccountId">${accounts.map(a=>`<option value="${a.id}">${esc(a.name)} · ${esc(a.currency)} · ${money(a.balance)}</option>`).join("")}</select></div>
  <div class="field"><label>Cuenta destino</label><select name="toAccountId">${accounts.map(a=>`<option value="${a.id}">${esc(a.name)} · ${esc(a.currency)}</option>`).join("")}</select></div>
  ${field("Monto a enviar","amount","","number",'step="0.01" min="0.01"')}
  ${field("Referencia (opcional)","reference","")}
  ${field("Nota","note","Transferencia entre cuentas")}
 `,f=>{
  const fromId=requireSelection(f.get("fromAccountId"),"una cuenta origen");
  const toId=requireSelection(f.get("toAccountId"),"una cuenta destino");
  if(fromId===toId)throw new Error("La cuenta origen y destino deben ser diferentes.");
  const from=ensureActive(accounts.find(a=>a.id===fromId),"Cuenta origen");
  const to=ensureActive(accounts.find(a=>a.id===toId),"Cuenta destino");
  const amount=requirePositiveNumber(f.get("amount"),"Monto");
  const manualReference=String(f.get("reference")||"").trim();
  const note=String(f.get("note")||"Transferencia entre cuentas").trim();
  return localAtomic("Transferencia financiera",()=>{
   const reference=manualReference||nextConfiguredDoc("cashTransfer","TF");
   const received=convertMoney(amount,from.currency,to.currency);
   const fromUsd=convertMoney(amount,from.currency,"USD");
   const fromRate=latestRateFor(from.currency)||1,toRate=latestRateFor(to.currency)||1;
   DB.moveCash(from.id,"OUT",amount,reference,note,null,from.currency,fromRate);
   DB.moveCash(to.id,"IN",received,reference,note,null,to.currency,toRate);
   s.cashTransfers.unshift({
    id:DB.id("ct"),date:new Date().toISOString(),reference,fromAccountId:from.id,toAccountId:to.id,
    fromAmount:amount,fromCurrency:from.currency,toAmount:received,toCurrency:to.currency,
    baseAmountUSD:fromUsd,fromRate,toRate,note,status:"Completada"
   });
   DB.log(`Transferencia ${reference}: ${from.currency} ${money(amount)} → ${to.currency} ${money(received)}`,"CREATE","cash_transfer");
   DB.save();
   return reference;
  });
 });
}

function newCashClosing(){
 const s=state(),accounts=activeCashAccounts();
 if(!accounts.length)return alert("No hay cuentas activas para cerrar.");
 modal("Cierre de caja",`
  <div class="notice">Cuenta el dinero real. ATLAS comparará ese valor con el saldo del sistema.</div>
  <div class="field"><label>Cuenta</label><select name="accountId">${accounts.map(a=>`<option value="${a.id}">${esc(a.name)} · ${esc(a.currency)} · Sistema ${money(a.balance)}</option>`).join("")}</select></div>
  ${field("Monto contado físicamente","countedBalance","","number",'step="0.01" min="0"')}
  ${field("Observación","note","Cierre de caja")}
 `,f=>{
  const accountId=requireSelection(f.get("accountId"),"una cuenta");
  const account=ensureActive(accounts.find(a=>a.id===accountId),"Cuenta");
  const counted=requireNonNegativeNumber(f.get("countedBalance"),"Monto contado");
  const systemBalance=Number(account.balance||0);
  const difference=safeMoney(counted-systemBalance);
  return localAtomic("Cierre de caja",()=>{
   const closing={
    id:DB.id("cc"),number:nextConfiguredDoc("cashClosing","CJ"),date:new Date().toISOString(),accountId,
    currency:account.currency,systemBalance,countedBalance:counted,difference,
    note:String(f.get("note")||"").trim(),status:Math.abs(difference)<0.01?"Cuadrado":"Con diferencia"
   };
   s.cashClosings.unshift(closing);
   DB.log(`Cierre ${closing.number} · ${account.name} · diferencia ${account.currency} ${money(difference)}`,"CREATE","cash_closing");
   DB.save();
   return closing.number;
  });
 });
}

function reconcileCashClosing(id){
 requirePermission("cash","conciliar caja"); sensitiveConfirm("conciliar una diferencia de caja");
 const s=state(),closing=(s.cashClosings||[]).find(c=>c.id===id);
 if(!closing)return;
 if(closing.status!=="Con diferencia")return alert("Este cierre ya no tiene una diferencia pendiente.");
 const account=s.cashAccounts.find(a=>a.id===closing.accountId);
 if(!account)return alert("La cuenta del cierre ya no existe.");
 const diff=Number(closing.difference||0);
 modal("Conciliar diferencia",`
  <div class="notice">Diferencia detectada: <strong>${moneyWithCurrency(diff,closing.currency)}</strong>. La conciliación ajustará el saldo del sistema al monto contado y dejará trazabilidad.</div>
  ${field("Motivo de la diferencia","reason","Diferencia de cierre")}
 `,f=>{
  const reason=requiredText(f.get("reason"),"Motivo");
  return localAtomic("Conciliación de caja",()=>{
   const amount=Math.abs(diff);
   const type=diff>0?"IN":"OUT";
   const ref=`AJ-${closing.number}`;
   DB.moveCash(account.id,type,amount,ref,reason,null,account.currency,latestRateFor(account.currency)||1);
   const baseAmount=convertMoney(amount,account.currency,"USD");
   const lines=diff>0?[
    {accountId:accountByName("Caja y bancos"),debit:baseAmount,credit:0},
    {accountId:accountByName("Ajustes y diferencias de caja"),debit:0,credit:baseAmount}
   ]:[
    {accountId:accountByName("Ajustes y diferencias de caja"),debit:baseAmount,credit:0},
    {accountId:accountByName("Caja y bancos"),debit:0,credit:baseAmount}
   ];
   assertJournalBalanced(lines);
   DB.postJournal(ref,`Conciliación de caja · ${reason}`,lines);
   const rec={
    id:DB.id("cr"),date:new Date().toISOString(),closingId:closing.id,accountId:account.id,
    currency:account.currency,difference:diff,adjustmentAmount:amount,baseAmountUSD:baseAmount,reason,status:"Aplicada"
   };
   s.cashReconciliations.unshift(rec);
   closing.status="Conciliado";closing.reconciledAt=rec.date;closing.reconciliationId=rec.id;
   DB.log(`Cierre ${closing.number} conciliado · ${reason}`,"CREATE","cash_reconciliation");
   DB.save();
   return rec.id;
  });
 });
}

function applyCustomerCredit(creditId){
 const s=state(),credit=(s.customerCredits||[]).find(c=>c.id===creditId);
 if(!credit||Number(credit.balance||0)<=0)throw new Error("El crédito ya no está disponible.");
 const debts=(s.receivables||[]).filter(r=>r.customerId===credit.customerId&&Number(r.balance||0)>0);
 if(!debts.length)return alert("Este cliente no tiene cuentas pendientes.");
 modal("Aplicar crédito a favor",`
  <div class="notice">Disponible: USD ${money(credit.balance)}</div>
  <div class="field"><label>Cuenta por cobrar</label><select name="receivableId">${debts.map(r=>`<option value="${r.id}">${esc(r.reference)} · USD ${money(r.balance)}</option>`).join("")}</select></div>
  ${field("Monto a aplicar (USD)","amount",Math.min(Number(credit.balance||0),Number(debts[0]?.balance||0)),"number",'step="0.01" min="0.01"')}
 `,f=>{
  const r=debts.find(x=>x.id===requireSelection(f.get("receivableId"),"una cuenta por cobrar"));
  if(!r)throw new Error("Cuenta por cobrar inexistente.");
  const requested=requirePositiveNumber(f.get("amount"),"Monto");
  const amount=Math.min(requested,Number(credit.balance||0),Number(r.balance||0));
  if(amount<=0)throw new Error("No hay saldo disponible para aplicar.");
  return localAtomic("Aplicación de crédito",()=>{
   credit.balance=safeMoney(Number(credit.balance||0)-amount);
   credit.status=credit.balance<=0?"Utilizado":"Parcial";
   credit.usedAt=new Date().toISOString();
   r.balance=safeMoney(Number(r.balance||0)-amount);
   r.status=r.balance<=0?"Pagada":"Parcial";
   const c=s.customers.find(x=>x.id===credit.customerId);
   if(c)c.balance=Math.max(0,safeMoney(Number(c.balance||0)-amount));
   const lines=[
    {accountId:accountByName("Créditos a clientes"),debit:amount,credit:0},
    {accountId:accountByName("Cuentas por cobrar"),debit:0,credit:amount}
   ];
   assertJournalBalanced(lines);
   const applicationRef=nextLocalDoc("customerCreditApplication","NC");
   DB.postJournal(applicationRef,"Aplicación de crédito a favor",lines);
   DB.log(`Crédito aplicado a ${r.reference}: USD ${money(amount)}`,"CREATE","customer_credit_application");
   DB.save();
   return amount;
  });
 });
}

function payReceivable(id){
 const s=state(),r=s.receivables.find(x=>x.id===id);if(!r)return;
 modal("Registrar cobro",`<div class="notice">Saldo a aplicar en USD. ATLAS convierte automáticamente al tipo de moneda de la cuenta seleccionada.</div>${field("Monto a aplicar (USD)","amount",r.balance,"number",'step="0.01" min="0.01"')}<div class="field"><label>Método de pago</label><select name="paymentMethodId">${activePaymentMethods().map(m=>`<option value="${m.id}">${esc(m.name)}</option>`).join("")}</select></div><div class="field"><label>Cuenta destino</label><select name="accountId">${activeCashAccounts().map(a=>`<option value="${a.id}">${esc(a.name)} (${esc(a.currency)})</option>`).join("")}</select></div>`,async f=>{
  const requested=requirePositiveNumber(f.get("amount"),"Monto");const amt=Math.min(requested,Number(r.balance||0));if(amt<=0)throw new Error("La cuenta ya no tiene saldo pendiente.");requireSelection(f.get("accountId"),"una cuenta destino");
  if(isSupabaseConfigured()){await RemoteRepo.collectReceivable({p_receivable_id:id,p_amount:amt,p_cash_account_id:f.get("accountId")});await pullTransactions(state());await pullAccounting(state());DB.setSyncStatus("synced");DB.log(`Cobro remoto registrado: ${r.reference}`,"CREATE","receivable_payment");return;}
  return localAtomic("Cobro",()=>{
  r.balance-=amt;r.status=r.balance<=0?"Pagada":"Parcial";const c=s.customers.find(c=>c.id===r.customerId);if(c)c.balance=Math.max(0,Number(c.balance||0)-amt);
  const payment=convertedPayment(amt,f.get("accountId"));
  DB.moveCash(f.get("accountId"),"IN",payment.amount,r.reference,`Cobro aplicado USD ${money(amt)}`,f.get("paymentMethodId")||null,payment.account.currency,payment.rate);
  DB.postJournal(r.reference,"Cobro de cuenta por cobrar",[{accountId:accountByName("Caja y bancos"),debit:amt,credit:0},{accountId:accountByName("Cuentas por cobrar"),debit:0,credit:amt}]);
  DB.log(`Cobro registrado: ${r.reference}`);DB.save();
  return amt;
  });
 });
}
function payPayable(id){
 const s=state(),r=s.payables.find(x=>x.id===id);if(!r)return;
 modal("Registrar pago",`<div class="notice">Saldo a aplicar en USD. ATLAS convierte automáticamente al tipo de moneda de la cuenta seleccionada.</div>${field("Monto a aplicar (USD)","amount",r.balance,"number",'step="0.01" min="0.01"')}<div class="field"><label>Método de pago</label><select name="paymentMethodId">${activePaymentMethods().map(m=>`<option value="${m.id}">${esc(m.name)}</option>`).join("")}</select></div><div class="field"><label>Cuenta origen</label><select name="accountId">${activeCashAccounts().map(a=>`<option value="${a.id}">${esc(a.name)} (${esc(a.currency)})</option>`).join("")}</select></div>`,async f=>{
  const requested=requirePositiveNumber(f.get("amount"),"Monto");const amt=Math.min(requested,Number(r.balance||0));if(amt<=0)throw new Error("La cuenta ya no tiene saldo pendiente.");requireSelection(f.get("accountId"),"una cuenta origen");
  if(isSupabaseConfigured()){await RemoteRepo.payPayable({p_payable_id:id,p_amount:amt,p_cash_account_id:f.get("accountId")});await pullTransactions(state());await pullAccounting(state());DB.setSyncStatus("synced");DB.log(`Pago remoto registrado: ${r.reference}`,"CREATE","payable_payment");return;}
  return localAtomic("Pago",()=>{
  r.balance-=amt;r.status=r.balance<=0?"Pagada":"Parcial";const p=s.suppliers.find(p=>p.id===r.supplierId);if(p)p.balance=Math.max(0,Number(p.balance||0)-amt);
  const payment=convertedPayment(amt,f.get("accountId"));
  DB.moveCash(f.get("accountId"),"OUT",payment.amount,r.reference,`Pago aplicado USD ${money(amt)}`,f.get("paymentMethodId")||null,payment.account.currency,payment.rate);
  DB.postJournal(r.reference,"Pago de cuenta por pagar",[{accountId:accountByName("Cuentas por pagar"),debit:amt,credit:0},{accountId:accountByName("Caja y bancos"),debit:0,credit:amt}]);
  DB.log(`Pago registrado: ${r.reference}`);DB.save();
  return amt;
  });
 });
}


function newStockTransfer(){
 const s=state();
 if(s.branches.length<2)return alert("Necesitas al menos dos sucursales.");
 modal("Nueva transferencia de stock",`
  <div class="field"><label>Producto</label><select name="productId">${s.products.filter(p=>(p.status||"Activo")!=="Inactivo").map(p=>`<option value="${p.id}">${esc(p.name)}</option>`).join("")}</select></div>
  <div class="field"><label>Origen</label><select name="fromBranchId">${DB.visibleBranches().filter(b=>(b.status||"Activo")!=="Inactivo").map(b=>`<option value="${b.id}">${esc(b.name)}</option>`).join("")}</select></div>
  <div class="field"><label>Destino</label><select name="toBranchId">${DB.visibleBranches().filter(b=>(b.status||"Activo")!=="Inactivo").map(b=>`<option value="${b.id}">${esc(b.name)}</option>`).join("")}</select></div>
  ${field("Cantidad","qty","1","number",'min="0.001" step="0.001"')}
 `,async f=>{
  const productId=requireSelection(f.get("productId"),"un producto"),fromBranchId=requireSelection(f.get("fromBranchId"),"la sucursal de origen"),toBranchId=requireSelection(f.get("toBranchId"),"la sucursal de destino"),qty=requirePositiveNumber(f.get("qty"),"Cantidad");
  if(fromBranchId===toBranchId)throw new Error("Origen y destino no pueden ser iguales");
  if(isSupabaseConfigured()){
    const result=await RemoteRepo.transferStock({p_product_id:productId,p_from_branch:fromBranchId,p_to_branch:toBranchId,p_qty:qty});
    await pullCoreWorkspace(state());await pullAccounting(state());DB.setSyncStatus("synced");
    DB.log(`Transferencia remota ${result.number} completada`,"CREATE","stock_transfer");
    return;
  }
  return localAtomic("Transferencia",()=>{
  let from=s.inventory.find(i=>i.productId===productId&&i.branchId===fromBranchId);
  let to=s.inventory.find(i=>i.productId===productId&&i.branchId===toBranchId);
  if(!from||from.stock<qty)throw new Error("Stock insuficiente en la sucursal de origen");
  if(!to){to={id:DB.id("i"),productId,branchId:toBranchId,stock:0,reserved:0};s.inventory.push(to)}
  from.stock-=qty;to.stock+=qty;
  const number=nextConfiguredDoc("stockTransfer","TR"),date=new Date().toISOString();
  s.stockTransfers.push({id:DB.id("tr"),number,date,productId,fromBranchId,toBranchId,qty,status:"Completada"});
  s.movements.unshift({id:DB.id("m"),date,type:"TRANSFERENCIA SALIDA",productId,branchId:fromBranchId,qty:-qty,note:number});
  s.movements.unshift({id:DB.id("m"),date,type:"TRANSFERENCIA ENTRADA",productId,branchId:toBranchId,qty,note:number});
  DB.log(`Transferencia ${number} completada`,"CREATE","stock_transfer");DB.save();
  return number;
  });
 });
}
function newQuotation(){
 const s=state();
 modal("Nueva cotización",`
  <div class="field"><label>Cliente</label><select name="customerId">${s.customers.filter(c=>(c.status||"Activo")!=="Inactivo").map(c=>`<option value="${c.id}">${esc(c.name)}</option>`).join("")}</select></div>
  <div class="field"><label>Producto</label><select name="productId">${s.products.filter(p=>(p.status||"Activo")!=="Inactivo").map(p=>`<option value="${p.id}">${esc(p.name)} · $ ${money(p.price)}</option>`).join("")}</select></div>
  ${field("Cantidad","qty","1","number",'min="1"')}${field("Validez (días)","validDays","15","number",'min="1"')}
 `,f=>{
   const p=s.products.find(x=>x.id===f.get("productId")),qty=Number(f.get("qty")),subtotal=qty*Number(p?.price||0),tax=subtotal*Number(p?.tax||0)/100,total=subtotal+tax;
   const number=nextConfiguredDoc("quote","Q"),date=new Date().toISOString(),exp=new Date();exp.setDate(exp.getDate()+Number(f.get("validDays")));
   s.quotations.push({id:DB.id("q"),number,date,expiresAt:exp.toISOString(),customerId:f.get("customerId"),items:[{productId:p.id,qty,price:p.price,tax:p.tax}],subtotal,tax,total,status:"Pendiente"});
   DB.log(`Cotización ${number} creada`,"CREATE","quotation");DB.save();
 });
}
function convertQuoteToSale(id){
 const s=state(),q=s.quotations.find(x=>x.id===id);if(!q)return;if(q.status==="Convertida")return alert("Esta cotización ya fue convertida.");
 cart=q.items.map(i=>{const p=s.products.find(p=>p.id===i.productId);return {productId:i.productId,name:p?.name||"",price:Number(i.price),tax:Number(i.tax),qty:Number(i.qty)}});
 q.status="Convertida";DB.log(`Cotización ${q.number} preparada para venta`,"UPDATE","quotation");current="sales";render();
 setTimeout(()=>{const customer=document.getElementById("saleCustomer");if(customer)customer.value=q.customerId},0);
}

function voidSale(id){
 requirePermission("sales","anular ventas"); sensitiveConfirm("anular una venta");
 const s=state(),sale=s.sales.find(v=>v.id===id);
 if(!sale)return;
 if(sale.status==="Anulada")return alert("La venta ya está anulada.");
 if((s.returns||[]).some(r=>r.saleId===sale.id&&r.status!=="Anulada"))return alert("Esta venta tiene devoluciones. Debes completar el proceso por devoluciones, no por anulación.");
 const creditSale=(sale.paymentCondition||sale.condition)==="credit";
 const receivable=(s.receivables||[]).find(r=>r.reference===sale.number);
 if(creditSale&&receivable&&Number(receivable.balance||0)<Number(receivable.total||sale.total)-0.01)
   return alert("Esta venta a crédito ya tiene cobros aplicados. Para proteger los saldos, usa Devoluciones en lugar de Anular.");
 modal("Anular venta",`
  <div class="notice">ATLAS revertirá inventario, cuentas y contabilidad. Esta acción quedará registrada en auditoría.</div>
  ${field("Motivo","reason","Error de operación")}
  ${!creditSale?`<div class="field"><label>Cuenta para reembolso</label><select name="refundAccountId">${activeCashAccounts().map(a=>`<option value="${a.id}">${esc(a.name)} (${esc(a.currency)})</option>`).join("")}</select></div>
  <div class="field"><label>Método</label><select name="paymentMethodId">${activePaymentMethods().map(m=>`<option value="${m.id}">${esc(m.name)}</option>`).join("")}</select></div>`:""}
 `,f=>{
  const reason=requiredText(f.get("reason"),"Motivo");
  return localAtomic("Anulación de venta",()=>{
   const amount=Number(sale.baseTotalUSD??sale.total||0);
   const subtotal=Number(sale.subtotal??(sale.items||[]).reduce((a,i)=>a+Number(i.price||0)*Number(i.qty||0),0)),tax=Number(sale.tax??Math.max(0,amount-subtotal));
   let totalCost=0;
   for(const item of sale.items||[]){
    let inv=s.inventory.find(i=>i.productId===item.productId&&i.branchId===sale.branchId);
    if(!inv){inv={id:DB.id("i"),productId:item.productId,branchId:sale.branchId,stock:0,reserved:0};s.inventory.push(inv)}
    inv.stock+=Number(item.qty||0);
    const cost=Number(item.cost??s.products.find(p=>p.id===item.productId)?.cost||0)*Number(item.qty||0);
    totalCost+=cost;
    s.movements.unshift({id:DB.id("m"),date:new Date().toISOString(),type:"ANULACIÓN VENTA",productId:item.productId,branchId:sale.branchId,qty:Number(item.qty||0),note:sale.number});
   }
   const lines=[
    {accountId:accountByName("Ventas"),debit:subtotal,credit:0},
    {accountId:accountByName("IVA por pagar"),debit:tax,credit:0}
   ];
   if(creditSale){
    if(receivable){receivable.balance=0;receivable.status="Anulada";receivable.cancelledAt=new Date().toISOString()}
    const c=s.customers.find(x=>x.id===sale.customerId);
    if(c)c.balance=Math.max(0,safeMoney(Number(c.balance||0)-amount));
    lines.push({accountId:accountByName("Cuentas por cobrar"),debit:0,credit:amount});
   }else{
    const accountId=requireSelection(f.get("refundAccountId"),"una cuenta para reembolso");
    const payment=convertedPayment(amount,accountId);
    const pm=f.get("paymentMethodId")||null;
    if(activePaymentMethods().length&&!pm)throw new Error("Selecciona un método para registrar el reembolso.");
    DB.moveCash(accountId,"OUT",payment.amount,`AN-${sale.number}`,`Anulación: ${reason}`,pm,payment.account.currency,payment.rate);
    lines.push({accountId:accountByName("Caja y bancos"),debit:0,credit:amount});
   }
   if(totalCost>0)lines.push(
    {accountId:accountByName("Inventario"),debit:totalCost,credit:0},
    {accountId:accountByName("Costo de ventas"),debit:0,credit:totalCost}
   );
   assertJournalBalanced(lines);
   DB.postJournal(`AN-${sale.number}`,`Anulación de venta · ${reason}`,lines);
   sale.status="Anulada";sale.voidedAt=new Date().toISOString();sale.voidReason=reason;
   DB.log(`Venta ${sale.number} anulada · ${reason}`,"VOID","sale");
   DB.save();
   return sale.number;
  });
 });
}

function newReturn(){
 const s=state(),eligibleSales=(s.sales||[]).filter(v=>v.status!=="Anulada");if(!eligibleSales.length)return alert("No hay ventas activas para devolver.");
 modal("Registrar devolución",`
  <div class="field"><label>Venta</label><select name="saleId">${eligibleSales.map(v=>`<option value="${v.id}">${esc(v.number)} · $ ${money(v.total)}</option>`).join("")}</select></div>
  <div class="field"><label>Producto</label><select name="productId">${s.products.filter(p=>(p.status||"Activo")!=="Inactivo").map(p=>`<option value="${p.id}">${esc(p.name)}</option>`).join("")}</select></div>
  ${field("Cantidad","qty","1","number",'min="1"')}
  <div class="notice">Si la venta fue de contado, selecciona de dónde saldrá el reembolso.</div>
  <div class="field"><label>Cuenta para reembolso</label><select name="refundAccountId"><option value="">— Solo si aplica —</option>${activeCashAccounts().map(a=>`<option value="${a.id}">${esc(a.name)} (${esc(a.currency)})</option>`).join("")}</select></div>
  <div class="field"><label>Método de reembolso</label><select name="refundPaymentMethodId"><option value="">— Solo si aplica —</option>${activePaymentMethods().map(m=>`<option value="${m.id}">${esc(m.name)}</option>`).join("")}</select></div>
 `,async f=>{
  const sale=s.sales.find(v=>v.id===requireSelection(f.get("saleId"),"una venta")),productId=requireSelection(f.get("productId"),"un producto"),qty=requirePositiveNumber(f.get("qty"),"Cantidad");if(!sale)throw new Error("Venta inexistente");if(sale.status==="Anulada")throw new Error("La venta está anulada y no puede recibir devoluciones.");
  if(isSupabaseConfigured()){
    const result=await RemoteRepo.returnSale({p_sale_id:sale.id,p_product_id:productId,p_qty:qty});
    await pullCoreWorkspace(state());await pullTransactions(state());await pullAccounting(state());DB.setSyncStatus("synced");
    DB.log(`Devolución remota ${result.number||sale.number} completada`,"CREATE","return");
    return;
  }
  return localAtomic("Devolución",()=>{
  const sold=sale.items.find(i=>i.productId===productId);if(!sold)throw new Error("Ese producto no pertenece a la venta");
  const already=s.returns.filter(r=>r.saleId===sale.id&&r.productId===productId).reduce((a,r)=>a+r.qty,0);
  if(already+qty>sold.qty)throw new Error("La cantidad devuelta supera la vendida");
  const net=qty*Number(sold.price),taxReturn=net*Number(sold.tax||0)/100,amount=net+taxReturn,costReturn=qty*Number(sold.cost??s.products.find(p=>p.id===productId)?.cost||0),number=nextConfiguredDoc("return","DV"),date=new Date().toISOString();
  let inv=s.inventory.find(i=>i.productId===productId&&i.branchId===sale.branchId);if(!inv){inv={id:DB.id("i"),productId,branchId:sale.branchId,stock:0,reserved:0};s.inventory.push(inv)}inv.stock+=qty;
  const creditSale=(sale.paymentCondition||sale.condition)==="credit";
  const rec=creditSale?reconcileReceivableForReturn({...sale,paymentCondition:"credit"},amount):{arReduction:0,excess:amount};
  if(creditSale&&rec.arReduction>0){
    const c=s.customers.find(c=>c.id===sale.customerId);
    if(c)c.balance=Math.max(0,safeMoney(Number(c.balance||0)-rec.arReduction));
  }
  if(creditSale&&rec.excess>0)addCustomerCredit(sale.customerId,rec.excess,number);
  let refundAccountId=null,refundPaymentMethodId=null,refundAmount=null,refundCurrency=null,refundRate=null;
  if(!creditSale){
    refundAccountId=requireSelection(f.get("refundAccountId"),"una cuenta para el reembolso");
    refundPaymentMethodId=f.get("refundPaymentMethodId")||null;
    if(activePaymentMethods().length)requireSelection(refundPaymentMethodId,"un método de reembolso");
    const refund=convertedPayment(amount,refundAccountId);
    DB.moveCash(refundAccountId,"OUT",refund.amount,number,`Reembolso devolución ${sale.number}`,refundPaymentMethodId,refund.account.currency,refund.rate);
    refundAmount=refund.amount;refundCurrency=refund.account.currency;refundRate=refund.rate;
  }
  s.returns.push({id:DB.id("ret"),number,date,saleId:sale.id,saleNumber:sale.number,productId,qty,net,tax:taxReturn,amount,cost:costReturn,arReduction:rec.arReduction,customerCredit:creditSale?rec.excess:0,refundAccountId,refundPaymentMethodId,refundAmount,refundCurrency,refundRate,status:"Completada"});
  s.movements.unshift({id:DB.id("m"),date,type:"DEVOLUCIÓN",productId,branchId:sale.branchId,qty,note:number});
  const returnLines=[
    {accountId:accountByName("Ventas"),debit:net,credit:0},
    {accountId:accountByName("IVA por pagar"),debit:taxReturn,credit:0}
  ];
  if(creditSale){
    if(rec.arReduction>0)returnLines.push({accountId:accountByName("Cuentas por cobrar"),debit:0,credit:rec.arReduction});
    if(rec.excess>0)returnLines.push({accountId:accountByName("Créditos a clientes"),debit:0,credit:rec.excess});
  }else{
    returnLines.push({accountId:accountByName("Caja y bancos"),debit:0,credit:amount});
  }
  if(costReturn>0)returnLines.push({accountId:accountByName("Inventario"),debit:costReturn,credit:0},{accountId:accountByName("Costo de ventas"),debit:0,credit:costReturn});
  assertJournalBalanced(returnLines);
  DB.postJournal(number,"Devolución de venta",returnLines);
  DB.log(`Devolución ${number} registrada`,"CREATE","return");DB.save();
  return number;
  });
 });
}
function newExpense(){
 const s=state();
 modal("Nuevo gasto",`
  ${field("Categoría","category","Operativo")}${field("Descripción","description","")}
  ${field("Monto","amount","0","number",'min="0.01" step="0.01"')}
  <div class="field"><label>Método de pago</label><select name="paymentMethodId">${activePaymentMethods().map(m=>`<option value="${m.id}">${esc(m.name)}</option>`).join("")}</select></div>
  <div class="field"><label>Cuenta origen</label><select name="accountId">${s.cashAccounts.map(a=>`<option value="${a.id}">${esc(a.name)} (${esc(a.currency)})</option>`).join("")}</select></div>
  ${field("Referencia","reference","")}
 `,async f=>{
  const amount=requirePositiveNumber(f.get("amount"),"Monto"),manualReference=String(f.get("reference")||"").trim(),paymentMethodId=f.get("paymentMethodId")||null;requireSelection(f.get("accountId"),"una cuenta origen");if(activePaymentMethods().length)requireSelection(paymentMethodId,"un método de pago");
  if(isSupabaseConfigured()){
    const result=await RemoteRepo.createExpense({p_cash_account_id:f.get("accountId"),p_category:f.get("category"),p_description:f.get("description"),p_amount:amount,p_reference:manualReference||null});
    await pullTransactions(state());await pullAccounting(state());DB.setSyncStatus("synced");
    DB.log(`Gasto remoto ${result.reference} registrado`,"CREATE","expense");
    return;
  }
  return localAtomic("Gasto",()=>{
  const reference=manualReference||nextConfiguredDoc("expense","G");
  s.expenses.push({id:DB.id("ex"),date:new Date().toISOString(),category:f.get("category"),description:f.get("description"),amount,accountId:f.get("accountId"),paymentMethodId,reference});
  DB.moveCash(f.get("accountId"),"OUT",amount,reference,f.get("description"),paymentMethodId,"USD",latestRateFor("USD"));
  const expAcc=s.chartOfAccounts.find(a=>a.name==="Compras / Gastos")?.id,cashAcc=s.chartOfAccounts.find(a=>a.name==="Caja y bancos")?.id;
  if(expAcc&&cashAcc)DB.postJournal(reference,"Gasto operativo",[{accountId:expAcc,debit:amount,credit:0},{accountId:cashAcc,debit:0,credit:amount}]);
  DB.log(`Gasto ${reference} registrado`,"CREATE","expense");DB.save();
  return reference;
  });
 });
}
function newPaymentMethod(){
 const s=state();
 modal("Nuevo método de pago",`${field("Nombre","name","")}<div class="field"><label>Tipo</label><select name="type"><option value="cash">Efectivo</option><option value="bank">Banco</option><option value="mobile">Pago móvil</option><option value="other">Otro</option></select></div>`,f=>{s.paymentMethods.push({id:DB.id("pm"),name:f.get("name"),type:f.get("type"),active:true});DB.log(`Método de pago creado: ${f.get("name")}`,"CREATE","payment_method");DB.save()});
}
function togglePaymentMethod(id){const m=state().paymentMethods.find(x=>x.id===id);if(!m)return;m.active=!m.active;DB.log(`Método ${m.name}: ${m.active?"activo":"inactivo"}`,"UPDATE","payment_method");DB.save();render()}

function editRolePermissions(id){
 const s=state(),r=s.roles.find(x=>x.id===id);if(!r)return;
 const all=r.permissions.includes("*");
 const checks=PERMISSIONS.map(p=>`<label class="perm-item"><input type="checkbox" name="perm" value="${p}" ${all||r.permissions.includes(p)?"checked":""}> <span>${p}</span></label>`).join("");
 modal(`Permisos · ${esc(r.name)}`,`
  <div class="notice">Administrador puede usar todos los módulos. Para otros roles selecciona solo lo necesario.</div>
  <div class="perm-grid">${checks}</div>
 `,f=>{
   const selected=f.getAll("perm");
   r.permissions = selected.length===PERMISSIONS.length ? ["*"] : selected;
   DB.log(`Permisos actualizados para ${r.name}`,"UPDATE","role");
   DB.save();
 });
}

function saveSettings(e){e.preventDefault();const f=new FormData(e.target),x=state().settings;x.defaultCreditDays=Number(f.get("defaultCreditDays"));x.lowStockAlerts=f.get("lowStockAlerts")==="true";x.allowNegativeStock=f.get("allowNegativeStock")==="true";x.invoiceTaxIncluded=f.get("invoiceTaxIncluded")==="true";DB.log("Configuración general actualizada","UPDATE","settings");DB.save();alert("Configuración guardada");render()}
function downloadBackup(){const blob=new Blob([DB.exportBackup()],{type:"application/json"}),url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download=`ATLAS_respaldo_${new Date().toISOString().slice(0,10)}.json`;a.click();URL.revokeObjectURL(url);DB.log("Respaldo descargado","EXPORT","backup")}
function restoreBackup(){const input=document.getElementById("backupFile"),file=input?.files?.[0];if(!file)return alert("Selecciona un archivo de respaldo.");const reader=new FileReader();reader.onload=()=>{try{if(!confirm("Esto reemplazará los datos actuales. ¿Continuar?"))return;DB.importBackup(reader.result);cart=[];current="dashboard";render();alert("Respaldo restaurado correctamente")}catch(e){alert("No se pudo restaurar: "+e.message)}};reader.readAsText(file)}



async function syncAccountingNow(){
 if(!isSupabaseConfigured())return alert("Supabase todavía no está configurado.");
 DB.setSyncStatus("syncing");render();
 try{const counts=await pullAccounting(state());DB.setSyncStatus("synced");DB.log(`Contabilidad sincronizada: ${counts.entries} asientos`,"SYNC","accounting");alert("Contabilidad sincronizada correctamente.");}
 catch(e){DB.setSyncStatus("error",e.message);alert("No se pudo sincronizar contabilidad: "+e.message);}
 render();
}
async function syncCoreNow(){
 if(!isSupabaseConfigured())return alert("Supabase todavía no está configurado.");
 DB.setSyncStatus("syncing");
 render();
 try{
   const result=await pullCoreWorkspace(state());
   DB.setSyncStatus("synced");
   DB.log(`Sincronización de maestros completada: ${result.counts.customers} clientes, ${result.counts.products} productos`,"SYNC","cloud");
   alert("Maestros sincronizados correctamente.");
 }catch(e){
   DB.setSyncStatus("error",e.message);
   alert("No se pudo sincronizar: "+e.message);
 }
 render();
}
async function syncTransactionsNow(){
 if(!isSupabaseConfigured())return alert("Supabase todavía no está configurado.");
 DB.setSyncStatus("syncing");
 render();
 try{
   const counts=await pullTransactions(state());
   DB.setSyncStatus("synced");
   DB.log(`Sincronización de operaciones completada: ${counts.sales} ventas, ${counts.purchases} compras`,"SYNC","cloud");
   alert("Operaciones sincronizadas correctamente.");
 }catch(e){
   DB.setSyncStatus("error",e.message);
   alert("No se pudo sincronizar: "+e.message);
 }
 render();
}

async function testCloud(){
 if(!isSupabaseConfigured())return alert("ATLAS sigue en modo local. Configura Supabase para probar la nube.");
 DB.setSyncStatus("checking");
 render();
 try{
   const result=await healthCheck();
   if(!result.ok)throw new Error(result.message);
   DB.setSyncStatus("synced");
   alert(`Conexión correcta${result.ms?` · ${result.ms} ms`:""}`);
 }catch(e){
   DB.setSyncStatus("error",e.message);
   alert("Error de conexión: "+e.message);
 }
 render();
}

function manualJournal(){
 const s=state();
 modal("Asiento manual",`
 ${field("Referencia","reference","AJ-"+String(s.journalEntries.length+1).padStart(4,"0"))}
 ${field("Descripción","description","Ajuste contable")}
 <div class="field"><label>Cuenta débito</label><select name="debitAccount">${s.chartOfAccounts.map(a=>`<option value="${a.id}">${esc(a.code)} · ${esc(a.name)}</option>`).join("")}</select></div>
 <div class="field"><label>Cuenta crédito</label><select name="creditAccount">${s.chartOfAccounts.map(a=>`<option value="${a.id}">${esc(a.code)} · ${esc(a.name)}</option>`).join("")}</select></div>
 ${field("Monto","amount","0","number",'step="0.01" min="0.01"')}
 `,f=>{const amount=Number(f.get("amount"));DB.postJournal(f.get("reference"),f.get("description"),[{accountId:f.get("debitAccount"),debit:amount,credit:0},{accountId:f.get("creditAccount"),debit:0,credit:amount}])});
}
function exportReport(){
 const s=state(), rows=[["Tipo","Documento","Fecha","Total"]];
 s.sales.forEach(x=>rows.push(["Venta",x.number,x.date,x.total]));
 s.purchases.forEach(x=>rows.push(["Compra",x.number,x.date,x.total]));
 const csv=rows.map(r=>r.map(v=>`"${String(v??"").replaceAll('"','""')}"`).join(",")).join("\n");
 const blob=new Blob([csv],{type:"text/csv;charset=utf-8"}),url=URL.createObjectURL(blob),a=document.createElement("a");
 a.href=url;a.download="ATLAS_reporte.csv";a.click();URL.revokeObjectURL(url);
 DB.log("Reporte CSV exportado","EXPORT","reports");
}
function printDocument(type,id){
 const s=state(), isSale=type==="sale",doc=(isSale?s.sales:s.purchases).find(x=>x.id===id);if(!doc)return;
 const party=isSale?s.customers.find(x=>x.id===doc.customerId):s.suppliers.find(x=>x.id===doc.supplierId);
 const items=doc.items||[];
 const rows=items.map(i=>{const p=s.products.find(x=>x.id===i.productId);const qty=Number(i.qty||0),unit=Number(isSale?i.price:i.cost);return `<tr><td>${esc(p?.name||"")}</td><td>${qty}</td><td>$ ${money(unit)}</td><td>$ ${money(qty*unit)}</td></tr>`}).join("");
 const w=window.open("","_blank","width=800,height=700");
 w.document.write(`<!doctype html><html><head><title>${esc(doc.number)}</title><style>body{font-family:Arial;padding:35px;color:#172033}h1{letter-spacing:.12em;margin-bottom:2px}.muted{color:#667085}.box{border:1px solid #ddd;border-radius:10px;padding:14px;margin:18px 0}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:9px;border-bottom:1px solid #ddd}.total{text-align:right;font-size:22px;font-weight:bold;margin-top:20px}</style></head><body>
 <h1>ATLAS</h1><div class="muted">Sistema de Gestión Empresarial</div>
 <div class="box"><strong>${isSale?"COMPROBANTE DE VENTA":"COMPROBANTE DE COMPRA"} ${esc(doc.number)}</strong><br>Fecha: ${datefmt(doc.date)}<br>${isSale?"Cliente":"Proveedor"}: ${esc(party?.name||"")}</div>
 <table><thead><tr><th>Producto</th><th>Cant.</th><th>Precio</th><th>Total</th></tr></thead><tbody>${rows}</tbody></table>
 <div class="total">TOTAL: $ ${money(doc.total)}</div><p class="muted">${esc(s.documentSettings.footer)}</p>
 <script>window.onload=()=>window.print()<\/script></body></html>`);
 w.document.close();
 DB.log(`Documento ${doc.number} enviado a impresión`,"PRINT","documents");
}

if("serviceWorker" in navigator){window.addEventListener("load",()=>navigator.serviceWorker.register("./sw.js").catch(()=>{}))}
render();

function runIntegrityAudit(){
 const s=state(),issues=[];
 const ids=a=>new Set((a||[]).map(x=>x.id));
 const branches=ids(s.branches),products=ids(s.products),customers=ids(s.customers),suppliers=ids(s.suppliers);
 for(const i of s.inventory||[]){
  if(!branches.has(i.branchId))issues.push(`Inventario ${i.id}: sucursal inexistente`);
  if(!products.has(i.productId))issues.push(`Inventario ${i.id}: producto inexistente`);
  if(Number(i.stock)<0&&!s.settings?.allowNegativeStock)issues.push(`Inventario ${i.id}: stock negativo`);
 }
 for(const x of s.sales||[]){
  if(x.branchId&&!branches.has(x.branchId))issues.push(`Venta ${x.number||x.id}: sucursal inexistente`);
  if(x.customerId&&!customers.has(x.customerId))issues.push(`Venta ${x.number||x.id}: cliente inexistente`);
  if(!Number.isFinite(Number(x.total)))issues.push(`Venta ${x.number||x.id}: total inválido`);
 }
 for(const x of s.purchases||[]){
  if(x.branchId&&!branches.has(x.branchId))issues.push(`Compra ${x.number||x.id}: sucursal inexistente`);
  if(x.supplierId&&!suppliers.has(x.supplierId))issues.push(`Compra ${x.number||x.id}: proveedor inexistente`);
 }
 const paymentIds=new Set((s.paymentMethods||[]).map(x=>x.id));
 for(const m of s.cashMovements||[])if(m.paymentMethodId&&!paymentIds.has(m.paymentMethodId))issues.push(`Movimiento ${m.reference||m.id}: método de pago inexistente`);
 for(const a of s.cashAccounts||[])
  if(Number(a.balance)<0&&!s.settings?.allowNegativeCash)issues.push(`Caja ${a.name}: saldo negativo`);
 for(const c of s.customerCredits||[]){
  if(Number(c.balance)<0)issues.push(`Crédito cliente ${c.reference||c.id}: saldo negativo`);
  if(c.customerId&&!customers.has(c.customerId))issues.push(`Crédito cliente ${c.reference||c.id}: cliente inexistente`);
 }
 for(const c of s.customerCredits||[]){
  if(Number(c.balance)>Number(c.amount||0)+0.01)issues.push(`Crédito cliente ${c.reference||c.id}: saldo mayor al crédito original`);
 }
 for(const r of s.returns||[]){
  const sale=(s.sales||[]).find(v=>v.id===r.saleId);
  if(!sale)issues.push(`Devolución ${r.number||r.id}: venta inexistente`);
  if(r.refundAccountId){
    const a=(s.cashAccounts||[]).find(x=>x.id===r.refundAccountId);
    if(!a)issues.push(`Devolución ${r.number||r.id}: cuenta de reembolso inexistente`);
  }
 }
 for(const v of s.sales||[]){
  if(v.status==="Anulada"&&(s.returns||[]).some(r=>r.saleId===v.id&&r.status!=="Anulada"))issues.push(`Venta ${v.number}: anulada pero conserva devoluciones activas`);
 }
 const saleNums=new Set();
 for(const x of s.sales||[]){
  const n=x.number||x.documentNumber;
  if(n&&saleNums.has(n))issues.push(`Número de venta duplicado: ${n}`);
  else if(n)saleNums.add(n);
 }
 const purchaseNums=new Set();
 for(const x of s.purchases||[]){
  const n=x.number||x.documentNumber;
  if(n&&purchaseNums.has(n))issues.push(`Número de compra duplicado: ${n}`);
  else if(n)purchaseNums.add(n);
 }
 const supported=new Set((s.supportedCurrencies||["USD","VES","EUR","USDT"]).map(x=>String(x).toUpperCase()));
 for(const a of s.cashAccounts||[])if(!supported.has(String(a.currency||"").toUpperCase()))issues.push(`Caja ${a.name}: moneda no válida`);
 for(const r of s.exchangeRates||[])if(!Number.isFinite(Number(r.rate))||Number(r.rate)<=0)issues.push(`Tasa ${r.currency||r.id}: valor inválido`);
 for(const v of s.sales||[])if(!supported.has(String(v.currency||"USD").toUpperCase()))issues.push(`Documento de venta ${v.number}: moneda no válida`);
 for(const p of s.purchases||[])if(!supported.has(String(p.currency||"USD").toUpperCase()))issues.push(`Documento de compra ${p.number}: moneda no válida`);
 for(const m of s.cashMovements||[]){
   const acc=(s.cashAccounts||[]).find(a=>a.id===m.accountId);
   if(acc&&m.currency&&String(acc.currency).toUpperCase()!==String(m.currency).toUpperCase())issues.push(`Movimiento ${m.reference}: moneda distinta a su cuenta`);
 } 
 for(const t of s.cashTransfers||[]){
  if(t.fromAccountId===t.toAccountId)issues.push(`Transferencia financiera ${t.reference||t.id}: misma cuenta origen y destino`);
  if(!(s.cashAccounts||[]).some(a=>a.id===t.fromAccountId))issues.push(`Transferencia financiera ${t.reference||t.id}: cuenta origen inexistente`);
  if(!(s.cashAccounts||[]).some(a=>a.id===t.toAccountId))issues.push(`Transferencia financiera ${t.reference||t.id}: cuenta destino inexistente`);
  if(Number(t.fromAmount)<=0||Number(t.toAmount)<=0)issues.push(`Transferencia financiera ${t.reference||t.id}: monto inválido`);
 }
 for(const c of s.cashClosings||[]){
  if(!(s.cashAccounts||[]).some(a=>a.id===c.accountId))issues.push(`Cierre ${c.number||c.id}: cuenta inexistente`);
  const expected=safeMoney(Number(c.countedBalance||0)-Number(c.systemBalance||0));
  if(Math.abs(expected-Number(c.difference||0))>0.01)issues.push(`Cierre ${c.number||c.id}: diferencia inconsistente`);
 }
 for(const r of s.cashReconciliations||[]){
  if(!(s.cashClosings||[]).some(c=>c.id===r.closingId))issues.push(`Conciliación ${r.id}: cierre inexistente`);
 } 
 for(const c of s.supplierCredits||[]){
  if(Number(c.balance)<0)issues.push(`Crédito proveedor ${c.reference||c.id}: saldo negativo`);
  if(Number(c.balance)>Number(c.amount||0)+0.01)issues.push(`Crédito proveedor ${c.reference||c.id}: saldo mayor al crédito original`);
  if(c.supplierId&&!suppliers.has(c.supplierId))issues.push(`Crédito proveedor ${c.reference||c.id}: proveedor inexistente`);
 }
 for(const r of s.purchaseReturns||[]){
  const p=(s.purchases||[]).find(x=>x.id===r.purchaseId);
  if(!p)issues.push(`Devolución compra ${r.number||r.id}: compra inexistente`);
  if(Number(r.qty||0)<=0)issues.push(`Devolución compra ${r.number||r.id}: cantidad inválida`);
 }
 for(const p of s.purchases||[]){
  if(p.status==="Anulada"&&(s.purchaseReturns||[]).some(r=>r.purchaseId===p.id&&r.status!=="Anulada"))issues.push(`Compra ${p.number}: anulada pero conserva devoluciones activas`);
 }


 const accountIds=new Set((s.chartOfAccounts||[]).map(a=>a.id));
 for(const e of s.journalEntries||[]){
  for(const l of e.lines||[])if(!accountIds.has(l.accountId))issues.push(`Asiento ${e.reference||e.id}: cuenta contable inexistente`);
  const d=(e.lines||[]).reduce((n,l)=>n+Number(l.debit||0),0);
  const h=(e.lines||[]).reduce((n,l)=>n+Number(l.credit||0),0);
  if(Math.abs(d-h)>.009)issues.push(`Asiento ${e.reference||e.id}: descuadrado`);
 }
 return issues;
}
window.ATLAS_DIAGNOSTICO=()=>{
 const issues=runIntegrityAudit();
 console.table(issues.length?issues:["Sin inconsistencias detectadas"]);
 return issues;
};
