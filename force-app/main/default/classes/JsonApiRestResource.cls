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

        try {
            negotiate(req);
            JsonApiResponse result = new JsonApiService().handle(
                'GET', segmentsOf(req.requestURI), req.params);
            writeResponse(res, result);
        } catch (JsonApiException e) {
            writeError(res, e.httpStatus, e.errors);
        } catch (Exception e) {
            writeError(res, 500, internalError(e));
        }
    }

    // ---------------------------------------------------------------------

    /**
     * Builds a 500 error that does NOT leak internals to the client. The full
     * message + stack are logged server-side under a short reference the client
     * can quote to support; the response carries only that reference.
     */
    @TestVisible
    private static List<JsonApiError> internalError(Exception e) {
        String ref = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
        System.debug(LoggingLevel.ERROR,
            'JSON:API 500 [' + ref + ']: ' + e.getMessage() + '\n' + e.getStackTraceString());
        return new List<JsonApiError>{
            new JsonApiError(500, 'INTERNAL_ERROR', 'Internal Server Error',
                'An unexpected error occurred. Reference: ' + ref)
        };
    }

    /**
     * Enforces JSON:API content negotiation: if the Accept header names the
     * JSON:API media type, at least one instance must be unparameterized.
     */
    private static void negotiate(RestRequest req) {
        String accept = header(req, 'Accept');
        if (String.isNotBlank(accept) && accept.contains(JsonApiConstants.MEDIA_TYPE)) {
            Boolean hasUnparameterized = false;
            for (String range : accept.split(',')) {
                if (range.trim().equalsIgnoreCase(JsonApiConstants.MEDIA_TYPE)) {
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
