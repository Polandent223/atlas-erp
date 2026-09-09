import {runIntegralAudit} from "./integral-audit.js";
import {runWorkflowAudit} from "./workflow-audit.js";
import {buildMigrationPackage,validateMigrationPackage} from "./migration.js";
import {buildImportPlan,validateImportPlan} from "./cloud-import.js";
import {validateReferences} from "./migration-mapper.js";
export function releaseReadiness(state){
 const structural=runIntegralAudit(state),workflow=runWorkflowAudit(state);
 const pkg=buildMigrationPackage(state),pkgv=validateMigrationPackage(pkg),refs=validateReferences(pkg);
 let plan={ok:false,errors:["No generado"]};
 try{plan=validateImportPlan(buildImportPlan(pkg))}catch(e){plan={ok:false,errors:[e.message]}}
 const gates=[
  {name:"Integridad estructural",ok:structural.ok,detail:`${structural.score}%`},
  {name:"Flujos entre módulos",ok:workflow.ok,detail:`${workflow.score}%`},
  {name:"Paquete de migración",ok:pkgv.ok,detail:pkgv.ok?"Válido":(pkgv.errors||[]).join("; ")},
  {name:"Relaciones de migración",ok:refs.ok,detail:refs.ok?"Válidas":refs.errors.slice(0,3).join("; ")},
  {name:"Plan de importación",ok:plan.ok,detail:plan.ok?"Válido":(plan.errors||[]).join("; ")}
 ];
 return {ready:gates.every(x=>x.ok),gates,structural,workflow};
}
