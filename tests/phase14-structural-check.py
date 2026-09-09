from pathlib import Path
s=Path('sql/ATLAS_FRESH_INSTALL_PHASE14.sql').read_text(encoding='utf-8')
required=['create table companies','create table sales','create table journal_entries',
'atlas_create_sale','atlas_create_purchase','atlas_return_sale','enable row level security',
'security_invoker=true']
for x in required:
    assert x in s, x
print('ATLAS Fase 14: estructura SQL limpia OK')
