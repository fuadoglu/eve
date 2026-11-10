"""OpenAPI komponent JSON Schema-ları və müsbət/mənfi kontrakt nümunələri.

Bu yoxlama route-un işlədiyini və ya DB təhlükəsizliyini sübut etmir.
"""
import json
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate_spec

root=Path(__file__).resolve().parent.parent
doc=json.loads((root/'docs/03-engineering/openapi.json').read_text())
validate_spec(doc)
schemas=doc['components']['schemas']
for name,schema in schemas.items():
    Draft202012Validator.check_schema(schema)
count=0
for example in doc.get('x-contract-examples',[]):
    assert example['schema'] in schemas, example['schema']
    wrapped={'$ref':'#/components/schemas/'+example['schema'],'components':doc['components']}
    validator=Draft202012Validator(wrapped,format_checker=FormatChecker())
    errors=list(validator.iter_errors(example['value']))
    actual=not errors
    assert actual==example['valid'], f"{example['schema']}: expected valid={example['valid']}; errors={[e.message for e in errors]}"
    count+=1
assert count>=4,'Müsbət və mənfi kontrakt nümunələri tələb olunur'
print(f'JSON Schema OK: {len(schemas)} schemas; {count} positive/negative examples. Application tests not run.')
