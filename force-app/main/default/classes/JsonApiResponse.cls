/**
 * A transport-agnostic result produced by {@link JsonApiService}: an HTTP
 * status, an optional document body and optional extra headers (e.g. Location).
 * The REST layer is responsible for writing this onto RestContext.response.
 */
public class JsonApiResponse {
    public Integer statusCode;
    public JsonApiDocument document;
    public Map<String, String> headers = new Map<String, String>();

    public JsonApiResponse(Integer statusCode, JsonApiDocument document) {
        this.statusCode = statusCode;
        this.document = document;
    }

    public JsonApiResponse withHeader(String name, String value) {
        this.headers.put(name, value);
        return this;
    }

    /** 204 No Content - used by DELETE. */
    public static JsonApiResponse noContent() {
        return new JsonApiResponse(204, null);
    }
}
