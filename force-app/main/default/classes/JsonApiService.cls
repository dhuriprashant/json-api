/**
 * The orchestration core of the framework. Given an HTTP method, the path
 * segments after the API base, the query parameters and an optional request
 * body, it performs the matching JSON:API operation and returns a
 * {@link JsonApiResponse}.
 *
 * Routing table:
 *   GET    /{type}                          collection
 *   GET    /{type}/{id}                      single resource
 *   GET    /{type}/{id}/{relationship}       related resource(s)
 *   GET    /{type}/{id}/relationships/{rel}  relationship linkage
 *   POST   /{type}                           create
 *   PATCH  /{type}/{id}                       update
 *   DELETE /{type}/{id}                       delete
 *
 * All SOQL and DML run in AccessLevel.USER_MODE, so object- and field-level
 * security is enforced by the platform on the running user's behalf.
 */
public with sharing class JsonApiService {

    private final String baseUrl = JsonApiConstants.BASE_PATH;
    private final JsonApiSerializer serializer = new JsonApiSerializer(JsonApiConstants.BASE_PATH);

    public JsonApiResponse handle(
        String method,
        List<String> segments,
        Map<String, String> params,
        String body
    ) {
        if (segments == null || segments.isEmpty()) {
            throw JsonApiException.badRequest('A resource type is required in the path.', null);
        }
        String type = segments[0];
        JsonApiResourceConfig config = JsonApiRegistry.forType(type);

        switch on method.toUpperCase() {
            when 'GET' {
                return handleGet(config, segments, params);
            }
            when 'POST' {
                requireCollection(segments);
                return create(config, body);
            }
            when 'PATCH' {
                String id = requireResourceId(segments);
                return updateRecord(config, id, body);
            }
            when 'DELETE' {
                String id = requireResourceId(segments);
                return remove(config, id);
            }
            when else {
                throw JsonApiException.methodNotAllowed('Method "' + method + '" is not supported.');
            }
        }
    }

    // ---------------------------------------------------------------------
    // GET
    // ---------------------------------------------------------------------

    private JsonApiResponse handleGet(
        JsonApiResourceConfig config,
        List<String> segments,
        Map<String, String> params
    ) {
        JsonApiQueryOptions options = JsonApiRequestParser.parse(params, config);

        if (segments.size() == 1) {
            return getCollection(config, options);
        }
        String id = segments[1];
        if (segments.size() == 2) {
            return getSingle(config, id, options);
        }
        // /{type}/{id}/relationships/{rel}
        if (segments.size() == 4 && segments[2] == 'relationships') {
            return getRelationshipLinkage(config, id, segments[3]);
        }
        // /{type}/{id}/{relationship}
        if (segments.size() == 3) {
            return getRelated(config, id, segments[2], options, params);
        }
        throw JsonApiException.notFound('Unrecognized resource path.');
    }

    private JsonApiResponse getCollection(JsonApiResourceConfig config, JsonApiQueryOptions options) {
        JsonApiQueryBuilder builder = new JsonApiQueryBuilder(config, options);
        List<SObject> records = Database.queryWithBinds(
            builder.buildCollectionQuery(), builder.binds, AccessLevel.USER_MODE);

        JsonApiDocument doc = JsonApiDocument.ofData(serializer.toResources(records, config, options));
        addIncluded(doc, records, config, options);

        Integer total = Database.countQueryWithBinds(builder.buildCountQuery(), builder.binds, AccessLevel.USER_MODE);
        doc.meta = new Map<String, Object>{ 'total' => total };
        doc.links = paginationLinks(config, options, builder, total);
        return new JsonApiResponse(200, doc);
    }

    private JsonApiResponse getSingle(JsonApiResourceConfig config, String id, JsonApiQueryOptions options) {
        SObject record = queryOne(config, id, options);
        if (record == null) {
            throw JsonApiException.notFound('No ' + config.getType() + ' with id "' + id + '".');
        }
        JsonApiDocument doc = JsonApiDocument.ofData(serializer.toResource(record, config, options));
        addIncluded(doc, new List<SObject>{ record }, config, options);
        return new JsonApiResponse(200, doc);
    }

    private JsonApiResponse getRelated(
        JsonApiResourceConfig config,
        String id,
        String relName,
        JsonApiQueryOptions options,
        Map<String, String> params
    ) {
        JsonApiRelationshipDef def = config.relationshipFor(relName);
        if (def == null) {
            throw JsonApiException.notFound('No relationship "' + relName + '" on ' + config.getType() + '.');
        }
        JsonApiResourceConfig targetConfig = JsonApiRegistry.forType(def.targetType);
        JsonApiQueryOptions targetOptions = JsonApiRequestParser.parse(params, targetConfig);
        SObject parent = queryOne(config, id, new JsonApiQueryOptions());
        if (parent == null) {
            throw JsonApiException.notFound('No ' + config.getType() + ' with id "' + id + '".');
        }

        if (def.isToMany) {
            List<SObject> related = queryChildren(def, targetConfig, id, targetOptions);
            return new JsonApiResponse(200,
                JsonApiDocument.ofData(serializer.toResources(related, targetConfig, targetOptions)));
        }
        Object lookupId = parent.get(def.lookupField);
        Object data = null;
        if (lookupId != null) {
            SObject related = queryOne(targetConfig, String.valueOf(lookupId), targetOptions);
            data = related == null ? null : serializer.toResource(related, targetConfig, targetOptions);
        }
        return new JsonApiResponse(200, JsonApiDocument.ofData(data));
    }

    private JsonApiResponse getRelationshipLinkage(JsonApiResourceConfig config, String id, String relName) {
        JsonApiRelationshipDef def = config.relationshipFor(relName);
        if (def == null) {
            throw JsonApiException.notFound('No relationship "' + relName + '" on ' + config.getType() + '.');
        }
        if (def.isToMany) {
            List<SObject> children = queryChildren(def, JsonApiRegistry.forType(def.targetType), id, new JsonApiQueryOptions());
            List<JsonApiResourceIdentifier> ids = new List<JsonApiResourceIdentifier>();
            for (SObject c : children) {
                ids.add(new JsonApiResourceIdentifier(def.targetType, String.valueOf(c.get('Id'))));
            }
            return new JsonApiResponse(200, JsonApiDocument.ofData(ids));
        }
        SObject parent = queryOne(config, id, new JsonApiQueryOptions());
        if (parent == null) {
            throw JsonApiException.notFound('No ' + config.getType() + ' with id "' + id + '".');
        }
        Object lookupId = parent.get(def.lookupField);
        Object data = lookupId == null
            ? null
            : new JsonApiResourceIdentifier(def.targetType, String.valueOf(lookupId));
        return new JsonApiResponse(200, JsonApiDocument.ofData(data));
    }

    // ---------------------------------------------------------------------
    // POST / PATCH / DELETE
    // ---------------------------------------------------------------------

    private JsonApiResponse create(JsonApiResourceConfig config, String body) {
        SObject record = new JsonApiDeserializer().toSObject(parseBodyData(body), config, false);
        Database.SaveResult sr = Database.insert(record, true, AccessLevel.USER_MODE);
        if (!sr.isSuccess()) {
            throw toException(sr.getErrors());
        }
        SObject reloaded = queryOne(config, sr.getId(), new JsonApiQueryOptions());
        JsonApiDocument doc = JsonApiDocument.ofData(serializer.toResource(reloaded, config, new JsonApiQueryOptions()));
        return new JsonApiResponse(201, doc)
            .withHeader('Location', serializer.resourceUrl(config.getType(), sr.getId()));
    }

    private JsonApiResponse updateRecord(JsonApiResourceConfig config, String id, String body) {
        Object data = parseBodyData(body);
        SObject record = new JsonApiDeserializer().toSObject(data, config, true);
        if (String.valueOf(record.get('Id')) != id) {
            throw JsonApiException.conflict('The id in the request body does not match the id in the URL.');
        }
        Database.SaveResult sr = Database.update(record, true, AccessLevel.USER_MODE);
        if (!sr.isSuccess()) {
            throw toException(sr.getErrors());
        }
        SObject reloaded = queryOne(config, id, new JsonApiQueryOptions());
        return new JsonApiResponse(200,
            JsonApiDocument.ofData(serializer.toResource(reloaded, config, new JsonApiQueryOptions())));
    }

    private JsonApiResponse remove(JsonApiResourceConfig config, String id) {
        SObject record = queryOne(config, id, new JsonApiQueryOptions());
        if (record == null) {
            throw JsonApiException.notFound('No ' + config.getType() + ' with id "' + id + '".');
        }
        Database.DeleteResult dr = Database.delete(record, true, AccessLevel.USER_MODE);
        if (!dr.isSuccess()) {
            throw toException(dr.getErrors());
        }
        return JsonApiResponse.noContent();
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    private SObject queryOne(JsonApiResourceConfig config, String id, JsonApiQueryOptions options) {
        if (!isValidId(id, config)) {
            throw JsonApiException.badRequest('"' + id + '" is not a valid id.', JsonApiErrorSource.forPointer('/data/id'));
        }
        JsonApiQueryBuilder builder = new JsonApiQueryBuilder(config, options);
        Id recordId = (Id) id;
        List<SObject> records = Database.queryWithBinds(
            builder.buildSingleQuery(recordId), builder.binds, AccessLevel.USER_MODE);
        return records.isEmpty() ? null : records[0];
    }

    private List<SObject> queryChildren(
        JsonApiRelationshipDef def,
        JsonApiResourceConfig targetConfig,
        String parentId,
        JsonApiQueryOptions options
    ) {
        JsonApiQueryBuilder builder = new JsonApiQueryBuilder(targetConfig, options);
        // Reuse collection select/sort/paging but scope to the parent via the FK.
        String soql = builder.buildCollectionQuery();
        // Inject the FK filter ahead of ORDER BY/LIMIT by rebuilding minimally.
        Map<String, Object> binds = builder.binds.clone();
        binds.put('parentId', (Id) parentId);
        soql = injectWhere(soql, def.childForeignKeyField + ' = :parentId');
        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    /** Inserts (or ANDs) a clause into an already-built SOQL string. */
    private String injectWhere(String soql, String clause) {
        Integer orderIdx = soql.indexOfIgnoreCase(' ORDER BY ');
        Integer limitIdx = soql.indexOfIgnoreCase(' LIMIT ');
        Integer cut = orderIdx >= 0 ? orderIdx : (limitIdx >= 0 ? limitIdx : soql.length());
        String head = soql.substring(0, cut);
        String tail = soql.substring(cut);
        if (head.containsIgnoreCase(' WHERE ')) {
            head += ' AND ' + clause;
        } else {
            head += ' WHERE ' + clause;
        }
        return head + tail;
    }

    private void addIncluded(
        JsonApiDocument doc,
        List<SObject> records,
        JsonApiResourceConfig config,
        JsonApiQueryOptions options
    ) {
        if (options.includePaths.isEmpty() || records.isEmpty()) {
            return;
        }
        List<JsonApiResourceObject> included =
            new JsonApiIncludeResolver(serializer).resolve(records, config, options);
        if (!included.isEmpty()) {
            doc.included = included;
        }
    }

    private Map<String, Object> paginationLinks(
        JsonApiResourceConfig config,
        JsonApiQueryOptions options,
        JsonApiQueryBuilder builder,
        Integer total
    ) {
        Integer size = builder.effectiveLimit();
        Integer offset = builder.effectiveOffset();
        String base = serializer.collectionUrl(config.getType());

        Map<String, Object> links = new Map<String, Object>();
        links.put('self', pageLink(base, offset, size));
        links.put('first', pageLink(base, 0, size));
        Integer lastOffset = total == 0 ? 0 : ((total - 1) / size) * size;
        links.put('last', pageLink(base, lastOffset, size));
        links.put('prev', offset > 0 ? pageLink(base, Math.max(offset - size, 0), size) : null);
        links.put('next', (offset + size) < total ? pageLink(base, offset + size, size) : null);
        return links;
    }

    private String pageLink(String base, Integer offset, Integer size) {
        return base + '?page[offset]=' + offset + '&page[limit]=' + size;
    }

    private Object parseBodyData(String body) {
        if (String.isBlank(body)) {
            throw JsonApiException.badRequest('A request body is required.', JsonApiErrorSource.forPointer('/data'));
        }
        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            throw JsonApiException.badRequest('Request body is not valid JSON.', JsonApiErrorSource.forPointer('/data'));
        }
        if (!parsed.containsKey('data')) {
            throw JsonApiException.badRequest('Request document must contain a "data" member.', JsonApiErrorSource.forPointer('/data'));
        }
        return parsed.get('data');
    }

    private Boolean isValidId(String id, JsonApiResourceConfig config) {
        try {
            Id parsed = (Id) id;
            return parsed.getSObjectType() == config.getSObjectType();
        } catch (Exception e) {
            return false;
        }
    }

    private JsonApiException toException(List<Database.Error> errors) {
        List<JsonApiError> apiErrors = new List<JsonApiError>();
        for (Database.Error e : errors) {
            apiErrors.add(new JsonApiError(422, String.valueOf(e.getStatusCode()),
                'Unprocessable Entity', e.getMessage()));
        }
        return new JsonApiException(422, apiErrors);
    }

    private void requireCollection(List<String> segments) {
        if (segments.size() != 1) {
            throw JsonApiException.methodNotAllowed('POST is only supported on a collection (/{type}).');
        }
    }

    private String requireResourceId(List<String> segments) {
        if (segments.size() != 2) {
            throw JsonApiException.methodNotAllowed('This method requires a path of /{type}/{id}.');
        }
        return segments[1];
    }
}
