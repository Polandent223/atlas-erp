# ATLAS — Migración Fase 8

## Cuando se active Supabase
1. Ejecutar `sql/schema_phase8.sql`.
2. Crear empresa, rol, perfil y sucursales.
3. Configurar `assets/config.js` con URL pública + anon key.
4. Iniciar sesión desde ATLAS.
5. Ir a Sistema y nube y probar conexión.
6. Sincronizar maestros.
7. Probar una venta pequeña y confirmar inventario/caja.
8. Probar compra, CxC y CxP.
9. Revisar Auditoría.

Las operaciones críticas se realizan en funciones PostgreSQL transaccionales para evitar que el navegador haga una operación a medias.
