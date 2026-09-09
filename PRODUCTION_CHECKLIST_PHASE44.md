# ATLAS · Lista de montaje seguro

1. Crear proyecto nuevo de Supabase.
2. Ejecutar primero `ATLAS_PRODUCTION_PHASE32.sql`.
3. Ejecutar `ATLAS_SECURITY_HARDENING_PHASE44.sql`.
4. Crear el primer usuario administrador desde Supabase Auth.
5. Asociar su `profile`, empresa, rol y sucursal.
6. Configurar en ATLAS únicamente URL pública del proyecto y `anon key`.
7. Nunca colocar `service_role`, contraseña SMTP ni claves privadas en GitHub/JavaScript.
8. Ejecutar prueba de sesión y dry-run de migración.
9. Comparar conteos local/nube.
10. Solo después habilitar importación real y publicar GitHub Pages.

ATLAS no considera la nube activa únicamente porque exista una URL: debe validar sesión, empresa y alcance.
