/**
 * Identifies the origin of an error within the request.
 * @see https://jsonapi.org/format/#error-objects
 */
public class JsonApiErrorSource {
    /** JSON Pointer (RFC 6901) to the offending member, e.g. "/data/attributes/name". */
    public String pointer;
    /** The query parameter that caused the error, e.g. "include". */
    public String parameter;
    /** The request header that caused the error. */
    public String header;

    public static JsonApiErrorSource forPointer(String pointer) {
        JsonApiErrorSource s = new JsonApiErrorSource();
        s.pointer = pointer;
        return s;
    }

    public static JsonApiErrorSource forParameter(String parameter) {
        JsonApiErrorSource s = new JsonApiErrorSource();
        s.parameter = parameter;
        return s;
    }
}
