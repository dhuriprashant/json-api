/**
 * Resolves `include` paths into a deduplicated list of related resource objects
 * for the document's top-level `included` member. Supports multi-segment paths
 * (e.g. "contacts.account") by walking one relationship at a time and querying
 * each level in bulk.
 * @see https://jsonapi.org/format/#fetching-includes
 */
public with sharing class JsonApiIncludeResolver {

    private final JsonApiSerializer serializer;

    public JsonApiIncludeResolver(JsonApiSerializer serializer) {
        this.serializer = serializer;
    }

    public List<JsonApiResourceObject> resolve(
        List<SObject> primary,
        JsonApiResourceConfig primaryConfig,
        JsonApiQueryOptions options
    ) {
        Map<String, JsonApiResourceObject> includedByKey =
            new Map<String, JsonApiResourceObject>();
        for (String path : options.includePaths) {
            resolvePath(primary, primaryConfig, path.split('\\.'), 0, options, includedByKey);
        }
        return includedByKey.values();
    }

    private void resolvePath(
        List<SObject> parents,
        JsonApiResourceConfig parentConfig,
        List<String> segments,
        Integer idx,
        JsonApiQueryOptions options,
        Map<String, JsonApiResourceObject> acc
    ) {
        if (idx >= segments.size() || parents.isEmpty()) {
            return;
        }
        JsonApiRelationshipDef def = parentConfig.relationshipFor(segments[idx]);
        if (def == null) {
            throw JsonApiException.badRequest(
                'Cannot include unknown relationship "' + segments[idx] + '".',
                JsonApiErrorSource.forParameter(JsonApiConstants.PARAM_INCLUDE));
        }

        JsonApiResourceConfig targetConfig = JsonApiRegistry.forType(def.targetType);
        List<SObject> related = fetchRelated(parents, def, targetConfig, options);

        for (SObject r : related) {
            JsonApiResourceObject obj = serializer.toResource(r, targetConfig, options);
            acc.put(obj.key(), obj);
        }
        // Walk to the next segment using the records we just fetched as parents.
        resolvePath(related, targetConfig, segments, idx + 1, options, acc);
    }

    private List<SObject> fetchRelated(
        List<SObject> parents,
        JsonApiRelationshipDef def,
        JsonApiResourceConfig targetConfig,
        JsonApiQueryOptions options
    ) {
        String fields = String.join(new List<String>(selectFields(targetConfig, options)), ', ');
        String objectName = String.valueOf(targetConfig.getSObjectType());
        Map<String, Object> binds = new Map<String, Object>();
        String soql;

        if (def.isToMany) {
            Set<Id> parentIds = new Set<Id>();
            for (SObject p : parents) {
                parentIds.add((Id) p.get('Id'));
            }
            if (parentIds.isEmpty()) {
                return new List<SObject>();
            }
            binds.put('ids', parentIds);
            soql = 'SELECT ' + fields + ' FROM ' + objectName +
                ' WHERE ' + def.childForeignKeyField + ' IN :ids';
        } else {
            Set<Id> lookupIds = new Set<Id>();
            for (SObject p : parents) {
                Object v = p.get(def.lookupField);
                if (v != null) {
                    lookupIds.add((Id) v);
                }
            }
            if (lookupIds.isEmpty()) {
                return new List<SObject>();
            }
            binds.put('ids', lookupIds);
            soql = 'SELECT ' + fields + ' FROM ' + objectName + ' WHERE Id IN :ids';
        }

        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    /** Mirrors the builder's field selection for related resources. */
    private Set<String> selectFields(JsonApiResourceConfig config, JsonApiQueryOptions options) {
        Set<String> fields = new Set<String>{ 'Id' };
        for (String attr : config.resolveAttributeNames(options)) {
            fields.add(config.fieldFor(attr));
        }
        for (JsonApiRelationshipDef def : config.getRelationships().values()) {
            if (!def.isToMany && def.lookupField != null) {
                fields.add(def.lookupField);
            }
        }
        return fields;
    }
}
