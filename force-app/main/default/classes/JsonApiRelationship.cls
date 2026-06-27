/**
 * A "relationship object" describing a link between resources.
 * `data` is the resource linkage: a single {@link JsonApiResourceIdentifier}
 * for to-one relationships, or a List for to-many relationships, or null.
 * @see https://jsonapi.org/format/#document-resource-object-relationships
 */
public class JsonApiRelationship {
    public Map<String, Object> links;
    public Object data;
    public Map<String, Object> meta;

    public JsonApiRelationship() {}

    /** Builds a relationship carrying only links (no linkage fetched). */
    public static JsonApiRelationship withLinks(String selfLink, String relatedLink) {
        JsonApiRelationship rel = new JsonApiRelationship();
        rel.links = new Map<String, Object>{
            'self' => selfLink,
            'related' => relatedLink
        };
        return rel;
    }
}
