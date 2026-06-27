/**
 * The top-level object of every JSON:API request and response document.
 * A document MUST contain at least one of `data`, `errors`, or `meta`, and
 * `data` and `errors` MUST NOT coexist.
 * @see https://jsonapi.org/format/#document-top-level
 */
public class JsonApiDocument {
    /**
     * The document's primary data: a single {@link JsonApiResourceObject},
     * a List of them, a {@link JsonApiResourceIdentifier} (or List) for
     * relationship endpoints, or null.
     */
    public Object data;
    public List<JsonApiError> errors;
    public Map<String, Object> meta;
    public List<JsonApiResourceObject> included;
    public Map<String, Object> links;
    public Map<String, Object> jsonapi;

    public JsonApiDocument() {}

    /** Wraps primary data and stamps the document with the spec version. */
    public static JsonApiDocument ofData(Object data) {
        JsonApiDocument doc = new JsonApiDocument();
        doc.data = data;
        doc.jsonapi = new Map<String, Object>{ 'version' => JsonApiConstants.VERSION };
        return doc;
    }

    /** Wraps a collection of errors. */
    public static JsonApiDocument ofErrors(List<JsonApiError> errors) {
        JsonApiDocument doc = new JsonApiDocument();
        doc.errors = errors;
        doc.jsonapi = new Map<String, Object>{ 'version' => JsonApiConstants.VERSION };
        return doc;
    }

    public void addIncluded(JsonApiResourceObject resource) {
        if (this.included == null) {
            this.included = new List<JsonApiResourceObject>();
        }
        this.included.add(resource);
    }

    /** Serializes to a JSON string, omitting absent (null) members per the spec. */
    public String toJson() {
        return JSON.serialize(this, true);
    }
}
