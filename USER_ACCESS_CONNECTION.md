# Usuarios conectados a Supabase

En modo nube, Administración → Usuarios consulta `atlas_access_snapshot` y muestra el correo real para distinguir perfiles con el mismo nombre. Vincular cuenta requiere una identidad existente en Authentication y llama a `atlas_link_auth_user`. Editar acceso usa `atlas_assign_user_access` para asignar rol, sucursales y estado. No utiliza PIN locales ni claves administrativas en el navegador.

La SQL de `sql/ATLAS_USER_ACCESS_CONNECTION.sql` se instaló en el proyecto atlas-erp. Mantiene controles de sesión, empresa y permiso `settings.manage`/`*`, limita el directorio para usuarios normales, rechaza sucursales inválidas o vacías en roles restringidos y evita que un administrador se desactive o retire su propio acceso administrativo.

## Verificación

- `node tests/user-access-runtime.mjs`: selección de RPC, validación, propagación de errores y alcance de sucursales.
- `node tests/runtime52-dashboard.mjs` y `python tests/validate.py`: comprobaciones existentes.
- `tests/user-access-integration.sql`: ejecutado en Supabase con fixtures temporales y ROLLBACK. Verifica vinculación, edición, aislamiento y rechazos; los perfiles originales permanecen intactos.
- `tests/user-access-browser.mjs`: prueba preparada de formularios y lista a 390 px con RPC simuladas. No ejecutada: Chromium no estaba instalado y su descarga devolvió un archivo inválido. Requiere servidor local en 8765 y Playwright; la revisión visual sigue pendiente.

Esto conecta cuentas ya creadas. Crear credenciales desde ATLAS requiere una función administrativa de servidor; el proyecto todavía no tiene Edge Functions. Las pruebas SQL y de interfaz no equivalen a iniciar sesión con una nueva cuenta real.

Los advisors también marcan funciones privilegiadas accesibles a `authenticated`. Estas tres RPC mantienen deliberadamente ese acceso para funcionar desde ATLAS y validan sesión, empresa y permisos internamente. Persisten avisos anteriores de search_path en otras funciones; este cambio no certifica la seguridad de todo el ERP.
