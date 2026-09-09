# ATLAS Fase 24 — Compras y proveedores

## Devolución de compra
Reduce inventario y revierte el costo/IVA correspondiente. Si la compra fue a crédito, baja la cuenta por pagar; si sobra valor, crea un crédito de proveedor.

## Crédito de proveedor
Puede aplicarse a otra cuenta por pagar del mismo proveedor sin mover dinero de caja.

## Compra de contado
La devolución registra una entrada real en la cuenta elegida, incluso si la cuenta usa otra moneda.

## Anulación
Solo se permite cuando es seguro hacerlo. Si la compra ya tiene pagos parciales o devoluciones activas, ATLAS obliga a usar el flujo correcto en vez de anular.

## Integridad
Los procesos críticos permanecen dentro de `DB.atomic()`.
