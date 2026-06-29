# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A configuration-driven Apex framework that exposes Salesforce SObjects over a REST API conforming to [JSON:API v1.1](https://jsonapi.org/format/). All code lives in `force-app/main/default/classes/` (Apex `.cls` + `.cls-meta.xml`). There is no LWC, no JS build — it is a pure Apex Salesforce DX project.

Two reference resources ship: `accounts` (Account) and `contacts` (Contact). Full endpoint/query-param reference and a "how to add a resource" walkthrough live in `force-app/main/default/classes/JSON-API-README.md`.

## Commands

The framework's own tests are run as a named set (`RunSpecifiedTests`) so unrelated broken tests in the target org don't block it.

```powershell
# Deploy
sf project deploy start -d force-app -o <org>

# Validate without saving (compiles + runs this framework's tests, persists nothing)
sf project deploy validate -d force-app -o <org> -l RunSpecifiedTests `
  -t JsonApiServiceTest -t JsonApiRequestParserTest `
  -t JsonApiRestResourceTest -t JsonApiCoverageTest -t JsonApiUnitTest

# Run the test suite with coverage
sf apex run test -o <org> -l RunSpecifiedTests -c `
  -t JsonApiServiceTest -t JsonApiRequestParserTest `
  -t JsonApiRestResourceTest -t JsonApiCoverageTest -t JsonApiUnitTest

# Run a single test class
sf apex run test -o <org> -l RunSpecifiedTests -t JsonApiServiceTest -c
```

The test classes are `JsonApiServiceTest`, `JsonApiRequestParserTest`, `JsonApiRestResourceTest`, `JsonApiCoverageTest`, and `JsonApiUnitTest` (`JsonApiTestQueryGateway` is a shared `@IsTest` mock, not a runnable suite). `JsonApiUnitTest` and `JsonApiRequestParserTest` are **DML-free** (they use the in-memory `JsonApiQueryGateway` / no SObjects) and run even in orgs with broken triggers; the other three insert real `Account`/`Contact` records, so a broken Account/Contact trigger in the target org will fail them (an org problem, not a framework one). Validate the full suite in a clean scratch org.

## Request flow

A request walks one path through the layers; understanding this sequence is the fastest way to orient:

1. **`JsonApiRestResource`** (`@RestResource(urlMapping='/jsonapi/*')`) — the only HTTP entry point. Handles HTTP concerns only: content negotiation (enforces the `application/vnd.api+json` media type → 406), splits the URI into path segments after the `jsonapi` base, catches exceptions and renders them, and (in a `finally`) emits a `JsonApiRequestLog` to the active `JsonApiObserver` via `JsonApiObservability`. Delegates everything else to the service.
2. **`JsonApiService`** — the orchestration core. Contains the routing table (maps verb + segment shape to an operation). All data access goes through a `JsonApiQueryGateway` (default `JsonApiUserModeGateway`, which runs every query in `AccessLevel.USER_MODE`); a `@TestVisible` constructor accepts an in-memory gateway for DML-free unit tests.
3. **`JsonApiRegistry` / `JsonApiBootstrap`** — `forType(type)` resolves the JSON:API type string to its config, throwing 404 if unregistered. The registry lazily self-initializes by calling `JsonApiBootstrap.registerAll()` on first lookup.
4. **`JsonApiRequestParser` → `JsonApiQueryOptions`** — parses query params (`include`, `fields[]`, `sort`, `filter[]`, `page[]`, `extend`) into a typed options object. `extend` names attribute groups to add on top of the always-returned `base` group.
5. **`JsonApiQueryBuilder`** — builds SOQL strings + a `binds` map from config + options. All field/object names come from configs (never user input); all filter values are bind variables — no SOQL injection.
6. **`JsonApiSerializer` / `JsonApiIncludeResolver`** — convert SObjects → the document model. The include resolver populates the top-level `included` array.
7. **Document model** — `JsonApiDocument`, `JsonApiResourceObject`, `JsonApiResourceIdentifier`, `JsonApiError`, `JsonApiErrorSource`. `JsonApiResponse` wraps status + headers + document. Relationship objects are plain `Map`s (not a typed class) so an empty to-one serializes as explicit `"data": null`; `JsonApiDocument.toJson()` builds the top level as a map for the same reason (JSON suppress-nulls drops null Apex fields but keeps null map entries).
8. **`JsonApiException`** — typed errors with factory methods (`notFound`, `badRequest`, `conflict`, `unsupportedMediaType`, etc.) carrying HTTP status + JSON:API `errors[]`.

`JsonApiConstants` holds the media type and `BASE_PATH`.

## Adding a resource (the central extension point)

The whole framework is driven by `JsonApiResourceConfig` subclasses. To expose a new SObject:

1. Subclass `JsonApiResourceConfig`. Three abstract methods are required: `getType()` (the JSON:API type string), `getSObjectType()`, and `getAttributeGroups()` (group name → map of JSON:API attribute name → SObject field API name; **do not** map `id` here). The `base` group is always returned; other groups are returned only when the client opts in via the `extend` query param (e.g. `?extend=financials`). Optionally override `getRelationships()`. See `AccountResourceConfig` / `ContactResourceConfig`.
2. Add a `JsonApiResource__mdt` Custom Metadata record whose `Apex_Class__c` is your config class name and `Is_Active__c` is checked (see `customMetadata/JsonApiResource.Accounts.md-meta.xml`). `JsonApiBootstrap.registerAll()` loads active records and instantiates each via `Type.forName().newInstance()` — no Apex change to the framework is needed.

Relationships are declared via `JsonApiRelationshipDef.toOne(name, targetType, lookupField)` (lookup field on this object) or `JsonApiRelationshipDef.toMany(name, targetType, childForeignKeyField)` (FK field on the child object).

## Conventions & constraints

- Apex API version is `65.0` (`sfdx-project.json`); no namespace.
- Read-only: only `GET` is implemented. `JsonApiService.handle` rejects any non-GET verb with 405, and `JsonApiRestResource` exposes only `@HttpGet`. There is no create/update/delete path or deserializer.
- All data access must stay in `AccessLevel.USER_MODE` to keep CRUD/FLS enforcement — preserve this in any new query/DML path.
- Attributes are grouped via `getAttributeGroups()`; `base` is always returned, other groups only via `?extend=group1,group2`. A sparse `fields[type]` set takes precedence over `extend`. `resolveAttributeNames()` is the single source of truth used by the builder, serializer, and include resolver.
- Filtering supports operators via `filter[attr][op]` (`eq`/`ne`/`gt`/`gte`/`lt`/`lte`/`like`/`in`/`nin`; bare `filter[attr]` = `eq`, and `in`/`nin` take a comma-separated list). Conditions are AND-ed; `JsonApiQueryOptions.filters` is a `List<FilterCondition>` (multiple conditions may target one attribute, e.g. a gt/lt range). Add operators in `JsonApiQueryBuilder.buildClause()`. Values are always bound, never interpolated.
- `include` inlines the `included` array and to-one linkage; to-many linkage is exposed via the relationship endpoints, not inlined in primary `data`.
- `GET /_health` is a reserved diagnostics route (matched in `JsonApiService.handle` before the registry lookup, since `_health` is not a resource type). It returns a meta-only document (`JsonApiDocument.ofMeta`) listing registered resources + `JsonApiBootstrap.getRegistrationErrors()`; `200` when all CMDT records loaded, `503` when any was skipped. Meta-only docs omit the `data` member entirely (the `isDataDocument` flag distinguishes them from a data doc whose `data` is an explicit `null`).
- Bulk/atomic operations and writes to relationship endpoints are not implemented.
