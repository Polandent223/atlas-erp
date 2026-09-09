# ATLAS Fase 33 — Migración e inicio de sesión real

ATLAS ahora genera un paquete de migración validado sin contraseñas ni PIN locales.

Cuando llegue el momento de conectar:
1. Crear proyecto Supabase.
2. Ejecutar `sql/ATLAS_PRODUCTION_PHASE32.sql`.
3. Crear el primer usuario en Authentication.
4. Ejecutar `sql/ATLAS_BOOTSTRAP_FIRST_ADMIN_PHASE33.sql` reemplazando empresa, RIF y UUID.
5. Configurar solo URL + clave pública en ATLAS.
6. Verificar login.
7. Importar el paquete de migración con el proceso controlado de la siguiente etapa.
8. Comparar conteos antes/después antes de habilitar uso real.

Nunca migrar PIN locales como contraseñas.
