import fs from "node:fs";
const a=fs.readFileSync("assets/app.js","utf8");
for(const x of ["atlasBackup:true","formatVersion:1","schemaVersion:s.schemaVersion","validateBackupEnvelope","Este respaldo pertenece a una versión futura","La restauración reemplazará los datos locales actuales"])
 if(!a.includes(x))throw new Error("Contrato de recuperación faltante: "+x);
console.log("ATLAS Fase 31 recovery contract OK");
