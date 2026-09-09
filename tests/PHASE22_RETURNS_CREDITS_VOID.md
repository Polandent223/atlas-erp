# ATLAS Fase 22 — Devoluciones, créditos y anulaciones

- Devolución de contado genera una salida real de la cuenta seleccionada.
- El reembolso admite cuentas USD, VES, EUR o USDT mediante conversión.
- Devoluciones de crédito reducen CxC y, si sobra importe, crean crédito a favor.
- CxC muestra créditos a favor del cliente.
- Un crédito puede aplicarse a una deuda posterior sin movimiento de caja.
- La aplicación del crédito genera asiento contable.
- Una venta puede anularse solo bajo condiciones seguras.
- Si una venta a crédito ya tiene cobros, ATLAS bloquea la anulación directa y exige usar devolución.
- Si existen devoluciones activas, también bloquea la anulación total.
- Una anulación válida repone inventario y revierte contabilidad.
