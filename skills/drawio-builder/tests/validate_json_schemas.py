import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator


def main() -> int:
    skill = Path(sys.argv[1]).resolve()
    schemas = skill / "schemas"
    fixtures = skill / "scripts" / "fixtures" / "infrastructure"
    index = json.loads((fixtures / "schema-fixtures.json").read_text(encoding="utf-8"))
    failures = []
    checked_schemas = set()
    for item in index["fixtures"]:
        schema_path = schemas / item["schema"]
        document_path = fixtures / item["document"]
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        document = json.loads(document_path.read_text(encoding="utf-8"))
        if schema_path not in checked_schemas:
            Draft202012Validator.check_schema(schema)
            checked_schemas.add(schema_path)
        errors = list(Draft202012Validator(schema).iter_errors(document))
        observed = not errors
        if observed != item["valid"]:
            failures.append({
                "schema": item["schema"],
                "document": item["document"],
                "expectedValid": item["valid"],
                "errors": [error.message for error in errors],
            })
    profile_fixture_root = skill / "scripts" / "fixtures" / "profiles"
    profile_index = json.loads((profile_fixture_root / "index.json").read_text(encoding="utf-8"))
    notation_schema_path = schemas / "notation-profile.schema.json"
    contract_schema_path = schemas / "diagram-contract.schema.json"
    notation_schema = json.loads(notation_schema_path.read_text(encoding="utf-8"))
    contract_schema = json.loads(contract_schema_path.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(notation_schema)
    Draft202012Validator.check_schema(contract_schema)
    checked_schemas.update((notation_schema_path, contract_schema_path))
    checked_profiles = set()
    for profile_path in sorted((skill / "profiles").glob("*.json")):
        profile = json.loads(profile_path.read_text(encoding="utf-8"))
        profile_errors = list(Draft202012Validator(notation_schema).iter_errors(profile))
        if profile_errors:
            failures.append({
                "schema": "notation-profile.schema.json",
                "document": str(profile_path.relative_to(skill)),
                "expectedValid": True,
                "errors": [error.message for error in profile_errors],
            })
        checked_profiles.add(profile_path)
    for item in profile_index["fixtures"]:
        profile_path = skill / item["profile"]
        manifest_path = profile_fixture_root / item["manifest"]
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest_errors = list(Draft202012Validator(contract_schema).iter_errors(manifest))
        observed = not manifest_errors
        if observed != item["expectedSchemaValid"]:
            failures.append({
                "schema": "diagram-contract.schema.json",
                "document": str(manifest_path.relative_to(skill)),
                "expectedValid": item["expectedSchemaValid"],
                "errors": [error.message for error in manifest_errors],
            })
    print(json.dumps({
        "schemaCount": len(checked_schemas),
        "fixtureCount": len(index["fixtures"]) + len(profile_index["fixtures"]),
        "profileCount": len(checked_profiles),
        "failureCount": len(failures),
        "failures": failures,
    }))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
