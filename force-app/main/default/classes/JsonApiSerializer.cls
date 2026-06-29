/**
 * Converts SObject records into JSON:API resource objects, honouring sparse
 * fieldsets and emitting relationship linkage for to-one relationships.
 */
public with sharing class JsonApiSerializer {

    private final String baseUrl;

    /** @param baseUrl absolute base path of the API, e.g. /services/apexrest/jsonapi */
    public JsonApiSerializer(String baseUrl) {
        this.baseUrl = baseUrl == null ? '' : baseUrl;
    }

    public List<JsonApiResourceObject> toResources(
        List<SObject> records,
        JsonApiResourceConfig config,
        JsonApiQueryOptions options
    ) {
        List<JsonApiResourceObject> result = new List<JsonApiResourceObject>();
        for (SObject record : records) {
            result.add(toResource(record, config, options));
        }
        return result;
    }

    public JsonApiResourceObject toResource(
        SObject record,
        JsonApiResourceConfig config,
        JsonApiQueryOptions options
    ) {
        String type = config.getType();
        String id = String.valueOf(record.get('Id'));
        JsonApiResourceObject resource = new JsonApiResourceObject(type, id);

        // Attributes: sparse fieldset (if any) or base + `extend` groups.
        for (String attr : config.resolveAttributeNames(options)) {
            resource.putAttribute(attr, record.get(config.fieldFor(attr)));
        }

        // Relationships: a sparse fieldset can restrict which are emitted;
        // the `extend` groups affect attributes only, not relationships.
        Set<String> sparse = options != null && options.hasSparseFieldsFor(type)
            ? options.sparseFieldsFor(type)
            : null;
        for (JsonApiRelationshipDef def : config.getRelationships().values()) {
            if (sparse != null && !sparse.contains(def.name)) {
                continue;
            }
            resource.putRelationship(def.name, buildRelationship(record, id, type, def));
        }

        resource.links = new Map<String, Object>{ 'self' => resourceUrl(type, id) };
        return resource;
    }

    private Map<String, Object> buildRelationship(
        SObject record,
        String parentId,
        String parentType,
        JsonApiRelationshipDef def
    ) {
        Map<String, Object> rel = new Map<String, Object>{
            'links' => new Map<String, Object>{
                'self' => resourceUrl(parentType, parentId) + '/relationships/' + def.name,
                'related' => resourceUrl(parentType, parentId) + '/' + def.name
            }
        };

        if (!def.isToMany && def.lookupField != null) {
            // Emit explicit linkage: an identifier when set, or `null` (spec
            // requires null — not an absent member — for an empty to-one).
            Object lookupId = record.get(def.lookupField);
            rel.put('data', lookupId == null
                ? null
                : new JsonApiResourceIdentifier(def.targetType, String.valueOf(lookupId)));
        }
        // to-many linkage is exposed via the relationship endpoints, not inlined.
        return rel;
    }

    public String resourceUrl(String type, String id) {
        return baseUrl + '/' + type + '/' + id;
    }

    public String collectionUrl(String type) {
        return baseUrl + '/' + type;
    }
}
