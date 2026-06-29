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

    /**
     * Serializes to a JSON string. Absent members are omitted, but a data
     * document's `data` is always present — emitted as `null` for an empty
     * to-one (the spec distinguishes `"data": null` from an absent member).
     *
     * This is done via an explicit map because JSON suppress-nulls drops null
     * Apex-object fields (like `data`) but preserves null map entries.
     */
    public String toJson() {
        Map<String, Object> out = new Map<String, Object>();
        if (jsonapi != null) {
            out.put('jsonapi', jsonapi);
        }
        if (errors != null) {
            out.put('errors', errors);
        } else {
            out.put('data', data); // always present for a data document; null preserved
        }
        if (included != null) {
            out.put('included', included);
        }
        if (meta != null) {
            out.put('meta', meta);
        }
        if (links != null) {
            out.put('links', links);
        }
        return JSON.serialize(out, true);
    }
}
