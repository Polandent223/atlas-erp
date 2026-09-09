import fs from "node:fs";
const app=fs.readFileSync("assets/app.js","utf8");
const data=fs.readFileSync("assets/data.js","utf8");
const match=app.match(/import\s*\{([^}]+)\}\s*from\s*["']\.\/data\.js["']/);
if(!match) throw new Error("No se encontró import desde data.js");
const names=match[1].split(",").map(x=>x.trim()).filter(Boolean);
for(const n of names){
 const exported=new RegExp(`export\\s+(?:const|let|var|function|class)\\s+${n}\\b`).test(data);
 if(!exported) throw new Error(`data.js no exporta ${n}`);
}
console.log("ATLAS Fase 18 module contract OK:",names.join(", "));
