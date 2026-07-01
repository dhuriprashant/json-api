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
        System.assertEquals(1, opts.filters.size());
        JsonApiQueryOptions.FilterCondition fc = opts.filters[0];
        System.assertEquals('industry', fc.attribute);
        System.assertEquals('eq', fc.operator, 'bare filter defaults to eq');
        System.assertEquals('Technology', fc.rawValue);
    }

    @IsTest
    static void parsesFilterOperators() {
        Map<String, String> params = new Map<String, String>{
            'filter[annualRevenue][gte]' => '1000000',
            'filter[annualRevenue][lt]' => '5000000',
            'filter[industry][in]' => 'Technology,Finance',
            'filter[name][like]' => 'Acme%'
        };

        JsonApiQueryOptions opts = JsonApiRequestParser.parse(params, config());

        System.assertEquals(4, opts.filters.size(), 'four conditions, incl. a gte/lt range');
        Map<String, String> opByAttr = new Map<String, String>();
        for (JsonApiQueryOptions.FilterCondition fc : opts.filters) {
            opByAttr.put(fc.attribute + ':' + fc.operator, fc.rawValue);
        }
        System.assertEquals('1000000', opByAttr.get('annualRevenue:gte'));
        System.assertEquals('5000000', opByAttr.get('annualRevenue:lt'));
        System.assertEquals('Technology,Finance', opByAttr.get('industry:in'));
        System.assertEquals('Acme%', opByAttr.get('name:like'));
    }

    @IsTest
    static void parsesBareIdFilterWithCommasAsIn() {
        JsonApiQueryOptions opts = JsonApiRequestParser.parse(
            new Map<String, String>{ 'filter[id]' => '001000000000001,001000000000002' }, config());
        System.assertEquals(1, opts.filters.size());
        JsonApiQueryOptions.FilterCondition fc = opts.filters[0];
        System.assertEquals('id', fc.attribute.toLowerCase());
        System.assertEquals('in', fc.operator, 'bare comma-separated id filter -> in');
    }

    @IsTest
    static void parsesSingleIdFilterAsEq() {
        JsonApiQueryOptions opts = JsonApiRequestParser.parse(
            new Map<String, String>{ 'filter[id]' => '001000000000001' }, config());
        System.assertEquals('eq', opts.filters[0].operator, 'single id stays eq');
    }

    @IsTest
    static void parsesExplicitIdInOperator() {
        JsonApiQueryOptions opts = JsonApiRequestParser.parse(
            new Map<String, String>{ 'filter[id][in]' => '001000000000001,001000000000002' }, config());
        System.assertEquals('in', opts.filters[0].operator);
    }

    @IsTest
    static void rejectsUnsupportedFilterOperator() {
        assertBadRequest(new Map<String, String>{ 'filter[industry][bogusop]' => 'x' });
    }

    @IsTest
    static void rejectsUnknownAttributeWithOperator() {
        assertBadRequest(new Map<String, String>{ 'filter[bogus][gt]' => '1' });
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
    static void parsesExtendGroups() {
        JsonApiQueryOptions opts = JsonApiRequestParser.parse(
            new Map<String, String>{ 'extend' => 'financials,contactInfo' }, config());
        System.assertEquals(2, opts.extendGroups.size());
        System.assert(opts.extendGroups.contains('financials'));
        System.assert(opts.extendGroups.contains('contactInfo'));
    }

    @IsTest
    static void ignoresBaseGroupInExtend() {
        JsonApiQueryOptions opts = JsonApiRequestParser.parse(
            new Map<String, String>{ 'extend' => 'base,financials' }, config());
        System.assertEquals(1, opts.extendGroups.size(), 'base is implicit, not stored');
        System.assert(opts.extendGroups.contains('financials'));
    }

    @IsTest
    static void rejectsUnknownExtendGroup() {
        assertBadRequest(new Map<String, String>{ 'extend' => 'bogus' });
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
    static void rejectsTooDeepIncludePath() {
        // 'parent' is a valid self-referential relationship on accounts.
        assertBadRequest(new Map<String, String>{ 'include' => 'parent.parent.parent.parent' });
    }

    @IsTest
    static void rejectsTooManyIncludePaths() {
        List<String> paths = new List<String>();
        for (Integer i = 0; i <= JsonApiConstants.MAX_INCLUDE_PATHS; i++) {
            paths.add('parent');
        }
        assertBadRequest(new Map<String, String>{ 'include' => String.join(paths, ',') });
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
