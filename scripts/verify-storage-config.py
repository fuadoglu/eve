"""Check D33/D34 machine mapping against local Supabase bucket/API configuration."""

import json
import tomllib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
dictionary = json.loads((root / 'docs/03-engineering/data-dictionary.json').read_text())
with (root / 'supabase/config.toml').open('rb') as handle:
    config = tomllib.load(handle)

mapping = dictionary['storage']['bucket_by_classification']
classifications = dictionary['enums']['media_classification']['values']
assert set(mapping) == set(classifications), 'classification mapping differs from enum'
assert len(set(mapping.values())) == len(mapping), 'bucket IDs are not one-to-one'
assert dictionary['storage']['all_buckets_private'] is True
assert config['api']['schemas'] == ['api'], 'Data API must expose only api'
assert set(config['storage']['buckets']) == set(mapping.values()), 'bucket declarations differ'
for bucket_id in mapping.values():
    assert config['storage']['buckets'][bucket_id]['public'] is False, bucket_id

media = next(table for table in dictionary['tables'] if table['name'] == 'media_assets')
check = next(item for item in media['checks'] if item['name'] == 'media_bucket_classification')
expected = ' OR '.join(
    f"(classification='{classification}' AND bucket='{bucket_id}')"
    for classification, bucket_id in mapping.items()
)
assert check['enforcement'] == 'CHECK' and check['expression'] == expected, 'DB CHECK differs'
print(f"Storage config OK: api-only; {len(mapping)} private buckets and DB CHECK align with D33/D34.")
