---
paths:
  - "app/**"
  - "db/**"
  - "spec/**"
---

# Architecture: layers and who may call whom

```
GraphQL (types, mutations)          thin: parse input, authenticate, authorize, call a service, shape output
        |
Application services                one use case each: business rules, transaction, returns a Result
        |
Models + query objects + policies   data rules | read, filter, search | who may do what
        |
PostgreSQL                          constraints are the last line of defence
```

Jobs and mailers call services. Nothing calls "up" the diagram.

## Rules
- GraphQL classes only parse input, require login, call a policy, call **one** service, and shape the output. No business logic, no multi-step queries, no external calls in them.
- A service owns one use case and its transaction. It returns a `Result` (success with a value, or failure with a stable `code`). It does not build GraphQL errors.
- Models hold data rules (validations, associations, simple scopes). No external calls and no email sending in callbacks.
- Jobs load records by id and call a service. They never contain business rules.
- Tenancy: every query starts from `current_organization`. Never a global `Model.find`.

