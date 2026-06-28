/**
 * A transport-agnostic result produced by {@link JsonApiService}: an HTTP status,
 * an optional document body and optional extra headers. The REST layer writes
 * this onto RestContext.response.
 */
public class JsonApiResponse {
    public Integer statusCode;
    public JsonApiDocument document;
    public Map<String, String> headers = new Map<String, String>();

    public JsonApiResponse(Integer statusCode, JsonApiDocument document) {
        this.statusCode = statusCode;
        this.document = document;
    }
}
