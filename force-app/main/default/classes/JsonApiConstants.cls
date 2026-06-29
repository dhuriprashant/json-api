/**
 * Shared constants for the JSON:API framework.
 * @see https://jsonapi.org/format/
 */
public with sharing class JsonApiConstants {
    /** Response media type. We use application/json (simpler) but maintain JSON:API document structure. */
    public static final String MEDIA_TYPE = 'application/json';

    /** Legacy JSON:API media type — accepted in Accept header for compatibility. */
    public static final String MEDIA_TYPE_JSON_API = 'application/vnd.api+json';

    /** The version of the JSON:API spec this framework targets. */
    public static final String VERSION = '1.1';

    /** Absolute base path of the API, used to build `links`. Matches the
     *  @RestResource urlMapping ('/jsonapi/*') under /services/apexrest. */
    public static final String BASE_PATH = '/services/apexrest/jsonapi';

    // ---- Reserved query parameter names ----
    public static final String PARAM_INCLUDE = 'include';
    public static final String PARAM_SORT = 'sort';
    public static final String PARAM_FIELDS = 'fields';
    public static final String PARAM_PAGE = 'page';
    public static final String PARAM_FILTER = 'filter';
    /** Comma-separated list of extra attribute groups to include in the payload. */
    public static final String PARAM_EXTEND = 'extend';

    /** Reserved path segment for the diagnostics/health endpoint (not a resource type). */
    public static final String HEALTH_PATH = '_health';

    // ---- Pagination sub-keys ----
    public static final String PAGE_LIMIT = 'limit';
    public static final String PAGE_OFFSET = 'offset';
    public static final String PAGE_NUMBER = 'number';
    public static final String PAGE_SIZE = 'size';

    /** Default and maximum page sizes guard against unbounded queries. */
    public static final Integer DEFAULT_PAGE_SIZE = 25;
    public static final Integer MAX_PAGE_SIZE = 200;

    /** SOQL OFFSET is hard-capped by the platform at 2000. */
    public static final Integer MAX_OFFSET = 2000;

    /** Guards against runaway compound documents (SOQL/CPU). */
    public static final Integer MAX_INCLUDE_PATHS = 10;
    public static final Integer MAX_INCLUDE_DEPTH = 3;
}
