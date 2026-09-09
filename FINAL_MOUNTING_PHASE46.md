# ATLAS · Montaje final

La aplicación ya contiene un interruptor protegido Local/Nube.

El modo nube NO puede activarse solo por pegar una URL o una clave pública. Primero ATLAS exige:
1. Supabase configurado.
2. Usuario autenticado.
3. Perfil asociado a una empresa.
4. `current_user_scope`/alcance válido.
5. Verificación del destino cloud.

Después de esa comprobación el administrador puede activar modo nube. También existe regreso inmediato a modo local.

GitHub Pages queda preparado mediante `.github/workflows/deploy-pages.yml`.

Para el despliegue real todavía hacen falta los datos del proyecto Supabase y acceso al repositorio GitHub del propietario. Esos datos no se inventan ni se guardan en el ZIP.
