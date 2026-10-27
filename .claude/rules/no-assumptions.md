# Do not assume. Ask first.

Never assume business rules, scope, roles, or what data means.

## Ask before writing code when
- A task is ambiguous or the requirement is incomplete (list what is missing and ask).
- Two approaches are valid (present both, give a recommendation, ask which).
- The change affects business logic, permissions, tenancy, data retention, or what a client sees.
- Existing code conflicts with the task, or a change could have side effects elsewhere.

## Do not
- Pick a file, name, or design silently when several are plausible.
- Decide a business rule "because it seems reasonable". Ask the owner.
- Refactor or add extras that were not requested.

## Example
- Bad: "add a field to accounts" then adding a column, a type field, and a policy rule without asking.
- Good: ask which role may see it, whether it is sensitive (sensitive), and whether it can be empty.
