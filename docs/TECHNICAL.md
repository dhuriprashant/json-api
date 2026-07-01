# Apex JSON:API Framework — Technical Design

This document describes the internal design of the framework: how a request flows
through the layers, what each class is responsible for, how SOQL is generated
safely, the security model, key algorithms, and the extension points. It is aimed
at developers maintaining or extending the framework. For usage/endpoint
reference, see [`JSON-API-README.md`](../force-app/main/default/classes/JSON-API-README.md).

- **Spec target:** [JSON:API v1.1](https://jsonapi.org/format/)
- **Platform:** Apex (API 65.0), no namespace, no external dependencies
- **Source:** `force-app/main/default/classes/`

---

## 1. Design goals & principles

| Goal | How it's realized |
|------|-------------------|
| **Configuration over code** | New resources are exposed by subclassing `JsonApiResourceConfig` + one `JsonApiResource__mdt` Custom Metadata record — no change to the framework, no new endpoints, parsing, or SOQL. |
| **Single responsibility per class** | HTTP, routing, parsing, query building, serialization, and persistence are separate, independently testable units. |
| **Secure by default** | All SOQL runs in `AccessLevel.USER_MODE`; identifiers come only from config; values are always bind variables. Read-only — no DML. |
| **Spec compliance** | Document model mirrors the JSON:API object model; content negotiation and error documents follow the spec. |
| **Transport independence** | The service layer returns a `JsonApiResponse` value object; only `JsonApiRestResource` touches `RestContext`. This keeps the core unit-testable without HTTP. |

---

## 2. Layered architecture

```
                       HTTP (application/vnd.api+json)
                                  │
                  ┌───────────────▼────────────────┐
                  │      JsonApiRestResource         │  HTTP concerns only:
                  │  @RestResource('/jsonapi/*')     │  verb routing, content
                  └───────────────┬────────────────┘  negotiation, response I/O
                                  │ method, segments[], params, body
                  ┌───────────────▼────────────────┐
                  │         JsonApiService           │  routing table + orchestration
                  └──┬───────┬───────┬───────┬──────┘
                     │           │            │
        ┌────────────▼─┐ ┌───────▼──┐ ┌───────▼───────────┐
        │ RequestParser│ │  Query   │ │ Serializer        │
        │  →QueryOpts  │ │  Builder │ │ + IncludeResolver │
        └──────┬───────┘ └─────┬────┘ └───────┬───────────┘
               │               │              │
               │        ┌──────▼─────┐        │
               │        │  Database  │        │  queryWithBinds (USER_MODE)
               │        └────────────┘        │
        ┌──────▼─────────────────────────▼──────┐
        │  Registry ← Bootstrap ← ResourceConfig  │  config & metadata
        └─────────────────────────────────────────┘
                                  │
                  ┌───────────────▼────────────────┐
                  │  Document model (DTOs) → JSON    │
                  └─────────────────────────────────┘
```

### Class responsibilities

| Layer | Class | Responsibility |
|-------|-------|----------------|
| HTTP | `JsonApiRestResource` | The only `@RestResource`. Routes verbs, enforces content negotiation, splits the URI, writes the response, renders exceptions as error documents. |
| Orchestration | `JsonApiService` | Routing table (verb + path shape → operation). Runs queries/DML. Builds the response document including `meta` and pagination `links`. |
| Orchestration | `JsonApiResponse` | Transport-agnostic `{statusCode, document, headers}` value object. |
| Config | `JsonApiResourceConfig` | Abstract base mapping a JSON:API `type` → SObject, attribute groups and relationships. |
| Config | `JsonApiRelationshipDef` | Declares a to-one (lookup field) or to-many (child FK) relationship. |
| Config | `JsonApiRegistry` | Lookups by type and by SObjectType; lazy self-initialization. |
| Config | `JsonApiBootstrap` | Loads active `JsonApiResource__mdt` records and instantiates each named Apex config via reflection. |
| Parsing | `JsonApiRequestParser` | Raw params → validated `JsonApiQueryOptions`. |
| Parsing | `JsonApiQueryOptions` | Typed `include` / `fields` / `sort` / `filter` / `page` (+ inner `SortField`). |
| Data | `JsonApiQueryBuilder` | Generates parameterized SOQL (collection / single / count) + a `binds` map. |
| Data | `JsonApiIncludeResolver` | Coalesces `include` paths into a tree and bulk-queries related records for the `included` array. |
| Data | `JsonApiQueryGateway` / `JsonApiUserModeGateway` | The DB seam: interface over query execution; the production impl runs everything in `USER_MODE`. Swappable for an in-memory test double. |
| Serialization | `JsonApiSerializer` | SObject → `JsonApiResourceObject` (attributes, to-one linkage, links). |
| Model | `JsonApiDocument`, `JsonApiResourceObject`, `JsonApiResourceIdentifier`, `JsonApiError`, `JsonApiErrorSource` | The JSON:API document object model. |
| Errors | `JsonApiException` | Carries HTTP status + `errors[]`; factory methods per status. |
| Observability | `JsonApiObservability` / `JsonApiObserver` / `JsonApiRequestLog` / `JsonApiDebugObserver` | Per-request telemetry emitted at the HTTP boundary to a pluggable observer (default: structured debug log). |
| Constants | `JsonApiConstants` | Media type, base path, param names, pagination limits. |

---

## 3. Request lifecycle (end to end)

Tracing `GET /services/apexrest/jsonapi/v1/accounts/001.../?include=parent&fields[accounts]=name`:

1. **Entry** — `JsonApiRestResource.doGet()` (the only HTTP handler) runs the request directly.
2. **Content negotiation** — `negotiate()` accepts `application/json` or unparameterized `application/vnd.api+json`. Response is always `application/json` with JSON:API document structure.
3. **Path split** — `segmentsOf(requestURI)` finds the `jsonapi` base token and returns the URL-decoded segments after it: `['v1', 'accounts', '001...']` (the first is the API version).
4. **Service dispatch** — `JsonApiService.handle('GET', segments, params)`:
   - any non-GET verb → `405`;
   - the reserved `_health` segment short-circuits to the diagnostics document (before version handling);
   - the leading `v1` segment is taken as the **API version**, stripped, and used to build a version-scoped serializer (`BASE_PATH + '/v1'`);
   - `JsonApiRegistry.forType('v1', 'accounts')` resolves the config (lazy-initializing the registry via `JsonApiBootstrap` on first call). Unknown version/type → `404`.
   - routes the remaining `type/id/...` by path shape → `handleGet()`.
5. **Parse query** — `JsonApiRequestParser.parse(params, config)` produces `JsonApiQueryOptions`. Unknown sort/filter/include names are rejected with `400` here, before any SOQL exists.
6. **Build & run SOQL** — for a single record, `JsonApiQueryBuilder.buildSingleQuery(id)` produces `SELECT Id, Name, ParentId FROM Account WHERE Id = :recordId LIMIT 1` with `binds = {recordId}`. Executed via `Database.queryWithBinds(..., AccessLevel.USER_MODE)`.
7. **Serialize** — `JsonApiSerializer.toResource()` maps fields → attributes (honoring sparse `fields[accounts]=name`), emits to-one relationship linkage from the `ParentId` value, and adds a `self` link.
8. **Resolve includes** — `JsonApiIncludeResolver.resolve()` collects `ParentId` values, bulk-queries the parent Accounts, serializes them into `included` (deduplicated by `type:id`).
9. **Assemble** — `JsonApiDocument.ofData(resource)` (stamped with `jsonapi.version`), `included` attached.
10. **Write response** — `writeResponse()` sets the status code, `Content-Type: application/vnd.api+json`, any extra headers, and the serialized body.
11. **Errors** — any `JsonApiException` thrown anywhere in 2–10 is caught in `doGet()` and rendered as a JSON:API error document with the carried HTTP status; any other exception becomes a `500` error document.
12. **Telemetry** — in a `finally`, `doGet()` emits a `JsonApiRequestLog` (status, duration, SOQL count, rows, error code/reference) to the active `JsonApiObserver`.

### Sequence diagram

A `GET /jsonapi/v1/accounts/{id}?include=parent` request through the layers:

```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant REST as JsonApiRestResource
    participant Svc as JsonApiService
    participant Reg as JsonApiRegistry
    participant Parser as JsonApiRequestParser
    participant Builder as JsonApiQueryBuilder
    participant DB as Database USER_MODE
    participant Ser as JsonApiSerializer
    participant Inc as JsonApiIncludeResolver

    Client->>REST: GET /v1/accounts/{id}?include=parent
    activate REST
    REST->>REST: negotiate(Accept)
    REST->>REST: segmentsOf(uri) -> [accounts, id]
    REST->>Svc: handle GET, segments, params
    activate Svc

    Svc->>Reg: forType(v1, accounts)
    Reg-->>Svc: config (404 if unknown)
    Svc->>Parser: parse(params, config)
    Parser-->>Svc: QueryOptions (400 if invalid param)

    Svc->>Builder: buildSingleQuery(id)
    Builder-->>Svc: soql + binds
    Svc->>DB: queryWithBinds(soql, binds)
    DB-->>Svc: SObject (404 if none)
    Svc->>Ser: toResource(record, config, options)
    Ser-->>Svc: ResourceObject (data)

    opt include requested
        Svc->>Inc: resolve(records, config, options)
        Inc->>DB: queryWithBinds(related WHERE Id IN ids)
        DB-->>Inc: related SObjects
        Inc->>Ser: toResource per related record
        Inc-->>Svc: included list (deduped by type+id)
    end

    Svc-->>REST: JsonApiResponse(200, document)
    deactivate Svc
    REST-->>Client: 200 application/vnd.api+json
    deactivate REST

    Note over REST: JsonApiException is caught and rendered as an error<br/>document with its status 400/404/405/406, any other error becomes 500
```

_(If your viewer doesn't render Mermaid, see the exported
[request-sequence.svg](img/request-sequence.svg) /
[request-sequence.png](img/request-sequence.png).)_

For a **collection** request the single-record query is replaced by
`buildCollectionQuery()` + `buildCountQuery()` (the latter feeds `meta.total` and
the pagination `links`); everything else is identical.

---

## 4. The configuration model

A resource is fully described by a `JsonApiResourceConfig` subclass:

```apex
public override String getType();                          // 'accounts'
public override Schema.SObjectType getSObjectType();       // Account.SObjectType
public override Map<String,Map<String,String>> getAttributeGroups(); // group -> (jsonName -> Field)
public virtual  Map<String,JsonApiRelationshipDef> getRelationships();
```

Derived helpers on the base class (do not override) keep subclasses terse:
`getAttributeMap()` (the flattened union of all groups), `getFieldToAttributeMap()`,
`getAttributeFieldNames()`, `hasAttribute()`, `fieldFor()`, `hasGroup()`,
`relationshipFor()`.

### Attribute groups & `extend`

Attributes are partitioned into named groups via `getAttributeGroups()`. The
`base` group (`JsonApiResourceConfig.BASE_GROUP`) is always returned; other groups
are opt-in through the `extend` query param. Two helpers drive selection:

- `attributesForGroups(extendGroups)` — base ∪ each requested group that exists on
  this resource (unknown groups ignored, so it's safe to apply to related types).
- `resolveAttributeNames(options)` — the single source of truth for *which*
  attributes to expose: a sparse `fields[type]` set wins if present, otherwise
  `attributesForGroups(options.extendGroups)`. The query builder, serializer, and
  include resolver all call this, so projected columns and serialized output never
  diverge.

### Relationships

`JsonApiRelationshipDef` has two factories:

- `toOne(name, targetType, lookupField)` — backed by a lookup/MD field on **this**
  object (e.g. `Contact.AccountId` → `account`). Linkage is derived directly from
  the stored lookup Id, so no extra query is needed for to-one linkage.
- `toMany(name, targetType, childForeignKeyField)` — backed by the FK field on the
  **child** object (e.g. `Account` ← `Contact.AccountId` → `contacts`). Linkage and
  side-loading require querying the children.

### Registry & bootstrap

`JsonApiRegistry` keys configs by `version/type` (a config's version comes from
`getVersion()`, default `v1`), so the same type can be registered under several
versions from different config classes (e.g. `AccountResourceConfig` →
`v1/accounts`, `AccountV2ResourceConfig` → `v2/accounts`). `ensureInitialized()`
lazily calls `JsonApiBootstrap.registerAll()` on the first lookup, so there is no
load-order dependency. `@TestVisible reset()` supports test isolation.

Registration is **data-driven via the `JsonApiResource__mdt` Custom Metadata Type**:

| CMDT element | Purpose |
|--------------|---------|
| `DeveloperName` / `Label` | Human-readable record name (e.g. `Accounts`). |
| `Apex_Class__c` (Text, required) | API name of the `JsonApiResourceConfig` subclass. |
| `Is_Active__c` (Checkbox) | When unchecked, the resource is skipped — disable without deleting. |
| `Versions__c` (Text) | Comma-separated versions the config is exposed under, e.g. `v1,v2`. Blank → the config's `getVersion()` (defaults to `v1`). |

`registerAll()` queries the active records and, for each, resolves the class with
`Type.forName(Apex_Class__c)` and `newInstance()`, validates it `instanceof
JsonApiResourceConfig`, and registers it **once per version** in `Versions__c` (the
same config instance can back several `version/type` keys — this is how one resource
is carried across versions unchanged; the shipped `Contacts` record uses
`Versions__c = "v1,v2"`). A config that *differs* between versions is instead a
separate class with its own record (e.g. `AccountV2ResourceConfig`). Registration is **fault-isolated**: each
record is wrapped in its own try/catch, so a misconfigured one (unknown class, no
public no-arg constructor, or a class that doesn't extend the base) is *skipped* —
the reason is logged at `ERROR` and recorded in
`JsonApiBootstrap.getRegistrationErrors()` — while the healthy records still load. A
request for a skipped type then returns a clean `404` rather than a `500` that would
also break every other resource. A `@TestVisible configOverride` field lets tests
inject in-memory CMDT rows without DML.

The **`GET /_health`** route (matched in `JsonApiService.handle` before the registry
lookup, since `_health` is not a resource type) surfaces this: a meta-only document
listing the registered resources and any `registrationErrors`, with HTTP `200` when
all active records loaded or `503` when one or more were skipped.

Because configs are loaded by name, **adding a resource needs no Apex change to the
framework** — only a new config class plus a CMDT record.

---

## 5. Query parsing (`JsonApiRequestParser`)

Salesforce exposes bracketed params verbatim, so the parser splits the *family*
from the *key* with the regex `^(\w+)\[([^\]]+)\]$`:

| Raw key | Family | Key | Handler |
|---------|--------|-----|---------|
| `fields[accounts]` | `fields` | `accounts` | sparse fieldset for type `accounts` |
| `page[size]` | `page` | `size` | pagination |
| `filter[industry]` | `filter` | `industry` | equality filter (`eq`) |
| `filter[annualRevenue][gte]` | `filter` | `annualRevenue` / `gte` | operator filter (`eq`/`ne`/`gt`/`gte`/`lt`/`lte`/`like`/`in`/`nin`) |
| `include` | — | — | relationship paths |
| `sort` | — | — | sort directives |
| `extend` | — | — | extra attribute groups |

**Validation happens at parse time** against the *primary* config:
- `sort` / `filter` attributes must exist in the config → else `400` with a
  `source.parameter`. This guarantees only known fields reach the SOQL builder.
- `include` validates the **first** path segment; deeper segments are validated by
  the include resolver as it descends. Paths deeper than `MAX_INCLUDE_DEPTH` or
  more than `MAX_INCLUDE_PATHS` of them → `400` (bounds compound-document cost).
- `extend` group names must exist on the primary config → else `400`; the `base`
  group is implicit and silently skipped if named.
- `page[...]` values must be non-negative integers; size is clamped to
  `MAX_PAGE_SIZE`, offset to `MAX_OFFSET` (the platform's 2000 ceiling).

`page[number]` is retained as-is and converted to an offset later by the builder
(once the page size is known): `offset = (number - 1) * size`.

---

## 6. SOQL generation & injection safety (`JsonApiQueryBuilder`)

The builder is the **only** place SOQL strings are produced. Two invariants make
it injection-proof:

1. **Identifiers come only from config.** Object name = `getSObjectType()`; field
   names = the values of `getAttributeMap()` / relationship defs. User input
   selects *which* configured field, never supplies a raw name. Sort/filter
   attribute names were already validated against the config in the parser.
2. **Values are always bind variables.** `buildClause()` emits the operator form
   (`Field = :fN`, `Field > :fN`, `Field LIKE :fN`, `Field IN :fN`, …) and stores
   the value (or coerced list for `in`/`nin`) in `binds`; the service executes with
   `Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)`. The operator
   itself is whitelisted by the parser, so it can never inject SOQL either.

The reserved `filter[id]` maps to the SObject `Id` field (it is not a declared
attribute). A bare comma-separated value is promoted to `in`; `parseId()` validates
each id's format and that it belongs to this resource's SObject type (→ `400`), and
the `ID` branch of `coerce`/`coerceList` binds `Id` / `List<Id>` so the SOQL is
type-correct.

### Field selection

`selectFields()` returns a `Set<String>`:
- always `Id`;
- the fields backing `config.resolveAttributeNames(options)` — i.e. the sparse
  `fields[type]` set if present, otherwise the `base` group plus any `extend`
  groups — so only columns that will actually be serialized are queried;
- all to-one lookup fields (cheap, and needed to emit to-one linkage).

### Value coercion

`coerce(field, value)` uses the field's `Schema.DisplayType` to convert the string
filter value to the correct Apex type (Boolean/Integer/Double/Date/Datetime/…),
so the bind type matches the field. A bad value → `400`.

### Memoized WHERE

`buildWhere()` is memoized (`whereBuilt`/`cachedWhere`) so the collection query and
the `COUNT()` query share **one** set of bind variables — calling both does not
double-increment the bind counter or desynchronize `binds`.

### Three query shapes

| Method | Produces |
|--------|----------|
| `buildCollectionQuery()` | `SELECT … FROM obj [WHERE …] [ORDER BY …] LIMIT n OFFSET m` |
| `buildSingleQuery(id)` | `SELECT … FROM obj WHERE Id = :recordId LIMIT 1` |
| `buildCountQuery()` | `SELECT COUNT() FROM obj [WHERE …]` (for `meta.total` + paging links) |

Sorting maps each `SortField` to `field ASC|DESC NULLS LAST`.

---

## 7. Include resolution (`JsonApiIncludeResolver`)

Compound documents are built by first **coalescing all `include` paths into a
prefix tree**, then walking the tree with a **one-level-per-step bulk query**
strategy (no SOQL subqueries/dot-traversal). Coalescing means a shared prefix is
queried once — `contacts.account` and `contacts.cases` fetch `contacts` a single
time.

```
buildTree(paths):  fold dotted paths into nested {relName -> node}

walk(parents, parentConfig, node):
    for relName in node.children:
        def       = parentConfig.relationshipFor(relName)     // 400 if unknown
        targetCfg = Registry.forType(version, def.targetType)
        related   = fetchRelated(parents, def, targetCfg)     // ONE bulk query
        for r in related: included[type:id] = serialize(r)    // dedupe by key
        walk(related, targetCfg, node.children[relName])      // descend once
```

`fetchRelated`:
- **to-one:** gather the lookup Ids from `parents`, then `… WHERE Id IN :ids`.
- **to-many:** gather parent Ids, then `… WHERE childForeignKeyField IN :ids`.

Properties:
- **Bulk-safe:** one query per relationship per level regardless of parent count;
  shared prefixes are never re-queried (governor friendly).
- **Bounded:** the parser caps paths at `MAX_INCLUDE_PATHS` and depth at
  `MAX_INCLUDE_DEPTH`, so the query count has a hard ceiling.
- **Deduplicated:** `included` is keyed by `type:id`, so a resource referenced by
  many parents appears once (spec requirement).
- **Sparse-aware:** related records honor `fields[targetType]`.

---

## 8. Serialization

`JsonApiSerializer.toResource()` builds a `JsonApiResourceObject`:
- `id` = `record.get('Id')`, `type` = config type;
- attributes from `resolveAttributeNames(options)` (sparse `fields[]`, else base +
  `extend` groups);
- relationships: each is a **`Map`** with `self`/`related` links; a to-one also
  carries explicit `data` linkage — the identifier when set, or `null` when empty;
- a `self` link.

### Suppress-nulls vs. explicit `null`

Output uses `JSON.serialize(value, true)`, whose `suppressApexObjectNulls` flag
omits absent members — but it only drops null **Apex-object fields**, *not* null
**map entries**. JSON:API requires an empty to-one to serialize as `"data": null`
(distinct from an absent member), so the two places that need an explicit null are
modeled as maps rather than typed fields:
- **relationship objects** are `Map<String,Object>` (so `data => null` survives);
- **`JsonApiDocument.toJson()`** builds the top level as a map and always includes
  `data` for a data document — so an empty relationship-linkage / related endpoint
  returns `{"data": null}` rather than `{}`.

Everything else stays a typed DTO and relies on suppress-nulls to omit optional
members. (The framework is read-only — there is no inbound deserialization path.)

---

## 9. Security model

| Concern | Mechanism |
|---------|-----------|
| CRUD / FLS | All reads go through `JsonApiUserModeGateway`, the only class that calls `Database`, which runs every query in `AccessLevel.USER_MODE` — so the platform enforces the running user's object and field permissions. |
| SOQL injection | Identifiers are config-sourced; values are bind variables (see §6). |
| Read-only | No DML path exists; non-GET verbs are rejected with `405`. |
| Sharing | All worker classes are declared `with sharing`. |
| Field exposure | Only fields explicitly listed in `getAttributeMap()` are ever selected or returned. |

`USER_MODE` is the linchpin — **preserve it on any new query or DML path.**

---

## 10. Error handling

`JsonApiException` carries an HTTP status and a `List<JsonApiError>`, with factory
methods (`badRequest`, `notFound`, `notAcceptable`, `methodNotAllowed`,
`internal`). Thrown anywhere in the stack, it is caught once in
`JsonApiRestResource.doGet()` and rendered as a spec-compliant document:

```json
{ "jsonapi": { "version": "1.1" },
  "errors": [ { "status": "400", "code": "BAD_REQUEST", "title": "Bad Request",
                "detail": "Cannot sort by unknown attribute \"foo\".",
                "source": { "parameter": "sort" } } ] }
```

Unexpected (non-`JsonApiException`) errors become a `500` whose `detail` is
**redacted**: `internalError()` logs the real message + stack server-side under a
short random reference and returns only `"…Reference: <id>"` to the client — no
internals leak.

| Condition | Status |
|-----------|--------|
| Validation / bad params (bad sort/filter/extend, invalid id) | 400 |
| Unknown type / id / relationship | 404 |
| Non-GET method | 405 |
| Parameterized Accept media type | 406 |
| Uncaught error | 500 |

---

## 11. Pagination

Two strategies are accepted and normalized to LIMIT/OFFSET:
- `page[size]` + `page[offset]` (offset-based), or `page[limit]` as a `size` alias;
- `page[size]` + `page[number]` (page-based) → `offset = (number-1) * size`.

For collections the service issues a `COUNT()` query and returns `meta.total` plus
top-level `links`:

```
first = offset 0
last  = floor((total-1)/size) * size
prev  = offset>0 ? max(offset-size, 0) : null
next  = (offset+size) < total ? offset+size : null
self  = current offset
```

Defaults/limits live in `JsonApiConstants` (`DEFAULT_PAGE_SIZE=25`,
`MAX_PAGE_SIZE=200`, `MAX_OFFSET=2000`).

---

## 12. Extension points

| To add… | Do this |
|---------|---------|
| A new resource | Subclass `JsonApiResourceConfig`; add a `JsonApiResource__mdt` record naming it. |
| More filter operators | Add a `when` branch in `JsonApiQueryBuilder.buildClause()` and the operator name to `FILTER_OPERATORS` in the parser. |
| Computed/virtual attributes | Override serialization for the type, or post-process the `JsonApiResourceObject`. |
| Per-resource toggles / extra config | Add fields to `JsonApiResource__mdt` and read them in `JsonApiBootstrap`. |
| Custom auth / rate limiting | Add checks in `JsonApiRestResource.doGet()` before delegating. |
| Swap the data source (e.g. mock, cache, cross-org) | Implement `JsonApiQueryGateway` and inject it into `JsonApiService`. |
| Route request telemetry (Platform Events, logging fwk) | Implement `JsonApiObserver` and register it via `JsonApiObservability.setObserver()`. |
| To-many linkage inlined in primary `data` | Populate `relationships[name].data` during serialization by querying children. |

---

## 13. Testing strategy

Tests run at two levels — **fast DML-free unit tests** plus DML-backed
integration tests:

| Test class | DML? | Focus |
|------------|------|-------|
| `JsonApiUnitTest` | No | Read/serialize/include pipeline driven by an in-memory `JsonApiTestQueryGateway` with fabricated SObjects — runs anywhere, even orgs with broken triggers. |
| `JsonApiRequestParserTest` | No | Param parsing + validation rejections. |
| `JsonApiServiceTest` | Yes | GET operations — collection, single, include, sparse, `extend`, sort, filter operators (`gt`/`gte`/`lt`/`lte`/`ne`/`like`/`in`/`nin`), pagination, related/linkage endpoints, error statuses (incl. non-GET → 405) — via `JsonApiService.handle()`. |
| `JsonApiRestResourceTest` | Yes | HTTP layer: `RestContext` plumbing, content negotiation (406), error rendering, `internalError` redaction, `segmentsOf`. |
| `JsonApiCoverageTest` | Yes | Config helpers, nested/coalesced include, document-model helpers, fault-isolated CMDT registration. |

The DB seam (`JsonApiQueryGateway`) is what makes the unit tests possible: inject
`JsonApiTestQueryGateway` via the `@TestVisible JsonApiService(gateway)`
constructor and seed rows per SObjectType — no inserts, no org coupling.

**Status:** 75 tests passing, 94% org-wide coverage with every framework class
≥89% (clean scratch org), and verified live over HTTP against a real org.

> The DML-backed tests insert real `Account`/`Contact` records, so a broken
> Account/Contact trigger in the target org will fail them — an org problem, not a
> framework one. The DML-free `JsonApiUnitTest`/`JsonApiRequestParserTest` run
> regardless; validate the full suite in a clean scratch org.

---

## 14. Known limitations

- **Read-only.** Only `GET` is implemented; `POST`/`PATCH`/`DELETE` return `405`.
  There is no DML or deserialization path. (Adding writes back means restoring a
  deserializer + create/update/delete handlers.)
- **to-many linkage** is exposed via relationship endpoints, not inlined into the
  primary `data` (to keep list responses lean). `included` side-loading works for
  to-many.
- **Filtering** supports `eq`/`ne`/`gt`/`gte`/`lt`/`lte`/`like`/`in`/`nin` via
  `filter[attr][op]` (bare `filter[attr]` = `eq`); conditions are AND-ed.
- **OFFSET** is bounded by the platform at 2000 — deep pagination should move to
  keyset/`WHERE Id >` strategies for very large datasets.

---

## 15. Conventions

- Apex API version **65.0**; no namespace.
- All data-access classes are `with sharing`; only `JsonApiRestResource` is
  `global` (required for `@RestResource`).
- Reserved Apex identifiers are avoided (e.g. the sort DTO is `SortField`, not
  `Sort`; the update method is `updateRecord`, not `update`).
- No `return`/`throw` placed after an exhaustive `switch` (Apex flags it as
  unreachable).

---

## 16. Observability

Every request emits one `JsonApiRequestLog` at the HTTP boundary, captured in a
`finally` so it fires on success **and** failure:

| Field | Meaning |
|-------|---------|
| `requestId` | `System.Request.getCurrent().getRequestId()` — correlate with platform debug logs |
| `method` / `path` / `resourceType` | the verb, URI, and first path segment |
| `statusCode` | HTTP status returned |
| `durationMs` | wall-clock latency |
| `soqlQueries` | SOQL consumed (`Limits.getQueries()` delta) |
| `rows` | primary `data` count |
| `errorCode` / `errorReference` | app error code and the 500 reference id, on failure |

`JsonApiObservability.emit()` hands the log to the registered `JsonApiObserver`
and **never throws** — a broken observer can't break the response. The default
`JsonApiDebugObserver` writes one structured JSON line per request (ERROR level
for failures, INFO otherwise), e.g.:

```
JSONAPI {"requestId":"4ab..","method":"GET","apiVersion":"v1","resourceType":"accounts","path":"/services/apexrest/jsonapi/v1/accounts","statusCode":200,"durationMs":42,"soqlQueries":2,"rows":9}
```

To ship telemetry somewhere durable (Platform Event, custom object, external
service), implement `JsonApiObserver` and register it once:

```apex
JsonApiObservability.setObserver(new MyPlatformEventObserver());
```
