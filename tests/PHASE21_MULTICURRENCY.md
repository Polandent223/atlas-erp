# ATLAS Fase 21 — Documento y pago en monedas distintas

Caso cubierto:
- la venta puede estar expresada en USD, VES, EUR o USDT;
- el valor contable interno permanece en USD para no romper inventario, CxC/CxP ni asientos existentes;
- una venta USD puede cobrarse en una cuenta VES;
- ATLAS convierte el monto con la tasa registrada;
- una compra puede pagarse desde una cuenta de moneda diferente;
- cobros de CxC y pagos de CxP pueden liquidarse con cuentas USD, VES, EUR o USDT;
- el movimiento de caja guarda la moneda real de la cuenta y la tasa usada;
- el documento guarda su moneda, total visible y total base USD.

Supabase sigue reservado para el final.
