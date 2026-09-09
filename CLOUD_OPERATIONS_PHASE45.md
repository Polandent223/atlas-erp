# ATLAS · Operaciones cloud

Fase 45 mueve las operaciones de mayor riesgo a RPC transaccionales PostgreSQL:

- crear venta;
- crear compra;
- cobrar CxC;
- pagar CxP.

Cada RPC valida empresa, permiso, sucursal y referencias, y ejecuta los cambios relacionados como una sola transacción. Si falla una parte, PostgreSQL revierte toda la operación.

La aplicación local sigue funcionando mientras Supabase no esté conectado. El cambio definitivo a modo cloud se realiza durante el montaje final.
