/**
 * Resolves `include` paths into a deduplicated list of related resource objects
 * for the document's top-level `included` member.
 *
 * Paths are coalesced into a tree first, so a shared prefix is queried only once
 * (e.g. `contacts.account` and `contacts.cases` fetch `contacts` a single time),
 * and each relationship level is queried in bulk for all accumulated parents.
 * @see https://jsonapi.org/format/#fetching-includes
 */
public with sharing class JsonApiIncludeResolver {

    private final JsonApiSerializer serializer;
    private final JsonApiQueryGateway gateway;
    private final String version;

    public JsonApiIncludeResolver(JsonApiSerializer serializer, JsonApiQueryGateway gateway, String version) {
        this.serializer = serializer;
        this.gateway = gateway;
        this.version = version;
    }

    /** A node in the coalesced include tree: relationship name -> sub-paths. */
    private class Node {
        Map<String, Node> children = new Map<String, Node>();
    }

    public List<JsonApiResourceObject> resolve(
        List<SObject> primary,
        JsonApiResourceConfig primaryConfig,
        JsonApiQueryOptions options
    ) {
        Node root = buildTree(options.includePaths);
        Map<String, JsonApiResourceObject> includedByKey =
            new Map<String, JsonApiResourceObject>();
        walk(primary, primaryConfig, root, options, includedByKey);
        return includedByKey.values();
    }

    /** Folds the list of dotted paths into a prefix tree. */
    private Node buildTree(List<String> paths) {
        Node root = new Node();
        for (String path : paths) {
            Node cursor = root;
            for (String segment : path.split('\\.')) {
                if (!cursor.children.containsKey(segment)) {
                    cursor.children.put(segment, new Node());
                }
                cursor = cursor.children.get(segment);
            }
        }
        return root;
    }

    /** One bulk query per relationship per level, deduped by `type:id`. */
    private void walk(
        List<SObject> parents,
        JsonApiResourceConfig parentConfig,
        Node node,
        JsonApiQueryOptions options,
        Map<String, JsonApiResourceObject> acc
    ) {
        if (parents.isEmpty() || node.children.isEmpty()) {
            return;
        }
        for (String relName : node.children.keySet()) {
            JsonApiRelationshipDef def = parentConfig.relationshipFor(relName);
            if (def == null) {
                throw JsonApiException.badRequest(
                    'Cannot include unknown relationship "' + relName + '".',
                    JsonApiErrorSource.forParameter(JsonApiConstants.PARAM_INCLUDE));
            }
            JsonApiResourceConfig targetConfig = JsonApiRegistry.forType(version, def.targetType);
            List<SObject> related = fetchRelated(parents, def, targetConfig, options);

            for (SObject r : related) {
                JsonApiResourceObject obj = serializer.toResource(r, targetConfig, options);
                acc.put(obj.key(), obj);
            }
            walk(related, targetConfig, node.children.get(relName), options, acc);
        }
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

        return gateway.query(soql, binds);
    }

    /** Mirrors the builder's field selection for related resources. */
    private Set<String> selectFields(JsonApiResourceConfig config, JsonApiQueryOptions options) {
        Set<String> fields = new Set<String>{ 'Id' };
        for (String attr : config.resolveAttributeNames(options)) {
            fields.add(config.fieldFor(attr));
        }
        for (JsonApiRelationshipDef def : config.relationships().values()) {
            if (!def.isToMany && def.lookupField != null) {
                fields.add(def.lookupField);
            }
        }
        return fields;
    }
}
