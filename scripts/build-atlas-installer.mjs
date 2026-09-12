import { readFileSync, writeFileSync } from 'node:fs';

const phases = [
  'sql/ATLAS_TRANSACTIONAL_ACCOUNTING_PHASE55.sql',
  'sql/ATLAS_MULTICURRENCY_CONTRACT_PHASE56.sql',
  'sql/ATLAS_OPERATIONS_HARDENING_PHASE57.sql',
  'sql/ATLAS_RETURNS_PHASE58.sql',
  'sql/ATLAS_PURCHASE_RETURNS_PHASE59.sql',
  'sql/ATLAS_CANCELLATIONS_PHASE60.sql',
  'sql/ATLAS_MULTICURRENCY_RPCS_PHASE61.sql',
  'sql/ATLAS_MASTER_DATA_PHASE62.sql',
  'sql/ATLAS_ADMIN_OPERATIONS_PHASE64.sql',
  'sql/ATLAS_CONFIGURATION_PHASE65.sql',
  'sql/ATLAS_ACCESS_CONTROL_PHASE66.sql',
  'sql/ATLAS_CASH_CONTROL_PHASE68.sql',
  'sql/ATLAS_FX_CASH_HARDENING_PHASE69.sql',
  'sql/ATLAS_FINANCIAL_INTEGRITY_PHASE70.sql'
];

const header = `-- ============================================================\n-- ATLAS — INSTALADOR CONSOLIDADO F55 → F73\n-- Base requerida: F32 + F44 ya instaladas.\n-- Generado automáticamente desde las fases revisadas de la rama.\n-- REGLA: ejecutar el archivo completo; no ejecutar fragmentos.\n-- Toda la migración corre en una sola transacción.\n-- ============================================================\n\nbegin;\n\n-- Preflight estructural: aborta antes de modificar si falta la base esperada.\ndo $$\ndeclare missing text[] := array[]::text[];\nbegin\n  if to_regclass('public.companies') is null then missing:=array_append(missing,'companies'); end if;\n  if to_regclass('public.profiles') is null then missing:=array_append(missing,'profiles'); end if;\n  if to_regclass('public.branches') is null then missing:=array_append(missing,'branches'); end if;\n  if to_regclass('public.products') is null then missing:=array_append(missing,'products'); end if;\n  if to_regclass('public.inventory') is null then missing:=array_append(missing,'inventory'); end if;\n  if to_regclass('public.cash_accounts') is null then missing:=array_append(missing,'cash_accounts'); end if;\n  if to_regclass('public.sales') is null then missing:=array_append(missing,'sales'); end if;\n  if to_regclass('public.purchases') is null then missing:=array_append(missing,'purchases'); end if;\n  if to_regclass('public.receivables') is null then missing:=array_append(missing,'receivables'); end if;\n  if to_regclass('public.payables') is null then missing:=array_append(missing,'payables'); end if;\n  if to_regclass('public.document_counters') is null then missing:=array_append(missing,'document_counters'); end if;\n  if to_regprocedure('public.current_company_id()') is null then missing:=array_append(missing,'current_company_id()'); end if;\n  if to_regprocedure('public.has_permission(text)') is null then missing:=array_append(missing,'has_permission(text)'); end if;\n  if to_regprocedure('public.can_access_branch(uuid)') is null then missing:=array_append(missing,'can_access_branch(uuid)'); end if;\n  if cardinality(missing)>0 then\n    raise exception 'ATLAS preflight falló. Falta base F32/F44: %', array_to_string(missing,', ');\n  end if;\nend $$;\n\n`;

const footer = `\n-- ============================================================\n-- Verificación estructural final. Si algo falta, toda la transacción revierte.\n-- ============================================================\ndo $$\ndeclare missing text[] := array[]::text[];\nbegin\n  if to_regclass('public.cash_transfers') is null then missing:=array_append(missing,'cash_transfers'); end if;\n  if to_regprocedure('public.atlas_post_journal(uuid,text,text,jsonb)') is null then missing:=array_append(missing,'atlas_post_journal'); end if;\n  if to_regprocedure('public.atlas_fx_amount(numeric,text,text,numeric)') is null then missing:=array_append(missing,'atlas_fx_amount'); end if;\n  if to_regprocedure('public.atlas_create_sale(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text)') is null then missing:=array_append(missing,'atlas_create_sale'); end if;\n  if to_regprocedure('public.atlas_create_purchase(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text)') is null then missing:=array_append(missing,'atlas_create_purchase'); end if;\n  if to_regprocedure('public.atlas_return_sale(uuid,uuid,numeric)') is null then missing:=array_append(missing,'atlas_return_sale'); end if;\n  if to_regprocedure('public.atlas_return_purchase(uuid,uuid,numeric)') is null then missing:=array_append(missing,'atlas_return_purchase'); end if;\n  if to_regprocedure('public.atlas_cancel_sale(uuid,text)') is null then missing:=array_append(missing,'atlas_cancel_sale'); end if;\n  if to_regprocedure('public.atlas_cancel_purchase(uuid,text)') is null then missing:=array_append(missing,'atlas_cancel_purchase'); end if;\n  if to_regprocedure('public.atlas_cash_transfer(uuid,uuid,numeric,numeric,numeric,numeric,numeric,text,text)') is null then missing:=array_append(missing,'atlas_cash_transfer'); end if;\n  if to_regprocedure('public.atlas_cash_close(uuid,numeric,text)') is null then missing:=array_append(missing,'atlas_cash_close'); end if;\n  if to_regprocedure('public.atlas_create_expense_fx(uuid,text,text,numeric,numeric,numeric,text)') is null then missing:=array_append(missing,'atlas_create_expense_fx'); end if;\n  if to_regprocedure('public.atlas_financial_integrity_check()') is null then missing:=array_append(missing,'atlas_financial_integrity_check'); end if;\n  if cardinality(missing)>0 then\n    raise exception 'ATLAS verificación final falló: %', array_to_string(missing,', ');\n  end if;\nend $$;\n\ncommit;\n\n-- Fin del instalador consolidado ATLAS F55 → F73.\n`;

const blocks = phases.map((path, index) => {
  const sql = readFileSync(path, 'utf8').replace(/^\uFEFF/, '').trim();
  return `-- ============================================================\n-- BLOQUE ${index + 1}/${phases.length}: ${path}\n-- ============================================================\n${sql}\n`;
});

const out = header + blocks.join('\n') + footer;
writeFileSync('sql/ATLAS_INSTALLER_F55_F73.sql', out, 'utf8');
console.log(`ATLAS installer generated: ${out.length} chars from ${phases.length} phase files.`);
