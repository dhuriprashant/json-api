/**
 * A "resource object" - the representation of a single record.
 * @see https://jsonapi.org/format/#document-resource-objects
 */
public class JsonApiResourceObject {
    public String type;
    public String id;
    public Map<String, Object> attributes;
    /**
     * Relationship name -> relationship object (itself a Map with `links` and,
     * for to-one, explicit `data` linkage). A Map is used rather than a typed
     * class so that an empty to-one linkage serializes as `"data": null` — null
     * map entries survive JSON suppress-nulls, whereas null Apex-object fields
     * do not.
     */
    public Map<String, Object> relationships;
    public Map<String, Object> links;
    public Map<String, Object> meta;

    public JsonApiResourceObject() {
        this.attributes = new Map<String, Object>();
    }

    public JsonApiResourceObject(String type, String id) {
        this();
        this.type = type;
        this.id = id;
    }

    public void putAttribute(String name, Object value) {
        if (this.attributes == null) {
            this.attributes = new Map<String, Object>();
        }
        this.attributes.put(name, value);
    }

    public void putRelationship(String name, Map<String, Object> rel) {
        if (this.relationships == null) {
            this.relationships = new Map<String, Object>();
        }
        this.relationships.put(name, rel);
    }

    /** A {type, id} pair uniquely identifies a resource object across a document. */
    public String key() {
        return this.type + ':' + this.id;
    }
}
