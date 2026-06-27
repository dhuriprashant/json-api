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

        Set<String> requested = options != null && options.hasSparseFieldsFor(type)
            ? options.sparseFieldsFor(type)
            : null;

        // Attributes
        for (String attr : config.getAttributeMap().keySet()) {
            if (requested == null || requested.contains(attr)) {
                resource.putAttribute(attr, record.get(config.fieldFor(attr)));
            }
        }

        // Relationships
        for (JsonApiRelationshipDef def : config.getRelationships().values()) {
            if (requested != null && !requested.contains(def.name)) {
                continue;
            }
            resource.putRelationship(def.name, buildRelationship(record, id, type, def));
        }

        resource.links = new Map<String, Object>{ 'self' => resourceUrl(type, id) };
        return resource;
    }

    private JsonApiRelationship buildRelationship(
        SObject record,
        String parentId,
        String parentType,
        JsonApiRelationshipDef def
    ) {
        JsonApiRelationship rel = JsonApiRelationship.withLinks(
            resourceUrl(parentType, parentId) + '/relationships/' + def.name,
            resourceUrl(parentType, parentId) + '/' + def.name
        );

        if (!def.isToMany && def.lookupField != null) {
            Object lookupId = record.get(def.lookupField);
            rel.data = lookupId == null
                ? null
                : new JsonApiResourceIdentifier(def.targetType, String.valueOf(lookupId));
        }
        // to-many linkage is populated by the include resolver when requested.
        return rel;
    }

    public String resourceUrl(String type, String id) {
        return baseUrl + '/' + type + '/' + id;
    }

    public String collectionUrl(String type) {
        return baseUrl + '/' + type;
    }
}
