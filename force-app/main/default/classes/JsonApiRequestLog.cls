/**
 * Per-request telemetry captured at the HTTP boundary and handed to a
 * {@link JsonApiObserver}. All fields are best-effort and may be null.
 */
public class JsonApiRequestLog {
    /** Platform request id, for correlating with debug logs. */
    public String requestId;
    public String method;
    /** API version segment, e.g. "v1". */
    public String apiVersion;
    /** The resource type segment, e.g. "accounts". */
    public String resourceType;
    /** Full request URI path. */
    public String path;
    public Integer statusCode;
    /** Wall-clock duration of the request in milliseconds. */
    public Long durationMs;
    /** SOQL queries consumed by the request. */
    public Integer soqlQueries;
    /** Count of primary `data` records returned (collection size, or 1, or 0). */
    public Integer rows;
    /** Application error code on failure (e.g. "NOT_FOUND"). */
    public String errorCode;
    /** The 500 reference id, when applicable, for support correlation. */
    public String errorReference;

    public Boolean isError() {
        return statusCode != null && statusCode >= 400;
    }
}
