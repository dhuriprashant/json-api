# Apex JSON:API Framework

A small, configuration-driven framework that exposes Salesforce SObjects over a
REST API conforming to the [JSON:API v1.1 specification](https://jsonapi.org/format/).

You describe each SObject once (its type name, fields, and relationships) and the
framework handles routing, CRUD, sparse fieldsets, sorting, filtering, pagination,
compound documents (`include`), content negotiation and spec-compliant errors.

All data access runs in `AccessLevel.USER_MODE`, so object- and field-level
security is enforced by the platform for the running user.

---

## Endpoints

Everything is served under `/services/apexrest/jsonapi`.

| Method   | Path                                       | Action                       |
|----------|--------------------------------------------|------------------------------|
| `GET`    | `/{type}`                                  | List a collection            |
| `GET`    | `/{type}/{id}`                             | Fetch one resource           |
| `GET`    | `/{type}/{id}/{relationship}`              | Fetch related resource(s)    |
| `GET`    | `/{type}/{id}/relationships/{relationship}`| Fetch relationship linkage   |
| `POST`   | `/{type}`                                  | Create                       |
| `PATCH`  | `/{type}/{id}`                             | Update                       |
| `DELETE` | `/{type}/{id}`                             | Delete                       |

### Supported query parameters

| Parameter            | Example                              | Notes                                   |
|----------------------|--------------------------------------|-----------------------------------------|
| `include`            | `?include=parent,contacts`           | Comma-separated; supports nested paths (`contacts.account`) |
| `fields[TYPE]`       | `?fields[accounts]=name,phone`       | Sparse fieldsets, per type              |
| `sort`               | `?sort=-annualRevenue,name`          | `-` prefix = descending                 |
| `filter[ATTR]`       | `?filter[industry]=Technology`       | Equality; multiple filters are AND-ed   |
| `page[size]`,`page[number]` | `?page[size]=10&page[number]=2`| Page-based pagination                    |
| `page[limit]`,`page[offset]`| `?page[limit]=10&page[offset]=20`| Offset-based pagination                 |

---

## Example requests

**List, sorted and filtered, with only two fields:**

```
GET /services/apexrest/jsonapi/accounts?filter[industry]=Technology&sort=-name&fields[accounts]=name,industry
Accept: application/vnd.api+json
```

**Fetch one account and side-load its parent:**

```
GET /services/apexrest/jsonapi/accounts/001.../?include=parent
```

```json
{
  "jsonapi": { "version": "1.1" },
  "data": {
    "type": "accounts",
    "id": "001...",
    "attributes": { "name": "Acme", "industry": "Technology" },
    "relationships": {
      "parent": {
        "links": { "self": ".../relationships/parent", "related": ".../parent" },
        "data": { "type": "accounts", "id": "001PARENT..." }
      }
    },
    "links": { "self": "/services/apexrest/jsonapi/accounts/001..." }
  },
  "included": [
    { "type": "accounts", "id": "001PARENT...", "attributes": { "name": "Parent Co" } }
  ]
}
```

**Create:**

```
POST /services/apexrest/jsonapi/accounts
Content-Type: application/vnd.api+json

{ "data": { "type": "accounts", "attributes": { "name": "New Co", "industry": "Finance" } } }
```

Returns `201 Created` with a `Location` header and the created resource.

**Errors** are returned as a JSON:API error document with the matching HTTP status:

```json
{ "jsonapi": { "version": "1.1" },
  "errors": [ { "status": "404", "code": "NOT_FOUND", "title": "Resource Not Found",
                "detail": "No accounts with id \"001...\"." } ] }
```

---

## Adding a new resource

1. Create a config that extends `JsonApiResourceConfig`:

```apex
public with sharing class OpportunityResourceConfig extends JsonApiResourceConfig {
    public override String getType() { return 'opportunities'; }
    public override Schema.SObjectType getSObjectType() { return Opportunity.SObjectType; }
    public override Map<String, String> getAttributeMap() {
        return new Map<String, String>{
            'name' => 'Name', 'stage' => 'StageName', 'amount' => 'Amount'
        };
    }
    public override Map<String, JsonApiRelationshipDef> getRelationships() {
        return new Map<String, JsonApiRelationshipDef>{
            'account' => JsonApiRelationshipDef.toOne('account', 'accounts', 'AccountId')
        };
    }
    // Optional: lock down which attributes may be written.
    public override Set<String> getWritableAttributes() {
        return new Set<String>{ 'name', 'stage', 'amount' };
    }
}
```

2. Register it in `JsonApiBootstrap.registerAll()`:

```apex
JsonApiRegistry.register(new OpportunityResourceConfig());
```

That's it — the new type is live at `/services/apexrest/jsonapi/opportunities`.

---

## Architecture

| Layer            | Classes                                                                |
|------------------|-----------------------------------------------------------------------|
| HTTP entry point | `JsonApiRestResource`                                                  |
| Orchestration    | `JsonApiService`, `JsonApiResponse`                                    |
| Configuration    | `JsonApiResourceConfig`, `JsonApiRelationshipDef`, `JsonApiRegistry`, `JsonApiBootstrap` |
| Request parsing  | `JsonApiRequestParser`, `JsonApiQueryOptions`                         |
| Data access      | `JsonApiQueryBuilder`, `JsonApiIncludeResolver`                       |
| (De)serialization| `JsonApiSerializer`, `JsonApiDeserializer`                            |
| Document model   | `JsonApiDocument`, `JsonApiResourceObject`, `JsonApiResourceIdentifier`, `JsonApiRelationship`, `JsonApiError`, `JsonApiErrorSource` |
| Errors           | `JsonApiException`                                                     |
| Constants        | `JsonApiConstants`                                                     |

### Security
- All SOQL/DML use `USER_MODE`, enforcing CRUD/FLS automatically.
- Object and field names in generated SOQL come only from configs, never from
  user input; all filter values are passed as bind variables — no SOQL injection.
- Only attributes in `getWritableAttributes()` can be set on create/update.

### Known limitations / extension points
- `include` populates the top-level `included` array and to-one linkage; to-many
  linkage inside primary `data` is exposed via the relationship endpoints rather
  than inlined.
- Filtering supports equality only. Extend `JsonApiQueryBuilder.computeWhere()`
  for operators (ranges, `LIKE`, `IN`).
- Bulk/atomic operations and writing to relationship endpoints are not yet
  implemented.

---

## Deploying & testing

```powershell
# Validate without saving (compiles + runs tests server-side, persists nothing)
sf project deploy validate -d force-app -l RunLocalTests -o <your-org>

# Deploy for real
sf project deploy start -d force-app -o <your-org>

# Run just this framework's tests
sf apex run test -o <your-org> -l RunSpecifiedTests `
  -t JsonApiServiceTest -t JsonApiRequestParserTest -t JsonApiRestResourceTest
```
