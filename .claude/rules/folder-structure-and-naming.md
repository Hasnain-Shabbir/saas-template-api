---
paths:
  - "app/**"
  - "db/**"
  - "spec/**"
---

# Folder structure and naming

Put code in the folder that owns it. Use the same domain name in every layer (for example `accounts` in the type, mutation, service (with its query object), policy, and job).

```
app/
  graphql/
    saas_template_api_schema.rb      limits, introspection, error mapping
    concerns/                   authentication, helpers shared by operations
    types/                      one file per type (base_*.rb are generated bases)
    mutations/<domain>/         one file per mutation, in a domain folder: accounts/, memberships/, auth/ (BaseMutation is Relay classic)
    queries/<domain>/           one file per query field, in a domain folder: users/, email_logs/ (BaseQuery is a GraphQL::Schema::Resolver; query_type.rb only lists the fields)
  services/<domain>/            use cases that return a Result, and the query objects next to them (SearchQuery: filter and order, returns a relation)
  policies/                     one policy per resource, default deny
  models/                       data rules only (concerns/ small and rare)
  jobs/<domain>/                thin jobs, arguments are ids
  mailers/
  lib/                          shared, reusable classes that are not tied to one domain (Paginator)
db/migrate/                     one change per migration
spec/                           mirrors app/ (see testing.md)
```

## Naming
- GraphQL operations: `<Verb><Noun>` in PascalCase (`CreateAccount`, `UpdateOrganization`). The name is part of the contract with any client.
- Services: `Domain::VerbNoun` (`Accounts::Create`), one public method `call`.
- Jobs: `Domain::VerbNounJob`. Policies: `<Model>Policy`. Query objects: `Domain::<Thing>Query`.
- File and class names mirror each other (Zeitwerk). Test paths mirror `app/` paths.

## Do not
- Create `app/helpers` (view helpers, unused in this API) or catch-all `Utils` or `Helpers` modules. `app/lib` is allowed for shared, reusable classes, but each one is named for what it does (`Paginator`), not `Utils`.
- Create a top-level `app/queries/`. A query object lives in `services/<domain>/`, so a domain stays in one folder (and `queries/` keeps meaning GraphQL query fields).
- Put a service in `models/` or a model concern in `services/`.
- Add a top-level folder without a reason written in the README or a decision note.
