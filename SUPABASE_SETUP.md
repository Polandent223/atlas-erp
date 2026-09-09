# Conectar ATLAS con Supabase

1. Crea un proyecto gratuito en Supabase.
2. Abre SQL Editor y ejecuta `sql/schema_phase6.sql`.
3. En Authentication crea el primer usuario administrador.
4. Inserta la empresa, rol administrador y perfil asociado al `auth.users.id`.
5. Copia únicamente:
   - Project URL
   - anon public key
6. Abre `assets/config.js`:
   - `mode: "supabase"`
   - pega `supabaseUrl`
   - pega `supabaseAnonKey`
7. Publica ATLAS en GitHub Pages.
8. En **Sistema y nube** pulsa **Probar conexión**.

## Seguridad
No uses `service_role` en el navegador. No guardes contraseñas SMTP, claves privadas ni tokens administrativos dentro del repositorio.

## Estado de Fase 6
La autenticación remota y la capa de seguridad están preparadas. La demo local sigue disponible mientras no se configuren credenciales. La migración de todas las operaciones del estado local a CRUD remoto completo se realizará sobre esta base, sin cambiar el diseño funcional.
