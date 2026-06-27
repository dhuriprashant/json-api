@IsTest
private class JsonApiRequestParserTest {

    private static JsonApiResourceConfig config() {
        return new AccountResourceConfig();
    }

    @IsTest
    static void parsesIncludeSortAndSparseFields() {
        Map<String, String> params = new Map<String, String>{
            'include' => 'parent,contacts',
            'sort' => '-name,industry',
            'fields[accounts]' => 'name,phone'
        };

        JsonApiQueryOptions opts = JsonApiRequestParser.parse(params, config());

        System.assertEquals(2, opts.includePaths.size(), 'two include paths');
        System.assertEquals(2, opts.sorts.size(), 'two sort directives');
        System.assertEquals('name', opts.sorts[0].attribute);
        System.assertEquals(false, opts.sorts[0].ascending, 'leading - means descending');
        System.assertEquals(true, opts.sorts[1].ascending);
        System.assert(opts.hasSparseFieldsFor('accounts'));
        System.assertEquals(2, opts.sparseFieldsFor('accounts').size());
    }

    @IsTest
    static void parsesPaginationAndFilter() {
        Map<String, String> params = new Map<String, String>{
            'page[size]' => '10',
            'page[number]' => '3',
            'filter[industry]' => 'Technology'
        };

        JsonApiQueryOptions opts = JsonApiRequestParser.parse(params, config());

        System.assertEquals(10, opts.pageSize);
        System.assertEquals(3, opts.pageNumber);
        System.assertEquals('Technology', opts.filters.get('industry'));
    }

    @IsTest
    static void clampsPageSizeToMaximum() {
        Map<String, String> params = new Map<String, String>{
            'page[size]' => String.valueOf(JsonApiConstants.MAX_PAGE_SIZE + 500)
        };
        JsonApiQueryOptions opts = JsonApiRequestParser.parse(params, config());
        System.assertEquals(JsonApiConstants.MAX_PAGE_SIZE, opts.pageSize);
    }

    @IsTest
    static void rejectsUnknownSortAttribute() {
        assertBadRequest(new Map<String, String>{ 'sort' => 'bogusField' });
    }

    @IsTest
    static void rejectsUnknownIncludeRelationship() {
        assertBadRequest(new Map<String, String>{ 'include' => 'bogusRel' });
    }

    @IsTest
    static void rejectsUnknownFilterAttribute() {
        assertBadRequest(new Map<String, String>{ 'filter[bogus]' => 'x' });
    }

    @IsTest
    static void rejectsNonNumericPage() {
        assertBadRequest(new Map<String, String>{ 'page[size]' => 'abc' });
    }

    private static void assertBadRequest(Map<String, String> params) {
        try {
            JsonApiRequestParser.parse(params, config());
            System.assert(false, 'Expected JsonApiException');
        } catch (JsonApiException e) {
            System.assertEquals(400, e.httpStatus);
        }
    }
}
