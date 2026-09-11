# ATLAS — Orden de migración F55 → F70

Este orden está diseñado para ejecutarse después de la base productiva F32/F44 ya instalada. No fusionar a `main` ni ejecutar parcialmente en producción real.

## Orden exacto

1. `ATLAS_TRANSACTIONAL_ACCOUNTING_PHASE55.sql`
2. `ATLAS_MULTICURRENCY_CONTRACT_PHASE56.sql`
3. `ATLAS_OPERATIONS_HARDENING_PHASE57.sql`
4. `ATLAS_RETURNS_PHASE58.sql`
5. `ATLAS_PURCHASE_RETURNS_PHASE59.sql`
6. `ATLAS_CANCELLATIONS_PHASE60.sql`
7. `ATLAS_MULTICURRENCY_RPCS_PHASE61.sql`
8. `ATLAS_MASTER_DATA_PHASE62.sql`
9. `ATLAS_ADMIN_OPERATIONS_PHASE64.sql`
10. `ATLAS_CONFIGURATION_PHASE65.sql`
11. `ATLAS_ACCESS_CONTROL_PHASE66.sql`
12. `ATLAS_CASH_CONTROL_PHASE68.sql`
13. `ATLAS_FX_CASH_HARDENING_PHASE69.sql`
14. `ATLAS_FINANCIAL_INTEGRITY_PHASE70.sql`

Las fases 63 y 67 son principalmente integración de interfaz y no contienen una migración SQL independiente. Las correcciones posteriores hechas sobre F58/F59/F60/F64 ya están incorporadas en esos mismos archivos y por eso no deben aplicarse versiones antiguas de ellos.

## Dependencias importantes

- F55 debe existir antes de F57–F70 porque define `atlas_post_journal` y la base contable.
- F56 define el contrato FX que F61 y F69 respetan.
- F58/F59 requieren las tablas operativas de F44 y la contabilidad de F55.
- F60 requiere los asientos de F55 y debe instalarse antes de la validación final de anulaciones.
- F61 reemplaza las versiones transaccionales anteriores con el contrato multimoneda definitivo.
- F62 añade campos de maestros usados por la sincronización actual.
- F64 usa `document_counters` de F44, pero desde F70 genera su secuencia de ajuste directamente para no heredar permisos de ventas/compras.
- F68 crea `cash_transfers` y amplía `cash_closings`.
- F69 reemplaza `atlas_cash_transfer` con validación FX más estricta y añade gastos multimoneda.
- F70 se ejecuta al final porque inspecciona la estructura y coherencia resultante.

## Códigos contables reservados

- `1.1.01` Caja y bancos
- `1.1.02` Cuentas por cobrar
- `1.1.03` Inventario
- `1.1.04` IVA crédito fiscal
- `1.1.05` Créditos de proveedores
- `2.1.01` Cuentas por pagar
- `2.1.02` IVA por pagar
- `2.1.03` Créditos de clientes
- `4.1.01` Ventas
- `5.1.01` Costo de ventas
- `5.2.01` Gastos operativos
- `5.2.02` Ajustes y diferencias de caja
- `5.2.03` Ajustes de inventario

## Validación antes del instalador único

Antes de generar el SQL consolidado se debe comprobar que ningún archivo vuelva a definir una función posterior con una versión antigua y que no haya colisiones de códigos contables, firmas RPC o políticas RLS. El instalador único debe respetar exactamente este orden.
