# Conexión de ATLAS con Supabase — Fase 32

1. Crear un proyecto nuevo en Supabase.
2. Abrir SQL Editor.
3. Ejecutar `sql/ATLAS_PRODUCTION_PHASE32.sql`.
4. Crear el primer usuario en Authentication.
5. Crear la empresa, perfil, rol Administrador y sucursal inicial.
6. Colocar en `assets/config.js` únicamente la URL del proyecto y la clave pública anon/publishable.
7. Probar login y aislamiento de empresa/sucursal.
8. Migrar los datos locales solo después de validar el respaldo.

No colocar `service_role`, contraseñas SMTP ni otras claves privadas en el frontend.
