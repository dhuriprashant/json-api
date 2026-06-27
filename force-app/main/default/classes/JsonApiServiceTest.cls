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

    private static JsonApiResponse handle(String method, List<String> segments, Map<String, String> params, String body) {
        return new JsonApiService().handle(method, segments, params, body);
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
    static void filtersAndSorts() {
        JsonApiResponse r = handle('GET', new List<String>{ 'accounts' },
            new Map<String, String>{ 'filter[industry]' => 'Technology', 'sort' => '-name' }, null);

        List<JsonApiResourceObject> data = (List<JsonApiResourceObject>) r.document.data;
        System.assertEquals(2, data.size(), 'two Technology accounts');
        // Descending by name: "Parent Co" before "Acme".
        System.assertEquals('Parent Co', data[0].attributes.get('name'));
    }

    @IsTest
    static void createsResource() {
        String body = JSON.serialize(new Map<String, Object>{
            'data' => new Map<String, Object>{
                'type' => 'accounts',
                'attributes' => new Map<String, Object>{ 'name' => 'New Co', 'industry' => 'Finance' }
            }
        });

        Test.startTest();
        JsonApiResponse r = handle('POST', new List<String>{ 'accounts' }, null, body);
        Test.stopTest();

        System.assertEquals(201, r.statusCode);
        System.assert(r.headers.containsKey('Location'));
        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assertNotEquals(null, obj.id);
        System.assertEquals('New Co', obj.attributes.get('name'));
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'New Co']);
    }

    @IsTest
    static void createsResourceWithRelationship() {
        Id parentId = [SELECT Id FROM Account WHERE Name = 'Parent Co' LIMIT 1].Id;
        String body = JSON.serialize(new Map<String, Object>{
            'data' => new Map<String, Object>{
                'type' => 'accounts',
                'attributes' => new Map<String, Object>{ 'name' => 'Child Co' },
                'relationships' => new Map<String, Object>{
                    'parent' => new Map<String, Object>{
                        'data' => new Map<String, Object>{ 'type' => 'accounts', 'id' => parentId }
                    }
                }
            }
        });

        JsonApiResponse r = handle('POST', new List<String>{ 'accounts' }, null, body);
        System.assertEquals(201, r.statusCode);
        Account child = [SELECT ParentId FROM Account WHERE Name = 'Child Co' LIMIT 1];
        System.assertEquals(parentId, child.ParentId);
    }

    @IsTest
    static void updatesResource() {
        Id id = acme().Id;
        String body = JSON.serialize(new Map<String, Object>{
            'data' => new Map<String, Object>{
                'type' => 'accounts', 'id' => id,
                'attributes' => new Map<String, Object>{ 'phone' => '555-9999' }
            }
        });

        JsonApiResponse r = handle('PATCH', new List<String>{ 'accounts', id }, null, body);
        System.assertEquals(200, r.statusCode);
        System.assertEquals('555-9999', [SELECT Phone FROM Account WHERE Id = :id].Phone);
    }

    @IsTest
    static void deletesResource() {
        Id id = acme().Id;
        JsonApiResponse r = handle('DELETE', new List<String>{ 'accounts', id }, null, null);
        System.assertEquals(204, r.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id = :id]);
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
    static void createWithUnknownAttributeIsBadRequest() {
        String body = JSON.serialize(new Map<String, Object>{
            'data' => new Map<String, Object>{
                'type' => 'accounts',
                'attributes' => new Map<String, Object>{ 'bogus' => 'x' }
            }
        });
        try {
            handle('POST', new List<String>{ 'accounts' }, null, body);
            System.assert(false, 'expected exception');
        } catch (JsonApiException e) {
            System.assertEquals(400, e.httpStatus);
        }
    }

    @IsTest
    static void typeMismatchOnCreateIsConflict() {
        String body = JSON.serialize(new Map<String, Object>{
            'data' => new Map<String, Object>{ 'type' => 'contacts',
                'attributes' => new Map<String, Object>{ 'name' => 'X' } }
        });
        try {
            handle('POST', new List<String>{ 'accounts' }, null, body);
            System.assert(false, 'expected exception');
        } catch (JsonApiException e) {
            System.assertEquals(409, e.httpStatus);
        }
    }

    @IsTest
    static void unsupportedMethodIsNotAllowed() {
        try {
            handle('OPTIONS', new List<String>{ 'accounts' }, new Map<String, String>(), null);
            System.assert(false, 'expected exception');
        } catch (JsonApiException e) {
            System.assertEquals(405, e.httpStatus);
        }
    }
}
