/**
 * A "resource identifier object" - a {type, id} pointer to a resource.
 * @see https://jsonapi.org/format/#document-resource-identifier-objects
 */
public class JsonApiResourceIdentifier {
    public String type;
    public String id;
    public Map<String, Object> meta;

    public JsonApiResourceIdentifier() {}

    public JsonApiResourceIdentifier(String type, String id) {
        this.type = type;
        this.id = id;
    }
}
