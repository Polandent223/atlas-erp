import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES+'/package.json');
const {chromium}=require('playwright');
const browser=await chromium.launch({headless:true});
const page=await browser.newPage({viewport:{width:390,height:844}});
const errors=[];page.on('pageerror',e=>errors.push(e.message));
let alertText='';page.on('dialog',async d=>{alertText=d.message();await d.accept();});
try{
 await page.goto('http://127.0.0.1:8765');
 await page.evaluate(async()=>{
  const {DB}=await import('/assets/data.js');
  DB.setRemoteSession({id:'00000000-0000-0000-0000-000000000001',full_name:'Administrador',email:'admin@example.invalid',status:'ACTIVE',role_id:'00000000-0000-0000-0000-000000000002',role:{id:'00000000-0000-0000-0000-000000000002',name:'Administrador',permissions:['*']},branch_ids:[],branches:[]});
 });
 await page.reload();
 await page.evaluate(async()=>{
  const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
  window.accessCalls=[];
  window.accessSnapshot={users:[{id:id(1),name:'Administrador Principal',email:'admin@example.invalid',status:'ACTIVE',role_id:id(2),branch_ids:[]},{id:id(7),name:'Administrador Principal',email:'other@example.invalid',status:'ACTIVE',role_id:id(3),branch_ids:[id(5)]}],roles:[{id:id(2),name:'Administrador',permissions:['*']},{id:id(3),name:'Ventas',permissions:['dashboard']}],branches:[{id:id(5),name:'Valencia',active:true},{id:id(6),name:'Maracay',active:true}]};
  const {RemoteRepo}=await import('/assets/repositories.js');
  RemoteRepo.rpc=async(name,args)=>{
   if(name==='atlas_access_snapshot')return structuredClone(window.accessSnapshot);
   window.accessCalls.push({name,args});
   await new Promise(r=>setTimeout(r,50));
   if(name==='atlas_link_auth_user')window.accessSnapshot.users.push({id:args.p_user_id,name:args.p_full_name,email:'new@example.invalid',status:args.p_active?'ACTIVE':'INACTIVE',role_id:args.p_role_id,branch_ids:args.p_branch_ids});
   else Object.assign(window.accessSnapshot.users.find(u=>u.id===args.p_user_id),{role_id:args.p_role_id,branch_ids:args.p_branch_ids,status:args.p_active?'ACTIVE':'INACTIVE'});
   return {id:args.p_user_id};
  };
 });
 await page.locator('[data-nav="controlCenter"]').click();
 await page.locator('[data-nav="users"]').click();
 await page.getByText('other@example.invalid',{exact:true}).waitFor();
 assert.equal(await page.locator('[data-user-access]').count(),2);
 assert.equal(await page.locator('body').evaluate(el=>el.scrollWidth<=innerWidth),true,'Mobile page overflows');
 await page.locator('[data-user-access]').nth(1).click();
 await page.locator('#modalForm').waitFor();
 await page.locator('[name="branchIds"]:checked').uncheck();
 await page.locator('#modalForm button[type="submit"], #modalForm button:not([type])').click();
 assert.match(alertText,/al menos una sucursal/);
 assert.equal(await page.evaluate(()=>accessCalls.length),0);
 await page.locator('[name="branchIds"]').nth(1).check();
 await page.locator('[name="active"]').uncheck();
 await page.locator('#modalForm').evaluate(form=>{form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));});
 await page.locator('#modalForm').waitFor({state:'detached'});
 assert.equal(await page.evaluate(()=>accessCalls.length),1,'Duplicate submit');
 assert.equal(await page.evaluate(()=>accessCalls[0].args.p_active),false);
 await page.locator('[data-add="user"]').click();
 await page.locator('[name="userId"]').fill('00000000-0000-0000-0000-000000000008');
 await page.locator('[name="name"]').fill('Nuevo usuario');
 assert.equal(await page.locator('#accessBranches').isDisabled(),true,'All-branch role');
 await page.locator('#modalForm button:not([type])').click();
 await page.locator('#modalForm').waitFor({state:'detached'});
 await page.getByText('new@example.invalid',{exact:true}).waitFor();
 assert.equal(await page.evaluate(()=>accessCalls.at(-1).name),'atlas_link_auth_user');
 assert.deepEqual(errors,[]);
 console.log('Browser mobile directory, edit, validation, duplicate-submit protection and link PASS (mock RPC)');
}finally{await browser.close();}
