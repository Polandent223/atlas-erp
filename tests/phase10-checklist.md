# ATLAS Fase 10 — pruebas de integridad

- Desactivar y reactivar clientes, proveedores, productos y sucursales sin borrar historial.
- Impedir desactivar el usuario con la sesión abierta.
- Crear una nueva sucursal y comprobar que recibe filas de inventario para todos los productos.
- Rechazar SKU repetido.
- Rechazar códigos repetidos de clientes/proveedores.
- Rechazar tasa cero o negativa.
- Rechazar stock negativo cuando la configuración no lo permite.
- Ocultar maestros inactivos de los formularios operativos.
- Confirmar que ventas/compras históricas siguen visibles.
- Ejecutar `sql/schema_phase10.sql` al activar Supabase.
