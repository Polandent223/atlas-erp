# ATLAS — Instalación limpia de Supabase

Cuando terminemos ATLAS y llegue el momento de conectarlo, usa **un proyecto Supabase nuevo**.

1. Abre el SQL Editor de Supabase.
2. Ejecuta `sql/ATLAS_FRESH_INSTALL_PHASE14.sql`.
3. Crea el primer usuario en Authentication.
4. Crea empresa, rol Administrador y perfil del usuario.
5. Configura `assets/config.js` con Project URL y anon key.
6. Nunca uses `service_role` en el navegador o GitHub.

Este archivo reemplaza la necesidad de ejecutar uno por uno los SQL de Fase 2 a Fase 13.
