# ATLAS — Puerta de salida a producción

ATLAS no se considera listo para uso real hasta cerrar esta puerta y completar la prueba integral contra Supabase.

## Bloques cerrados en la rama F55–F73
- Contabilidad atómica para venta, compra, cobro CxC y pago CxP.
- Validación de asiento balanceado, cuentas activas, empresa y sucursal.
- Contrato monetario USD de referencia con snapshots FX explícitos.
- Devoluciones remotas de venta/compra con inventario, CxC/CxP o créditos, contabilidad y auditoría.
- Anulaciones remotas de ventas/compras con bloqueo ante cobros, pagos o devoluciones incompatibles.
- Transferencias de inventario remotas y auditables.
- Creación remota de maestros, sucursales, métodos de pago, tasas y cuentas financieras.
- Usuarios/roles/permisos para perfiles ya existentes sin exponer privilegios de Supabase Auth en el navegador.
- Transferencias entre cuentas con monto origen/destino, base USD, tasas explícitas y bloqueo determinista para concurrencia.
- Cierre y conciliación de caja remotos.
- Aplicación remota de créditos de clientes y proveedores conservando monto original y saldo disponible.
- Gastos multimoneda con monto físico, equivalente USD y tasa validada por servidor.
- Diagnóstico financiero integral preparado en servidor.
- Ajustes de inventario separados contablemente de diferencias de caja: `5.2.03` vs `5.2.02`.
- Numeración interna segura para caja/créditos/gastos y numeración propia para ajustes de inventario.
- Instalador consolidado `ATLAS_INSTALLER_F55_F73.sql` generado automáticamente en orden de dependencias.
- Preflight + verificación estructural final dentro de una sola transacción SQL.
- Validación automática exitosa en PostgreSQL 16 ejecutando F32 + F44 + instalador consolidado completo.
- Service Worker actualizado a caché `atlas-v73` e incluye los módulos remotos actuales.

## Bloqueos todavía abiertos antes de producción
- Ejecutar el instalador consolidado una sola vez en el proyecto real de Supabase y guardar el resultado.
- Ejecutar diagnóstico financiero/estructural después de instalar y corregir cualquier hallazgo real.
- Probar en nube los flujos críticos de punta a punta: venta contado/crédito, cobro, compra contado/crédito, pago, devoluciones, anulaciones, inventario, caja, gastos, transferencias y conciliación.
- Verificar edición remota de maestros/configuración y estados activo/inactivo donde aplique.
- Revisar alta segura de nuevos usuarios Auth; no se habilitará mediante `service_role` en el frontend.
- Revisar reportes/documentos impresos después de los cambios contables y multimoneda.
- Revisión final del PR y comparación completa `main` ↔ `atlas-f55-review`.

## Regla de salida
No fusionar esta rama a `main` mientras exista un bloqueo crítico abierto. La rama `atlas-backup-pre-f55` permanece intacta como respaldo. El rediseño visual final se hará después del cierre funcional y de la prueba real en nube.
