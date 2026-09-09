# ATLAS — Puerta de salida a producción

ATLAS no se considera listo para uso real hasta cerrar estos puntos.

## Bloques cerrados en rama de endurecimiento
- Contabilidad atómica preparada para venta, compra, cobro CxC y pago CxP.
- Validación de asiento balanceado y cuentas activas.
- Validación de stock, permisos, empresa y sucursal.
- Contrato multi-moneda: no se permiten conversiones cruzadas inferidas con una sola tasa.
- Healthcheck monetario para cuentas y tasas.

## Bloqueos todavía abiertos
- Integrar el contrato FX directamente en todos los RPC de caja antes de desplegar F55/F56.
- Devolución de venta remota: inventario + crédito/reembolso + reverso contable + auditoría.
- Devolución de compra remota: inventario + crédito proveedor/reembolso + reverso contable + auditoría.
- Anulación remota de venta/compra con protección contra doble reverso.
- Gastos remotos con asiento automático y conversión de caja consistente.
- Transferencias entre cuentas en monedas distintas con dos snapshots de tasa explícitos.
- Transferencia de inventario con auditoría e idempotencia.
- Prueba integral real contra Supabase antes de fusionar a main.

## Regla
No fusionar esta rama a `main` mientras exista un bloqueo crítico abierto. El diseño visual final se hará después del cierre funcional.
