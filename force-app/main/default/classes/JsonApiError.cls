/**
 * An "error object" providing additional information about problems.
 * @see https://jsonapi.org/format/#error-objects
 */
public class JsonApiError {
    public String id;
    /** HTTP status code, as a string, e.g. "404". */
    public String status;
    /** An application-specific error code. */
    public String code;
    /** A short, human-readable summary of the problem. */
    public String title;
    /** A human-readable explanation specific to this occurrence. */
    public String detail;
    public JsonApiErrorSource source;
    public Map<String, Object> links;
    public Map<String, Object> meta;

    public JsonApiError() {}

    public JsonApiError(Integer httpStatus, String code, String title, String detail) {
        this.status = String.valueOf(httpStatus);
        this.code = code;
        this.title = title;
        this.detail = detail;
    }

    public JsonApiError withSource(JsonApiErrorSource src) {
        this.source = src;
        return this;
    }
}
