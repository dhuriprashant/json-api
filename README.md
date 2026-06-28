# Apex JSON:API Framework

A configuration-driven Apex framework that exposes Salesforce SObjects over a REST
API conforming to the [JSON:API v1.1 specification](https://jsonapi.org/format/).

Describe each SObject once (its type name, fields, and relationships) and the
framework handles routing, CRUD, sparse fieldsets, sorting, filtering, pagination,
compound documents (`include`), content negotiation, and spec-compliant errors —
all enforced under the running user's CRUD/FLS via `AccessLevel.USER_MODE`.

> 📖 **Usage reference** (endpoints, query params, examples, how to add a resource):
> [`force-app/main/default/classes/JSON-API-README.md`](force-app/main/default/classes/JSON-API-README.md)
> 🏗️ **Technical design** (architecture, request lifecycle, internals, security):
> [`docs/TECHNICAL.md`](docs/TECHNICAL.md)

---

## Status

- ⚠️ **Read-only:** GET-only framework; `POST`/`PATCH`/`DELETE` are not supported
  and return `405`.
- ✅ **Validated:** Apex tests passing with healthy org-wide coverage (clean scratch org).
- ✅ **Deployed & confirmed live** — GET (sparse fieldsets, pagination, `include`
  compound documents) and error responses verified against a real org.

---

## What it does

| Capability            | Example                                                        |
|-----------------------|----------------------------------------------------------------|
| Read (GET)            | `GET /{type}` and `GET /{type}/{id}` _(writes gated off for now → 405)_ |
| Relationships         | `GET /{type}/{id}/{relationship}` and `.../relationships/{rel}`|
| Compound documents    | `?include=parent,contacts` (supports nested, e.g. `contacts.account`) |
| Attribute groups      | `?extend=financials,contactInfo` (opt into extra groups beyond `base`) |
| Sparse fieldsets      | `?fields[accounts]=name,industry`                              |
| Sorting               | `?sort=-annualRevenue,name`                                    |
| Filtering             | `?filter[industry]=Technology`                                |
| Pagination            | `?page[size]=10&page[number]=2` or `?page[limit]=10&page[offset]=20` |
| Content negotiation   | `application/vnd.api+json` (415 / 406 enforcement)            |
| Error documents       | Spec-compliant `errors[]` with HTTP status, code, source pointer |

Two example resources ship out of the box: **`accounts`** (Account) and
**`contacts`** (Contact).

---

## Quick start

### Deploy

```powershell
# Authenticate (once)
sf org login web --alias my-org --set-default

# Deploy the framework
sf project deploy start -d force-app -o my-org

# Run the framework's tests
sf apex run test -o my-org -l RunSpecifiedTests `
  -t JsonApiServiceTest -t JsonApiRequestParserTest `
  -t JsonApiRestResourceTest -t JsonApiCoverageTest -c
```

### Call it

The API is served under `/services/apexrest/jsonapi`.

```bash
curl "$INSTANCE_URL/services/apexrest/jsonapi/accounts?fields[accounts]=name,industry&page[size]=10" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/vnd.api+json"
```

```json
{
  "jsonapi": { "version": "1.1" },
  "meta": { "total": 9 },
  "links": { "self": "...", "first": "...", "next": "...", "last": "..." },
  "data": [
    { "type": "accounts", "id": "001...",
      "attributes": { "name": "Acme", "industry": "Technology" },
      "links": { "self": "/services/apexrest/jsonapi/accounts/001..." } }
  ]
}
```

### Manual testing

Ready-to-run request collections covering every endpoint and option for both
example resources (reads, writes, includes, `extend`, pagination, error cases):

- [`docs/manual-tests.http`](docs/manual-tests.http) — for the VS Code **REST Client**
  extension (`humao.rest-client`); click "Send Request" above any request.
- [`docs/JsonApi.postman_collection.json`](docs/JsonApi.postman_collection.json) —
  import into **Postman**.

Both expose a `token` variable: set it to a fresh access token from
`sf org display -o <org> --json` (`result.accessToken`). Tokens are short-lived —
refresh when you start getting `401`s, and never commit a real token.

---

## Adding a resource

1. Create a `JsonApiResourceConfig` subclass mapping a JSON:API type to an SObject,
   with attributes organized into groups (see `AccountResourceConfig` /
   `ContactResourceConfig`).
2. Add a `JsonApiResource__mdt` Custom Metadata record pointing at that class — no
   framework code change needed.

That's it — the new type is live. Full walkthrough in the
[framework README](force-app/main/default/classes/JSON-API-README.md#adding-a-new-resource).

---

## Project layout

- `sfdx-project.json` — Salesforce DX configuration
- `config/project-scratch-def.json` — scratch org definition
- `docs/TECHNICAL.md` — detailed technical/architecture documentation
- `force-app/main/default/classes/` — the framework (23 classes) + tests + docs
- `force-app/main/default/objects/JsonApiResource__mdt/` — the resource-registration Custom Metadata Type
- `force-app/main/default/customMetadata/` — one `JsonApiResource` record per exposed resource
