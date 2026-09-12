# ATLAS Fase 55 — Revisión transaccional

Estado: **en revisión, no desplegar todavía**.

## Corregido en esta fase

- Ventas: inventario, caja/CxC, costo de venta, asiento contable y auditoría quedan dentro de una sola transacción PostgreSQL.
- Compras: inventario, caja/CxP, IVA crédito, asiento contable y auditoría quedan dentro de una sola transacción.
- Cobros CxC: actualizan deuda, caja, contabilidad y auditoría atómicamente.
- Pagos CxP: actualizan deuda, caja, contabilidad y auditoría atómicamente.
- Se valida que subtotal + impuesto = total.
- Se valida stock, sucursal, cliente/proveedor, cuenta financiera y permisos antes de confirmar.
- Se bloquea escritura directa de asientos para usuarios autenticados; el motor usa funciones seguras.
- Se asegura el plan contable mínimo requerido sin borrar cuentas existentes.

## Hallazgo importante pendiente

La interfaz F53 todavía trata los precios operativos como referencia USD aunque permita seleccionar otra moneda documental. Antes de declarar multi-moneda lista para producción hay que unificar la semántica de `exchange_rate`, importe documental e importe de la cuenta financiera. No se debe ocultar este punto ni marcar ATLAS como listo hasta corregirlo.

## Criterio de aprobación

No fusionar esta rama a `main` hasta revisar el contrato frontend ↔ RPC y completar las operaciones remotas que aún tengan lógica exclusivamente local (devoluciones, transferencias, gastos, anulaciones y créditos según corresponda).
