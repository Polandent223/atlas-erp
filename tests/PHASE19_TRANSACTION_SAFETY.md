# ATLAS Fase 19 — Seguridad transaccional local

Objetivo: una operación debe completarse entera o no dejar cambios a medias.

Revisado:
- venta;
- compra;
- cobro de CxC;
- pago de CxP;
- transferencia de inventario;
- devolución;
- gasto.

Se añadieron validaciones para selecciones obligatorias, números positivos y montos no negativos. Si una etapa crítica falla, `DB.atomic()` restaura el estado previo para evitar inventarios, saldos o documentos incompletos.

Supabase sigue reservado para el final.
