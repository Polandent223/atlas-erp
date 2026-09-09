# Publicar ATLAS en GitHub Pages

1. Crea un repositorio y sube ATLAS a la rama `main`.
2. Abre **Settings → Pages**.
3. En **Build and deployment**, selecciona **GitHub Actions**.
4. El archivo `.github/workflows/deploy.yml` publicará ATLAS automáticamente.
5. Cada actualización de la rama `main` volverá a desplegar el sistema.

Antes de usar datos reales configura Supabase en `assets/config.js` y ejecuta el SQL de la fase actual.

Nunca coloques `service_role`, contraseñas privadas ni secretos en GitHub.
