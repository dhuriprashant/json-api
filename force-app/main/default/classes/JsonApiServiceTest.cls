@IsTest
private class JsonApiServiceTest {

    @TestSetup
    static void setup() {
        Account parent = new Account(Name = 'Parent Co', Industry = 'Technology');
        insert parent;

        Account acme = new Account(
            Name = 'Acme', Industry = 'Technology', Phone = '555-0100',
            AnnualRevenue = 1000000, NumberOfEmployees = 50, ParentId = parent.Id);
        Account globex = new Account(Name = 'Globex', Industry = 'Manufacturing');
        insert new List<Account>{ acme, globex };

        insert new Contact(FirstName = 'Jane', LastName = 'Doe',
            Email = 'jane@acme.com', AccountId = acme.Id);
    }

    private static Account acme() {
        return [SELECT Id FROM Account WHERE Name = 'Acme' LIMIT 1];
    }

    // 4th arg (body) is ignored — the API is read-only — but kept so existing
    // GET call sites need no change.
    private static JsonApiResponse handle(String method, List<String> segments, Map<String, String> params, String body) {
        return new JsonApiService().handle(method, segments, params);
    }

    @IsTest
    static void getsCollectionWithMetaAndLinks() {
        Test.startTest();
        JsonApiResponse r = handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>(), null);
        Test.stopTest();

        System.assertEquals(200, r.statusCode);
        List<JsonApiResourceObject> data = (List<JsonApiResourceObject>) r.document.data;
        System.assert(data.size() >= 3, 'expected at least 3 accounts');
        System.assertEquals('accounts', data[0].type);
        System.assertEquals(3, (Integer) r.document.meta.get('total'));
        System.assert(r.document.links.containsKey('first'));
        System.assert(r.document.links.containsKey('last'));
    }

    @IsTest
    static void getsSingleResourceWithToOneInclude() {
        Id id = acme().Id;
        JsonApiResponse r = handle('GET', new List<String>{ 'accounts', id },
            new Map<String, String>{ 'include' => 'parent' }, null);

        System.assertEquals(200, r.statusCode);
        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assertEquals('Acme', obj.attributes.get('name'));
        System.assert(obj.relationships.containsKey('parent'), 'parent relationship present');
        System.assertEquals(1, r.document.included.size(), 'parent included once');
        System.assertEquals('accounts', r.document.included[0].type);
    }

    @IsTest
    static void respectsSparseFieldsets() {
        Id id = acme().Id;
        JsonApiResponse r = handle('GET', new List<String>{ 'accounts', id },
            new Map<String, String>{ 'fields[accounts]' => 'name' }, null);

        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assertEquals(1, obj.attributes.size(), 'only name requested');
        System.assert(obj.attributes.containsKey('name'));
    }

    @IsTest
    static void defaultReturnsOnlyBaseAttributes() {
        Id id = acme().Id;
        JsonApiResponse r = handle('GET', new List<String>{ 'accounts', id },
            new Map<String, String>(), null);

        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assertEquals(2, obj.attributes.size(), 'only the base group by default');
        System.assert(obj.attributes.containsKey('name'));
        System.assert(obj.attributes.containsKey('industry'));
        System.assert(!obj.attributes.containsKey('annualRevenue'), 'financials not returned');
    }

    @IsTest
    static void extendAddsRequestedGroup() {
        Id id = acme().Id;
        JsonApiResponse r = handle('GET', new List<String>{ 'accounts', id },
            new Map<String, String>{ 'extend' => 'financials' }, null);

        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assert(obj.attributes.containsKey('name'), 'base still present');
        System.assert(obj.attributes.containsKey('annualRevenue'), 'financials group added');
        System.assert(!obj.attributes.containsKey('phone'), 'contactInfo not requested');
    }

    @IsTest
    static void extendAddsMultipleGroups() {
        Id id = acme().Id;
        JsonApiResponse r = handle('GET', new List<String>{ 'accounts', id },
            new Map<String, String>{ 'extend' => 'financials,contactInfo' }, null);

        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assertEquals(6, obj.attributes.size(), 'base + financials + contactInfo');
    }

    @IsTest
    static void unknownExtendGroupIsBadRequest() {
        try {
            handle('GET', new List<String>{ 'accounts', acme().Id },
                new Map<String, String>{ 'extend' => 'bogus' }, null);
            System.assert(false, 'expected exception');
        } catch (JsonApiException e) {
            System.assertEquals(400, e.httpStatus);
        }
    }

    @IsTest
    static void filtersAndSorts() {
        JsonApiResponse r = handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>{ 'filter[industry]' => 'Technology', 'sort' => '-name' }, null);

        List<JsonApiResourceObject> data = (List<JsonApiResourceObject>) r.document.data;
        System.assertEquals(2, data.size(), 'two Technology accounts');
        // Descending by name: "Parent Co" before "Acme".
        System.assertEquals('Parent Co', data[0].attributes.get('name'));
    }

    @IsTest
    static void filtersWithComparisonOperators() {
        // Only Acme has a revenue (1,000,000); Parent Co and Globex are null,
        // and null never satisfies a comparison in SOQL.
        System.assertEquals(1, count(handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>{ 'filter[annualRevenue][gt]' => '500000' }, null)));

        // A gte/lt range on the same attribute - two conditions, AND-ed.
        System.assertEquals(1, count(handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>{
                'filter[annualRevenue][gte]' => '1000000',
                'filter[annualRevenue][lt]' => '2000000' }, null)));

        // lte just below Acme's revenue excludes it.
        System.assertEquals(0, count(handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>{ 'filter[annualRevenue][lte]' => '999999' }, null)));
    }

    @IsTest
    static void filtersWithNeLikeInNin() {
        // ne: Technology excluded -> Globex (Manufacturing) only.
        System.assertEquals(1, count(handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>{ 'filter[industry][ne]' => 'Technology' }, null)));

        // like: name begins with "Acme".
        System.assertEquals(1, count(handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>{ 'filter[name][like]' => 'Acme%' }, null)));

        // in: both industries -> all three accounts.
        System.assertEquals(3, count(handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>{ 'filter[industry][in]' => 'Technology,Manufacturing' }, null)));

        // nin: exclude Manufacturing -> the two Technology accounts.
        System.assertEquals(2, count(handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>{ 'filter[industry][nin]' => 'Manufacturing' }, null)));
    }

    private static Integer count(JsonApiResponse r) {
        return ((List<JsonApiResourceObject>) r.document.data).size();
    }

    @IsTest
    static void filtersByCommaSeparatedIds() {
        Map<String, Id> idByName = new Map<String, Id>();
        for (Account a : [SELECT Id, Name FROM Account]) {
            idByName.put(a.Name, a.Id);
        }
        Id acme = idByName.get('Acme');
        Id globex = idByName.get('Globex');

        JsonApiResponse r = handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>{ 'filter[id]' => acme + ',' + globex }, null);

        List<JsonApiResourceObject> data = (List<JsonApiResourceObject>) r.document.data;
        System.assertEquals(2, data.size(), 'only the two requested ids');
        Set<String> got = new Set<String>();
        for (JsonApiResourceObject o : data) {
            got.add(o.id);
        }
        System.assert(got.contains(String.valueOf(acme)) && got.contains(String.valueOf(globex)), got + '');
    }

    @IsTest
    static void filterByWrongTypeIdIsBadRequest() {
        Id contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        try {
            handle('GET', new List<String>{ 'accounts' },
                new Map<String, String>{ 'filter[id]' => contactId }, null);
            System.assert(false, 'expected a 400');
        } catch (JsonApiException e) {
            System.assertEquals(400, e.httpStatus);
        }
    }

    @IsTest
    static void getsRelatedToManyCollection() {
        Id id = acme().Id;
        JsonApiResponse r = handle('GET', new List<String>{ 'accounts', id, 'contacts' },
            new Map<String, String>(), null);

        System.assertEquals(200, r.statusCode);
        List<JsonApiResourceObject> data = (List<JsonApiResourceObject>) r.document.data;
        System.assertEquals(1, data.size());
        System.assertEquals('contacts', data[0].type);
    }

    @IsTest
    static void getsRelationshipLinkage() {
        Id id = acme().Id;
        JsonApiResponse r = handle('GET',
            new List<String>{ 'accounts', id, 'relationships', 'parent' },
            new Map<String, String>(), null);

        System.assertEquals(200, r.statusCode);
        JsonApiResourceIdentifier ident = (JsonApiResourceIdentifier) r.document.data;
        System.assertEquals('accounts', ident.type);
    }

    @IsTest
    static void unknownTypeReturnsNotFound() {
        try {
            handle('GET', new List<String>{ 'widgets' }, new Map<String, String>(), null);
            System.assert(false, 'expected exception');
        } catch (JsonApiException e) {
            System.assertEquals(404, e.httpStatus);
        }
    }

    @IsTest
    static void unknownIdReturnsNotFound() {
        String fakeId = Account.SObjectType.getDescribe().getKeyPrefix() + '000000000000';
        try {
            handle('GET', new List<String>{ 'accounts', fakeId },
                new Map<String, String>(), null);
            System.assert(false, 'expected exception');
        } catch (JsonApiException e) {
            System.assertEquals(404, e.httpStatus);
        }
    }

    @IsTest
    static void nonGetMethodsAreReadOnly() {
        // The API is read-only: every non-GET verb must be rejected with 405.
        Id id = acme().Id;
        for (String verb : new List<String>{ 'POST', 'PATCH', 'DELETE', 'PUT', 'OPTIONS' }) {
            try {
                handle(verb, new List<String>{ 'accounts', id }, new Map<String, String>(), null);
                System.assert(false, verb + ' should be rejected');
            } catch (JsonApiException e) {
                System.assertEquals(405, e.httpStatus, verb + ' -> 405');
            }
        }
    }
}
