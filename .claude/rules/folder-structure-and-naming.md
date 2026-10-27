---
paths:
  - "app/**"
  - "db/**"
  - "spec/**"
---

# Folder structure and naming

Put code in the folder that owns it. Use the same domain name in every layer (for example `accounts` in the type, mutation, service, query object, policy, and job).

```
app/
  graphql/
    saas_template_api_schema.rb      limits, introspection, error mapping
    concerns/                   authentication, helpers shared by operations
    types/                      one file per type (base_*.rb are generated bases)
    mutations/<domain>/         one file per mutation, in a domain folder: accounts/, memberships/, auth/ (BaseMutation is Relay classic)
    resolvers/                  query resolvers when a query outgrows query_type.rb
  services/<domain>/            use cases that return a Result      (target, not created yet)
  queries/<domain>/             query objects: filter, search, paginate   (target)
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
- Put a service in `models/` or a model concern in `services/`.
- Add a top-level folder without a reason written in the README or a decision note.
