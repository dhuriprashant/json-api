# Developer Guide

A practical, end-to-end guide to **working on** the Apex JSON:API framework:
adding new resources, understanding how the engine works internally, the
day-to-day development workflow, and how to extend and maintain it safely.

> This is the **contributor / extender** guide. For a condensed architecture
> reference see [`TECHNICAL.md`](TECHNICAL.md); for the **consumer** API reference
> (endpoints, query params, examples) see
> [`../force-app/main/default/classes/JSON-API-README.md`](../force-app/main/default/classes/JSON-API-README.md).

---

## Table of contents

1. [The core idea](#1-the-core-idea)
2. [Adding a new resource — full walkthrough](#2-adding-a-new-resource--full-walkthrough)
3. [How the framework works](#3-how-the-framework-works)
4. [How the framework is developed](#4-how-the-framework-is-developed)
5. [Extending the framework](#5-extending-the-framework)
6. [Maintenance & gotchas](#6-maintenance--gotchas)
7. [Reference](#7-reference)

---

## 1. The core idea

The framework is **configuration-driven**. There is exactly one HTTP entry point
and one orchestration core; everything about *what* a resource is — which SObject
it maps to, which fields are exposed, how it relates to other resources — lives in
a small **config class** plus a **Custom Metadata record**.

```
A request for /jsonapi/accounts
        │
        ▼
  JsonApiRegistry.forType("accounts")  ──►  AccountResourceConfig   (your config)
        │                                          │
        ▼                                          ▼
  the generic engine (parsing, SOQL,        getType(), getSObjectType(),
  serialization, includes, errors)          getAttributeGroups(), getRelationships()
```

The engine never hard-codes an object or field name. Object and field names come
**only** from configs; user input merely *selects among* configured names. This is
both the extension model (add a config → new endpoint) and the security model (no
user-supplied identifier ever reaches SOQL).

**Consequences worth internalizing:**

- Adding a resource requires **no change to the framework** — a new config class
  and a CMDT record, nothing else.
- The framework is **read-only (GET)**. There is no deserializer or write path.
- All data access runs in **`AccessLevel.USER_MODE`**, so CRUD/FLS is enforced by
  the platform for the running user.

---

## 2. Adding a new resource — full walkthrough

We'll expose the **Opportunity** SObject as the `opportunities` resource, with a
to-one relationship to its Account.

### Step 1 — Subclass `JsonApiResourceConfig`

Create `force-app/main/default/classes/OpportunityResourceConfig.cls`:

```apex
public with sharing class OpportunityResourceConfig extends JsonApiResourceConfig {

    public override String getType() {
        return 'opportunities';            // the JSON:API `type` string (URL segment)
    }

    public override Schema.SObjectType getSObjectType() {
        return Opportunity.SObjectType;    // the backing SObject
    }

    public override Map<String, Map<String, String>> getAttributeGroups() {
        return new Map<String, Map<String, String>>{
            // "base" is ALWAYS returned.
            'base' => new Map<String, String>{
                'name'  => 'Name',          // jsonapi attribute => SObject field API name
                'stage' => 'StageName'
            },
            // Other groups are returned only when the client asks: ?extend=details
            'details' => new Map<String, String>{
                'amount'    => 'Amount',
                'closeDate' => 'CloseDate'
            }
        };
    }

    public override Map<String, JsonApiRelationshipDef> getRelationships() {
        return new Map<String, JsonApiRelationshipDef>{
            'account' => JsonApiRelationshipDef.toOne('account', 'accounts', 'AccountId')
        };
    }
}
```

And the meta file `OpportunityResourceConfig.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

**The three required abstract methods:**

| Method | Returns | Rules |
|--------|---------|-------|
| `getType()` | the `type` string, e.g. `'opportunities'` | lowercase, plural by convention; this is the URL segment and the `type` in every resource object |
| `getSObjectType()` | `Schema.SObjectType` | the backing object |
| `getAttributeGroups()` | `Map<String, Map<String,String>>` | group name → ( jsonapi attribute name → SObject field API name ). **Must** contain a `base` group. **Never** map `id` here — it's handled automatically. |

### Step 2 — Understand attribute groups

Attributes are organized into named **groups** so the default payload stays lean
while richer data is available on demand:

- The **`base`** group is *always* returned.
- Any other group is returned *only* when the client names it in the comma-separated
  `?extend=` parameter (e.g. `?extend=details`).
- A sparse fieldset (`?fields[opportunities]=name,amount`) **takes precedence** —
  when present it selects the exact attributes and `extend` is ignored for that type.

```
GET /opportunities/006...                     → name, stage
GET /opportunities/006...?extend=details      → name, stage, amount, closeDate
GET /opportunities/006...?fields[opportunities]=amount  → amount only
```

`resolveAttributeNames(options)` on the base class is the **single source of truth**
for "which attributes apply to this request" and is used identically by the SOQL
builder, the serializer, and the include resolver — so they can never disagree.

### Step 3 — Declare relationships (optional)

Override `getRelationships()` returning relationship name → `JsonApiRelationshipDef`.
Two factory methods, mirroring the two Salesforce relationship shapes:

```apex
// to-one: backed by a lookup/master-detail field ON THIS object.
JsonApiRelationshipDef.toOne('account', 'accounts', 'AccountId')
//                            name        targetType  lookupField (on Opportunity)

// to-many: backed by a child relationship, keyed by the FK field on the CHILD.
JsonApiRelationshipDef.toMany('lineItems', 'opportunityLineItems', 'OpportunityId')
//                             name          targetType             childForeignKeyField (on child)
```

- `targetType` is the **JSON:API type string** of the related resource (it must
  itself be a registered resource for `include`/related endpoints to resolve it).
- **to-one** linkage is inlined into the primary resource's `relationships` and can
  be side-loaded with `?include=account`.
- **to-many** linkage is *not* inlined into primary `data`; it's reached via the
  relationship endpoints (`/opportunities/{id}/relationships/lineItems`) and can be
  side-loaded with `?include=lineItems`.

### Step 4 — Register it with a Custom Metadata record

Create `force-app/main/default/customMetadata/JsonApiResource.Opportunities.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Opportunities</label>
    <protected>false</protected>
    <values>
        <field>Apex_Class__c</field>
        <value xsi:type="xsd:string">OpportunityResourceConfig</value>
    </values>
    <values>
        <field>Is_Active__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
</CustomMetadata>
```

`JsonApiBootstrap.registerAll()` reads every **active** `JsonApiResource__mdt` record
on first use and instantiates each `Apex_Class__c` via `Type.forName().newInstance()`.
No framework code changes. Uncheck `Is_Active__c` to disable an endpoint without
deleting the record.

### Step 5 — Deploy & verify

```powershell
sf project deploy start -d force-app -o <org>

# Confirm it registered (and nothing else broke):
#   GET /services/apexrest/jsonapi/_health
#   -> meta.resources should now include "opportunities"
```

The `_health` endpoint is the fastest way to confirm registration succeeded — see
[§3.7](#37-registration--health).

### Step 6 — Test it

Two complementary styles (see [§4.3](#43-testing-strategy)):

```apex
// DML-free: fabricate SObjects, inject the in-memory gateway. Runs anywhere.
@IsTest
static void serializesOpportunity() {
    Id oppId = Id.valueOf('006000000000001AAA');
    Opportunity opp = new Opportunity(Name = 'Big Deal', StageName = 'Prospecting');
    opp.Id = oppId;

    JsonApiTestQueryGateway mock = new JsonApiTestQueryGateway()
        .seed(Opportunity.SObjectType, new List<SObject>{ opp });

    JsonApiResponse r = new JsonApiService(mock).handle(
        'GET', new List<String>{ 'opportunities', oppId }, new Map<String, String>());

    JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
    System.assertEquals('Big Deal', obj.attributes.get('name'));
    System.assertEquals(0, Limits.getDmlStatements());   // truly DML-free
}
```

> Note: the bundled test suite (`RunSpecifiedTests`) only runs the framework's own
> test classes. If you want your new resource covered by the named suite, either add
> its tests to an existing DML-free class or create your own and include it in the
> `-t` list when validating.

---

## 3. How the framework works

A single GET request walks one path through the layers. Understanding that path is
the fastest way to orient. Layers, in request order:

```
JsonApiRestResource  (HTTP)              the only @RestResource; content negotiation, write response, telemetry
        │
        ▼
JsonApiService  (orchestration)          routing table; calls the gateway; assembles the document
        │
        ├─ JsonApiRegistry / JsonApiBootstrap     type string → config (lazy CMDT load)
        ├─ JsonApiRequestParser → JsonApiQueryOptions    raw params → typed options
        ├─ JsonApiQueryBuilder                    config + options → SOQL + binds
        ├─ JsonApiQueryGateway                     executes SOQL in USER_MODE
        ├─ JsonApiSerializer                       SObject → resource object
        └─ JsonApiIncludeResolver                  side-loads the `included` array
        │
        ▼
Document model  →  JsonApiDocument.toJson()  →  response body
```

### 3.1 HTTP layer (`JsonApiRestResource`)

The only `@RestResource(urlMapping='/jsonapi/*')`. It deals **only** with HTTP
concerns and delegates everything else to the service:

- **Content negotiation** (`negotiate()`): accepts `application/json` or an
  unparameterized `application/vnd.api+json`; a JSON:API media type that is
  parameterized in every instance → `406`. The response is always
  `application/json` with JSON:API document structure.
- **Path split** (`segmentsOf()`): finds the `jsonapi` base token in the URI and
  returns the URL-decoded segments after it (`['accounts','001...']`).
- **Error rendering**: a `JsonApiException` is rendered with its carried status; any
  other exception becomes a redacted `500` (see [§3.6](#36-error-handling--500-redaction)).
- **Telemetry**: in a `finally`, emits a `JsonApiRequestLog` to the active observer
  (see [§3.8](#38-observability)).

It exposes only `@HttpGet`. Non-GET verbs are rejected — the platform 405s methods
with no handler, and `JsonApiService.handle` also rejects any non-GET with `405`.

### 3.2 Orchestration (`JsonApiService`)

The routing table maps verb + path shape to an operation:

```
GET /{type}                          → getCollection
GET /{type}/{id}                     → getSingle
GET /{type}/{id}/{relationship}      → getRelated         (resource or collection)
GET /{type}/{id}/relationships/{rel} → getRelationshipLinkage  (identifier objects)
GET /_health                         → health             (matched BEFORE registry lookup)
```

All data access goes through a `JsonApiQueryGateway`. The default constructor wires
the production `JsonApiUserModeGateway`; a `@TestVisible` constructor accepts an
in-memory gateway so the whole service can be unit-tested without DML.

### 3.3 Registry & config resolution

`JsonApiRegistry.forType(type)` resolves the type string to its config, throwing
`404` if unregistered. The registry **lazily self-initializes** by calling
`JsonApiBootstrap.registerAll()` on the first lookup — no load-order dependency, and
nothing to wire up at deploy time.

### 3.4 Request parsing (`JsonApiRequestParser` → `JsonApiQueryOptions`)

Salesforce exposes bracketed params verbatim (the key is literally
`"fields[accounts]"`), so the parser splits the *family* (`fields`) from the *key*
(`accounts`). It validates sort/filter/include/extend names **against the config**,
so bad requests fail with `400` *before* any SOQL exists and only known fields ever
reach the builder.

`JsonApiQueryOptions` is the typed result: `includePaths`, `sparseFields`,
`extendGroups`, `sorts`, `filters` (a `List<FilterCondition>`), and pagination.

### 3.5 SOQL generation (`JsonApiQueryBuilder`) & injection safety

Two invariants make the generated SOQL injection-proof:

1. **Identifiers come only from config.** Object name = `getSObjectType()`; field
   names = values of `getAttributeMap()` / relationship defs. User input only
   *selects* a configured field.
2. **Values are always bind variables.** `buildClause()` emits the operator form
   (`Field = :fN`, `Field > :fN`, `Field LIKE :fN`, `Field IN :fN`, …) and stores the
   value (or a typed list for `in`/`nin`) in `binds`; execution is via
   `Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)`. The operator itself
   is whitelisted by the parser, so it can't inject either.

Filtering supports `eq` `ne` `gt` `gte` `lt` `lte` `like` `in` `nin` via
`filter[attr][op]` (bare `filter[attr]` means `eq`). Conditions are AND-ed; multiple
conditions may target one attribute (e.g. a `gte`/`lt` range).

The resource **id** is always filterable even though it is not declared as an
attribute: `filter[id]` maps to the SObject `Id` field. A bare comma-separated value
(`filter[id]=001...,001...`) is promoted to `in` — the common "fetch these N records"
case — while a single value stays `eq`; explicit operators (`filter[id][in]=...`)
also work. Ids are validated for format and SObject type in the builder
(`parseId()`), so a malformed or wrong-type id is a clean `400`, not a `500`.

> **Typed `IN` binds.** SOQL rejects a `List<Object>` (ANY-typed) bind for `IN`. So
> `coerceList()` builds a list whose element type matches the column
> (`List<Double>`, `List<Integer>`, …). If you add an operator that binds a
> collection, keep it typed.

### 3.6 Error handling & 500 redaction

`JsonApiException` is the single exception type. Static factories cover the standard
conditions (`badRequest`, `notFound`, `notAcceptable`, `methodNotAllowed`,
`internal`), each carrying an HTTP status + JSON:API `errors[]`.

A `500` **never leaks internals**: the REST layer's `internalError()` logs the full
message + stack server-side under a short random reference id, stamps that id onto
the error, and returns a generic message ("…Reference: a1b2c3d4") to the client.

### 3.7 Registration & health

Registration is **fault-isolated**. `registerAll()` wraps each CMDT record in its own
try/catch: a misconfigured record (unknown class, no no-arg constructor, or a class
that doesn't extend the base) is *skipped* — logged at `ERROR` and recorded in
`JsonApiBootstrap.getRegistrationErrors()` — while healthy records still load. A
request for a skipped type then returns a clean `404` rather than a `500` that would
break every endpoint.

`GET /_health` surfaces this: a **meta-only** document listing registered resources
and any registration errors, with HTTP `200` when all active records loaded or `503`
when one or more were skipped. It's matched in `JsonApiService.handle` *before* the
registry lookup, since `_health` is not a resource type.

### 3.8 Observability

Every request emits a `JsonApiRequestLog` (method, path, status, duration, SOQL
count, rows, error code/reference) to a pluggable `JsonApiObserver`. The default
`JsonApiDebugObserver` writes a structured debug line; swap it via
`JsonApiObservability.setObserver(myObserver)` to route logs to a Platform Event,
custom object, or external service.

### 3.9 The document model & serialization semantics

The output types are `JsonApiDocument`, `JsonApiResourceObject`,
`JsonApiResourceIdentifier`, `JsonApiError`, `JsonApiErrorSource`. The single most
important implementation detail is how **explicit null** is preserved:

> `JSON.serialize(obj, true)` (suppress nulls) **drops null Apex-object fields** but
> **keeps null Map entries.** JSON:API distinguishes `"data": null` (an empty to-one)
> from an *absent* `data` member, so anything that must serialize as explicit null is
> modeled as a **`Map`**, not a typed field:
> - relationship objects are `Map<String, Object>` (an empty to-one puts `data → null`);
> - `JsonApiDocument.toJson()` builds the top level as a map and emits `data` only for
>   data documents (the `isDataDocument` flag), so a meta-only `_health` doc omits
>   `data` entirely while a relationship endpoint with no target still emits `"data": null`.

### 3.10 Performance: config memoization

A config instance is a **registry singleton**, so per-type derived data is memoized
on it and reused for the whole transaction:

- `getAttributeGroups()` is wrapped by `cachedGroups()` — built once.
- `getAttributeMap()`, `getFieldToAttributeMap()`, `getAttributeFieldNames()`,
  `relationships()`, and `fieldMap()` (the `getDescribe()` result) are all memoized.

All framework code calls the memoizing accessors (`config.relationships()`,
`config.fieldMap()`), **not** the overridable `getRelationships()` / `getDescribe()`
directly. When you write engine code, do the same.

---

## 4. How the framework is developed

### 4.1 Project shape

A pure Apex Salesforce DX project — no LWC, no JS build.

```
force-app/main/default/
  classes/            # 27 framework classes + 6 test classes + JSON-API-README.md
  objects/JsonApiResource__mdt/   # the registration Custom Metadata Type + 2 fields
  customMetadata/     # one JsonApiResource.*.md-meta.xml per exposed resource
config/project-scratch-def.json   # scratch org definition
docs/                 # TECHNICAL.md, this guide, manual-tests.http, Postman collection
sfdx-project.json     # sourceApiVersion 65.0, no namespace
```

### 4.2 Development workflow

```powershell
# Deploy to a dev/scratch org
sf project deploy start -d force-app -o <org>

# Validate without saving (compiles + runs THIS framework's tests, persists nothing)
sf project deploy validate -d force-app -o <org> -l RunSpecifiedTests `
  -t JsonApiServiceTest -t JsonApiRequestParserTest `
  -t JsonApiRestResourceTest -t JsonApiCoverageTest -t JsonApiUnitTest

# Run the suite with coverage
sf apex run test -o <org> -l RunSpecifiedTests -c `
  -t JsonApiServiceTest -t JsonApiRequestParserTest `
  -t JsonApiRestResourceTest -t JsonApiCoverageTest -t JsonApiUnitTest
```

`RunSpecifiedTests` is deliberate: it runs only the framework's own classes, so
unrelated broken tests in a shared org don't block validation.

> **Coverage numbers come from a real deploy + `run test -c`, not from `validate`.**
> `validate` is checkOnly — it won't show per-class coverage from `sf apex run test`
> because the classes were never persisted. To measure coverage, deploy
> (`-l NoTestRun`) then run the tests with `-c`.

### 4.3 Testing strategy

Tests run at two levels, and knowing which is which matters:

| Class | DML? | Focus |
|-------|------|-------|
| `JsonApiUnitTest` | **No** | Read/serialize/include pipeline + service routing + builder coercion, via the in-memory `JsonApiTestQueryGateway` with fabricated SObjects. |
| `JsonApiRequestParserTest` | **No** | Param parsing + validation rejections. |
| `JsonApiServiceTest` | Yes | GET operations end-to-end through real SOQL + USER_MODE. |
| `JsonApiRestResourceTest` | Yes | HTTP layer: `RestContext` plumbing, negotiation, error rendering, redaction. |
| `JsonApiCoverageTest` | Yes | Config helpers, nested/coalesced include, document model, fault-isolated registration. |

The enabler is the **`JsonApiQueryGateway` seam**: inject `JsonApiTestQueryGateway`
via the `@TestVisible JsonApiService(gateway)` constructor and `seed()` rows per
SObjectType — no inserts, no org coupling, immune to broken triggers. Seeded
queries ignore the `WHERE` clause (the test controls exactly what each object
returns) and record every SOQL string so you can assert query shape/count.

**Why DML-free matters:** the three DML-backed suites insert real `Account`/`Contact`
records, so a broken Account/Contact trigger in the target org will fail them — an
*org* problem, not a framework one. The DML-free suites run anywhere. **Validate the
full suite in a clean scratch org.**

### 4.4 Spinning up a clean scratch org

```powershell
sf org create scratch -f config/project-scratch-def.json -v <devhub> -a jsonapi-scratch -y 1 -w 15
sf project deploy start -d force-app -o jsonapi-scratch -l NoTestRun
sf apex run test -o jsonapi-scratch -l RunSpecifiedTests -c -w 15 `
  -t JsonApiServiceTest -t JsonApiRequestParserTest `
  -t JsonApiRestResourceTest -t JsonApiCoverageTest -t JsonApiUnitTest
```

(`-y` is duration-days; `-d` means `--set-default` for this command, not duration.)

### 4.5 Conventions to keep

- **API version `65.0`**, no namespace.
- **Read-only.** Only GET. Don't add a write path without an explicit decision — it
  means restoring a deserializer + create/update/delete handlers.
- **Stay in `AccessLevel.USER_MODE`** for every query/DML path.
- **`with sharing`** on classes that touch data.
- Route per-type describe-derived data through the **memoizing accessors**, not the
  overridable methods.

---

## 5. Extending the framework

| To add… | Do this |
|---------|---------|
| A new resource | Subclass `JsonApiResourceConfig` + add a `JsonApiResource__mdt` record. ([§2](#2-adding-a-new-resource--full-walkthrough)) |
| A new attribute group | Add a key to the resource's `getAttributeGroups()`. Clients opt in with `?extend=`. |
| A new filter operator | Add a `when` branch in `JsonApiQueryBuilder.buildClause()` **and** the operator name to `FILTER_OPERATORS` in `JsonApiRequestParser`. |
| Custom telemetry sink | Implement `JsonApiObserver`; register with `JsonApiObservability.setObserver(...)`. |
| A different data-access policy | Implement `JsonApiQueryGateway`; inject via the service constructor. (Keep `USER_MODE`.) |
| A new error condition | Add a factory to `JsonApiException`. |

### Recipe: a new filter operator (`between`)

1. **Parser** — whitelist it:
   ```apex
   private static final Set<String> FILTER_OPERATORS = new Set<String>{
       'eq','ne','gt','gte','lt','lte','like','in','nin','between'   // <-- add
   };
   ```
2. **Builder** — render it in `buildClause()`, keeping values bound:
   ```apex
   when 'between' {
       List<String> parts = fc.rawValue.split(',');           // "10,20"
       String lo = 'f' + (bindCounter++);
       String hi = 'f' + (bindCounter++);
       binds.put(lo, coerce(fieldName, parts[0].trim()));
       binds.put(hi, coerce(fieldName, parts[1].trim()));
       return '(' + fieldName + ' >= :' + lo + ' AND ' + fieldName + ' <= :' + hi + ')';
   }
   ```
3. **Test** — add a DML-free builder test (assert the SOQL + bind types) and a
   DML-backed service test (assert it actually filters).
4. **Docs** — update the filter tables in README, JSON-API-README, and TECHNICAL.

### Recipe: a custom observer

```apex
public class PlatformEventObserver implements JsonApiObserver {
    public void observe(JsonApiRequestLog log) {
        EventBus.publish(new Json_Api_Request__e(
            Status__c = log.statusCode, Path__c = log.path,
            Duration_Ms__c = log.durationMs, Soql__c = log.soqlQueries));
    }
}
// once, e.g. in a setup path:
JsonApiObservability.setObserver(new PlatformEventObserver());
```

`JsonApiObservability.emit()` swallows any exception the observer throws, so a broken
sink can never break a request.

---

## 6. Maintenance & gotchas

Hard-won lessons. Most of these have already bitten someone; keep them in mind when
changing the engine.

- **Suppress-nulls vs explicit null.** `JSON.serialize(obj, true)` drops null
  Apex-object fields but keeps null Map entries. Anything that must appear as
  `"data": null` (empty to-one linkage) is modeled as a `Map`. Don't "tidy" these
  into typed classes — you'll silently drop the `null` and break spec compliance.
  ([§3.9](#39-the-document-model--serialization-semantics))

- **Typed `IN` binds.** A `List<Object>` bind for `IN` throws
  *"Invalid bind expression type of ANY"*. Build a list whose element type matches the
  column. ([§3.5](#35-soql-generation-jsonapiquerybuilder--injection-safety))

- **Apex reserved words.** `Sort`, `Group`, `Update` (and friends) can't be used as
  identifiers — this is why you see `SortField`, `grp`, `updateRecord`.

- **Unreachable code after an exhaustive `switch`.** When every `when` branch
  (including `when else`) returns, Apex flags a trailing statement as unreachable.
  Don't add a "just in case" `return` after such a switch.

- **`USER_MODE` everywhere.** Every new query/DML path must run in
  `AccessLevel.USER_MODE` or you lose CRUD/FLS enforcement. The `JsonApiUserModeGateway`
  is the *only* class that calls `Database` query methods directly — keep it that way.

- **Memoization & singletons.** Configs are registry singletons, so memoized fields
  live for the whole transaction. `JsonApiRegistry.reset()` (`@TestVisible`) clears
  the registry between tests; if you add cached state to a config, make sure it's
  rebuilt after a reset (it is, because a reset creates fresh instances on next load).

- **Broken triggers in shared orgs.** If Account/Contact DML fails with something
  like *"Invalid conversion from runtime type Accounts.Constructor to
  fflib_SObjectDomain.IConstructable"*, that's a broken trigger in the **org**, not
  the framework. Run the DML-free suites, or validate in a clean scratch org.

- **Coverage from the right command.** Per-class coverage comes from a real deploy +
  `sf apex run test -c`. `deploy validate` is checkOnly and enforces the gate but
  won't give you `run test` per-class numbers.

---

## 7. Reference

### Class catalog (framework)

| Layer | Classes |
|-------|---------|
| HTTP entry | `JsonApiRestResource` |
| Orchestration | `JsonApiService`, `JsonApiResponse` |
| Config | `JsonApiResourceConfig`, `JsonApiRelationshipDef`, `JsonApiRegistry`, `JsonApiBootstrap` |
| Parsing | `JsonApiRequestParser`, `JsonApiQueryOptions` |
| Data access | `JsonApiQueryBuilder`, `JsonApiIncludeResolver`, `JsonApiQueryGateway`, `JsonApiUserModeGateway` |
| Serialization | `JsonApiSerializer` |
| Document model | `JsonApiDocument`, `JsonApiResourceObject`, `JsonApiResourceIdentifier`, `JsonApiError`, `JsonApiErrorSource` |
| Errors | `JsonApiException` |
| Observability | `JsonApiObservability`, `JsonApiObserver`, `JsonApiRequestLog`, `JsonApiDebugObserver` |
| Constants | `JsonApiConstants` |
| Test support | `JsonApiTestQueryGateway` (`@IsTest` mock gateway) |

### Query parameters

| Parameter | Example | Notes |
|-----------|---------|-------|
| `include` | `?include=parent,contacts` | comma-separated; nested (`contacts.account`); max 10 paths, depth 3 |
| `extend` | `?extend=financials,contactInfo` | attribute **groups** added on top of `base` |
| `fields[TYPE]` | `?fields[accounts]=name,phone` | sparse fieldsets; precedence over `extend` |
| `sort` | `?sort=-annualRevenue,name` | `-` prefix = descending |
| `filter[ATTR]` | `?filter[industry]=Technology` | equality (`eq`) |
| `filter[ATTR][OP]` | `?filter[annualRevenue][gte]=1000000` | `eq` `ne` `gt` `gte` `lt` `lte` `like` `in` `nin` |
| `filter[id]` | `?filter[id]=001...,001...` | fetch by id; comma list → `in`, single → `eq`; validated against the resource's SObject type |
| `page[size]` / `page[number]` | `?page[size]=10&page[number]=2` | page-based |
| `page[limit]` / `page[offset]` | `?page[limit]=10&page[offset]=20` | offset-based |

### Error codes

| HTTP | code | Raised when |
|------|------|-------------|
| 400 | `BAD_REQUEST` | unknown sort/filter/include/extend name, bad operator, bad filter value, malformed id |
| 404 | `NOT_FOUND` | unregistered type, unknown id, unknown relationship, unrecognized path shape |
| 405 | `METHOD_NOT_ALLOWED` | any non-GET verb |
| 406 | `NOT_ACCEPTABLE` | JSON:API media type requested only in parameterized form |
| 500 | `INTERNAL_ERROR` | any unexpected exception (message/stack redacted, reference id returned) |
| 503 | (health) | `/_health` when one or more CMDT records failed to register |

### Limits (`JsonApiConstants`)

| Constant | Value |
|----------|-------|
| `DEFAULT_PAGE_SIZE` | 25 |
| `MAX_PAGE_SIZE` | 200 |
| `MAX_OFFSET` | 2000 |
| `MAX_INCLUDE_PATHS` | 10 |
| `MAX_INCLUDE_DEPTH` | 3 |
