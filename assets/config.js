export const CONFIG = {
  // "local" mantiene la demo sin servicios externos.
  // "supabase" activa autenticación y sincronización remota.
  mode: "supabase",
  supabaseUrl: "https://fytleoumhkykhdzxwetk.supabase.co",
  supabaseAnonKey: "sb_publishable_3hvR4TIzEpAG_kBgulFwXA_Ak2JhPOQ",
  appName: "ATLAS",
  appSubtitle: "Sistema de Gestión Empresarial",
  syncIntervalMs: 15000
};

export const isSupabaseConfigured = () =>
  CONFIG.mode === "supabase" &&
  /^https:\/\/.+\.supabase\.co$/.test(CONFIG.supabaseUrl) &&
  CONFIG.supabaseAnonKey.length > 20;

// Fase 32: configuración segura del cliente.
// Solo URL y clave pública anon/publishable. NUNCA service_role.
if(typeof window!=="undefined") window.ATLAS_CLOUD_MODE = window.ATLAS_CLOUD_MODE || "local";
