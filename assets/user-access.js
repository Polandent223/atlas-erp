import { RemoteRepo } from "./repositories.js";

export const allBranches = role => (role?.permissions || []).some(p => p === "*" || p === "branches.all");
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function accessArgs(snapshot, input){
  if(!uuid.test(input.userId || "")) throw new Error("Introduce el UUID de la cuenta de Authentication.");
  const role = snapshot.roles.find(r => r.id === input.roleId);
  if(!role) throw new Error("Selecciona un rol de esta empresa.");
  const branches = [...new Set(input.branchIds || [])];
  if(!allBranches(role) && !branches.length) throw new Error("Selecciona al menos una sucursal.");
  if(branches.some(id => !snapshot.branches.some(b => b.id === id && b.active !== false))) throw new Error("Sucursal inválida o inactiva.");
  return {p_user_id:input.userId,p_role_id:role.id,p_branch_ids:allBranches(role)?[]:branches,p_active:input.active !== false};
}

export async function loadUserAccess(repo = RemoteRepo){
  const snapshot = await repo.rpc("atlas_access_snapshot");
  if(!snapshot || !Array.isArray(snapshot.users) || !Array.isArray(snapshot.roles) || !Array.isArray(snapshot.branches)){
    throw new Error("No se pudo cargar el directorio de usuarios. Actualiza la conexión de ATLAS.");
  }
  return snapshot;
}

export async function saveUserAccess(snapshot, input, repo = RemoteRepo){
  const args = accessArgs(snapshot, input);
  if(input.link){
    const name = String(input.name || "").trim();
    if(!name) throw new Error("Nombre requerido.");
    if(snapshot.users.some(u => u.id === input.userId)) throw new Error("Esta cuenta ya está vinculada; usa Editar acceso.");
    return repo.rpc("atlas_link_auth_user", {...args,p_full_name:name});
  }
  if(!snapshot.users.some(u => u.id === input.userId)) throw new Error("Usuario no encontrado en esta empresa.");
  return repo.rpc("atlas_assign_user_access", args);
}
