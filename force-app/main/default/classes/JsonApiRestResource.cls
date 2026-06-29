/**
 * The HTTP entry point for the framework. Exposes every registered resource
 * under /services/apexrest/jsonapi/* and delegates all logic to
 * {@link JsonApiService}. This class only deals with HTTP concerns: content
 * negotiation, writing the response and rendering errors.
 *
 * The API is read-only: only GET is exposed. Other HTTP methods are rejected by
 * the platform with 405.
 *
 * @see https://jsonapi.org/format/#content-negotiation
 */
@RestResource(urlMapping='/jsonapi/*')
global with sharing class JsonApiRestResource {

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', JsonApiConstants.MEDIA_TYPE);

        Long start = System.now().getTime();
        Integer queriesBefore = Limits.getQueries();
        List<String> segments = segmentsOf(req.requestURI);

        JsonApiRequestLog log = new JsonApiRequestLog();
        log.method = 'GET';
        log.path = req.requestURI;
        log.resourceType = segments.isEmpty() ? null : segments[0];
        log.requestId = System.Request.getCurrent().getRequestId();

        try {
            negotiate(req);
            JsonApiResponse result = new JsonApiService().handle('GET', segments, req.params);
            writeResponse(res, result);
            log.statusCode = result.statusCode;
            log.rows = rowCount(result);
        } catch (JsonApiException e) {
            writeError(res, e.httpStatus, e.errors);
            log.statusCode = e.httpStatus;
            log.errorCode = (e.errors != null && !e.errors.isEmpty()) ? e.errors[0].code : null;
        } catch (Exception e) {
            List<JsonApiError> errors = internalError(e);
            writeError(res, 500, errors);
            log.statusCode = 500;
            log.errorCode = 'INTERNAL_ERROR';
            log.errorReference = errors[0].id;
        } finally {
            log.durationMs = System.now().getTime() - start;
            log.soqlQueries = Limits.getQueries() - queriesBefore;
            JsonApiObservability.emit(log);
        }
    }

    // ---------------------------------------------------------------------

    /**
     * Builds a 500 error that does NOT leak internals to the client. The full
     * message + stack are logged server-side under a short reference (also set as
     * the error `id`) the client can quote to support.
     */
    @TestVisible
    private static List<JsonApiError> internalError(Exception e) {
        String ref = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
        System.debug(LoggingLevel.ERROR,
            'JSON:API 500 [' + ref + ']: ' + e.getMessage() + '\n' + e.getStackTraceString());
        JsonApiError err = new JsonApiError(500, 'INTERNAL_ERROR', 'Internal Server Error',
            'An unexpected error occurred. Reference: ' + ref);
        err.id = ref;
        return new List<JsonApiError>{ err };
    }

    /** Count of primary `data` records, for telemetry. */
    private static Integer rowCount(JsonApiResponse result) {
        if (result == null || result.document == null || result.document.data == null) {
            return 0;
        }
        Object data = result.document.data;
        if (data instanceof List<JsonApiResourceObject>) {
            return ((List<JsonApiResourceObject>) data).size();
        }
        if (data instanceof List<JsonApiResourceIdentifier>) {
            return ((List<JsonApiResourceIdentifier>) data).size();
        }
        return 1;
    }

    /**
     * Enforces content negotiation: accepts application/json or the JSON:API
     * media type (unparameterized). The response is always application/json
     * with JSON:API document structure.
     */
    private static void negotiate(RestRequest req) {
        String accept = header(req, 'Accept');
        if (String.isBlank(accept)) {
            return;  // no Accept header = accept any type
        }
        // Allow application/json directly
        if (accept.contains('application/json')) {
            return;
        }
        // Allow JSON:API media type (unparameterized only)
        if (accept.contains(JsonApiConstants.MEDIA_TYPE_JSON_API)) {
            Boolean hasUnparameterized = false;
            for (String range : accept.split(',')) {
                if (range.trim().equalsIgnoreCase(JsonApiConstants.MEDIA_TYPE_JSON_API)) {
                    hasUnparameterized = true;
                }
            }
            if (!hasUnparameterized) {
                throw JsonApiException.notAcceptable(
                    'The JSON:API media type must be requested without parameters.');
            }
        }
    }

    private static String header(RestRequest req, String name) {
        if (req.headers == null) {
            return null;
        }
        // Header names are case-insensitive; scan rather than assume casing.
        for (String key : req.headers.keySet()) {
            if (key.equalsIgnoreCase(name)) {
                return req.headers.get(key);
            }
        }
        return null;
    }

    /** Extracts the path segments after the "jsonapi" base, decoded. */
    @TestVisible
    private static List<String> segmentsOf(String uri) {
        List<String> segments = new List<String>();
        if (String.isBlank(uri)) {
            return segments;
        }
        List<String> all = uri.split('/');
        Boolean afterBase = false;
        for (String part : all) {
            if (String.isBlank(part)) {
                continue;
            }
            if (!afterBase) {
                if (part.equalsIgnoreCase('jsonapi')) {
                    afterBase = true;
                }
                continue;
            }
            segments.add(EncodingUtil.urlDecode(part, 'UTF-8'));
        }
        return segments;
    }

    private static void writeResponse(RestResponse res, JsonApiResponse result) {
        res.statusCode = result.statusCode;
        for (String name : result.headers.keySet()) {
            res.addHeader(name, result.headers.get(name));
        }
        if (result.document != null) {
            res.responseBody = Blob.valueOf(result.document.toJson());
        }
    }

    private static void writeError(RestResponse res, Integer status, List<JsonApiError> errors) {
        res.statusCode = status;
        res.responseBody = Blob.valueOf(JsonApiDocument.ofErrors(errors).toJson());
    }
}
