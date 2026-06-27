/**
 * The HTTP entry point for the framework. Exposes every registered resource
 * under /services/apexrest/jsonapi/* and delegates all logic to
 * {@link JsonApiService}. This class only deals with HTTP concerns: routing the
 * verb, content negotiation, writing the response and rendering errors.
 *
 * @see https://jsonapi.org/format/#content-negotiation
 */
@RestResource(urlMapping='/jsonapi/*')
global with sharing class JsonApiRestResource {

    @HttpGet
    global static void doGet() {
        dispatch('GET', false);
    }

    @HttpPost
    global static void doPost() {
        dispatch('POST', true);
    }

    @HttpPatch
    global static void doPatch() {
        dispatch('PATCH', true);
    }

    @HttpDelete
    global static void doDelete() {
        dispatch('DELETE', false);
    }

    // ---------------------------------------------------------------------

    private static void dispatch(String method, Boolean expectsBody) {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', JsonApiConstants.MEDIA_TYPE);

        try {
            negotiate(req, expectsBody);

            String body = req.requestBody == null ? null : req.requestBody.toString();
            JsonApiResponse result = new JsonApiService().handle(
                method, segmentsOf(req.requestURI), req.params, body);

            writeResponse(res, result);
        } catch (JsonApiException e) {
            writeError(res, e.httpStatus, e.errors);
        } catch (Exception e) {
            writeError(res, 500, new List<JsonApiError>{
                new JsonApiError(500, 'INTERNAL_ERROR', 'Internal Server Error', e.getMessage())
            });
        }
    }

    /**
     * Enforces JSON:API content negotiation: a request body must be sent as the
     * JSON:API media type with no parameters, and the Accept header (if it names
     * the media type) must not parameterize every instance.
     */
    private static void negotiate(RestRequest req, Boolean expectsBody) {
        if (expectsBody) {
            String contentType = header(req, 'Content-Type');
            if (String.isNotBlank(contentType) &&
                !contentType.trim().equalsIgnoreCase(JsonApiConstants.MEDIA_TYPE)) {
                throw JsonApiException.unsupportedMediaType(
                    'Content-Type must be "' + JsonApiConstants.MEDIA_TYPE + '".');
            }
        }
        String accept = header(req, 'Accept');
        if (String.isNotBlank(accept) && accept.contains(JsonApiConstants.MEDIA_TYPE)) {
            // Reject only when every JSON:API media-type instance carries params.
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
