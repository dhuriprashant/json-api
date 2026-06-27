/**
 * The single exception type the framework throws. It carries an HTTP status
 * and one or more {@link JsonApiError} objects so the REST layer can render a
 * spec-compliant error document and set the correct response code.
 *
 * Use the static factories for the common cases rather than constructing
 * errors by hand.
 */
public class JsonApiException extends Exception {
    public Integer httpStatus { get; private set; }
    public List<JsonApiError> errors { get; private set; }

    public JsonApiException(Integer httpStatus, List<JsonApiError> errors) {
        // Use the first error's detail as the Apex message for logging.
        this(buildMessage(errors));
        this.httpStatus = httpStatus;
        this.errors = errors;
    }

    public JsonApiException(Integer httpStatus, JsonApiError error) {
        this(httpStatus, new List<JsonApiError>{ error });
    }

    private static String buildMessage(List<JsonApiError> errors) {
        List<String> parts = new List<String>();
        for (JsonApiError e : errors) {
            parts.add((e.title != null ? e.title : '') +
                (e.detail != null ? ': ' + e.detail : ''));
        }
        return String.join(parts, '; ');
    }

    // ---------------------------------------------------------------------
    // Factories for the standard HTTP error conditions
    // ---------------------------------------------------------------------

    public static JsonApiException badRequest(String detail, JsonApiErrorSource source) {
        JsonApiError err = new JsonApiError(400, 'BAD_REQUEST', 'Bad Request', detail);
        err.source = source;
        return new JsonApiException(400, err);
    }

    public static JsonApiException notFound(String detail) {
        return new JsonApiException(404,
            new JsonApiError(404, 'NOT_FOUND', 'Resource Not Found', detail));
    }

    public static JsonApiException forbidden(String detail) {
        return new JsonApiException(403,
            new JsonApiError(403, 'FORBIDDEN', 'Forbidden', detail));
    }

    public static JsonApiException conflict(String detail) {
        return new JsonApiException(409,
            new JsonApiError(409, 'CONFLICT', 'Conflict', detail));
    }

    public static JsonApiException unsupportedMediaType(String detail) {
        return new JsonApiException(415,
            new JsonApiError(415, 'UNSUPPORTED_MEDIA_TYPE', 'Unsupported Media Type', detail));
    }

    public static JsonApiException notAcceptable(String detail) {
        return new JsonApiException(406,
            new JsonApiError(406, 'NOT_ACCEPTABLE', 'Not Acceptable', detail));
    }

    public static JsonApiException methodNotAllowed(String detail) {
        return new JsonApiException(405,
            new JsonApiError(405, 'METHOD_NOT_ALLOWED', 'Method Not Allowed', detail));
    }

    public static JsonApiException internal(String detail) {
        return new JsonApiException(500,
            new JsonApiError(500, 'INTERNAL_ERROR', 'Internal Server Error', detail));
    }
}
