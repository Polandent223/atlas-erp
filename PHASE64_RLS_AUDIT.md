# ATLAS — Fase 64: auditoría RLS multiempresa

Verificación realizada contra el proyecto Supabase de producción.

## Resultado
- RLS activo en tablas críticas operativas, financieras y contables.
- Clientes, proveedores, productos, CxC, CxP, caja, gastos y contabilidad quedan aislados por `current_company_id()`.
- Ventas, compras e inventario añaden control de sucursal mediante `can_access_branch(...)`.
- Líneas de venta/compra heredan el aislamiento a través de sus documentos padre.
- Líneas contables heredan el aislamiento mediante `journal_entries`.
- Escrituras administrativas requieren permisos específicos donde corresponde.

## Tablas verificadas
`branches`, `company_settings`, `customers`, `suppliers`, `products`, `inventory`, `sales`, `sale_items`, `purchases`, `purchase_items`, `receivables`, `payables`, `cash_accounts`, `cash_movements`, `expenses`, `accounting_accounts`, `journal_entries`, `journal_lines`.

Estado: **APROBADO para aislamiento multiempresa**.
