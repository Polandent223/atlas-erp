# ATLAS Fase 23 — Control de caja

## Transferencias
Una transferencia genera una salida en la cuenta origen y una entrada en la cuenta destino. Si las monedas son diferentes, se convierte usando las tasas guardadas.

## Cierre
El usuario informa el dinero realmente contado. ATLAS guarda el saldo esperado, el contado y la diferencia sin modificar el saldo automáticamente.

## Conciliación
Una diferencia pendiente requiere un motivo. ATLAS crea el ajuste financiero, registra la conciliación y genera un asiento contable balanceado.

## Seguridad
Todos los pasos críticos están dentro de `DB.atomic()`, por lo que un fallo revierte la operación completa.
