/**
 * DML-free unit tests for the read/serialize/include pipeline. By injecting an
 * in-memory {@link JsonApiTestQueryGateway}, these exercise the framework with
 * fabricated SObjects — no inserts, so they run fast and are immune to org
 * triggers/validation rules. The DML-backed integration tests
 * ({@link JsonApiServiceTest} etc.) still cover the real SOQL + USER_MODE paths.
 */
@IsTest
private class JsonApiUnitTest {

    private static Id fakeId(Schema.SObjectType type, Integer n) {
        return Id.valueOf(type.getDescribe().getKeyPrefix() +
            String.valueOf(n).leftPad(12).replace(' ', '0'));
    }

    private class RecordingObserver implements JsonApiObserver {
        public JsonApiRequestLog last;
        public void observe(JsonApiRequestLog log) {
            last = log;
        }
    }

    private class ThrowingObserver implements JsonApiObserver {
        public void observe(JsonApiRequestLog log) {
            throw new ObserverException('boom');
        }
    }

    private class ObserverException extends Exception {}

    @IsTest
    static void observabilityEmitsToObserverAndSwallowsFailures() {
        RecordingObserver rec = new RecordingObserver();
        JsonApiObservability.setObserver(rec);

        JsonApiRequestLog log = new JsonApiRequestLog();
        log.method = 'GET';
        log.statusCode = 200;
        log.resourceType = 'accounts';
        JsonApiObservability.emit(log);

        System.assertEquals(200, rec.last.statusCode);
        System.assertEquals('accounts', rec.last.resourceType);

        // A misbehaving observer must never propagate out of emit().
        JsonApiObservability.setObserver(new ThrowingObserver());
        JsonApiObservability.emit(log);
    }

    @IsTest
    static void debugObserverHandlesSuccessAndError() {
        JsonApiRequestLog ok = new JsonApiRequestLog();
        ok.statusCode = 200;
        JsonApiRequestLog bad = new JsonApiRequestLog();
        bad.statusCode = 500;

        new JsonApiDebugObserver().observe(ok);   // INFO branch
        new JsonApiDebugObserver().observe(bad);  // ERROR branch
        System.assertEquals(false, ok.isError());
        System.assertEquals(true, bad.isError());
    }

    @IsTest
    static void healthEndpointReportsOkWhenAllResourcesLoad() {
        JsonApiRegistry.reset(); // load from the real (valid) CMDT records

        JsonApiResponse r = new JsonApiService(new JsonApiTestQueryGateway()).handle(
            'GET', new List<String>{ JsonApiConstants.HEALTH_PATH }, new Map<String, String>());

        System.assertEquals(200, r.statusCode);
        System.assertEquals('ok', r.document.meta.get('status'));
        System.assertEquals(0, ((Map<String, String>) r.document.meta.get('registrationErrors')).size());
        System.assert(((List<String>) r.document.meta.get('resources')).contains('accounts'));
        // Meta-only document: no primary data member, not even an explicit null.
        System.assert(!r.document.toJson().contains('"data"'), r.document.toJson());
    }

    @IsTest
    static void healthEndpointReportsDegradedWithRegistrationErrors() {
        JsonApiBootstrap.configOverride = new List<JsonApiResource__mdt>{
            new JsonApiResource__mdt(DeveloperName = 'Accounts', Apex_Class__c = 'AccountResourceConfig', Is_Active__c = true),
            new JsonApiResource__mdt(DeveloperName = 'Bad', Apex_Class__c = 'NoSuchClass__X', Is_Active__c = true)
        };
        JsonApiRegistry.reset();

        JsonApiResponse r = new JsonApiService(new JsonApiTestQueryGateway()).handle(
            'GET', new List<String>{ JsonApiConstants.HEALTH_PATH }, new Map<String, String>());

        System.assertEquals(503, r.statusCode);
        System.assertEquals('degraded', r.document.meta.get('status'));
        Map<String, String> errors = (Map<String, String>) r.document.meta.get('registrationErrors');
        System.assert(errors.containsKey('Bad'), 'bad record surfaced in health: ' + errors);
        // The healthy resource is still listed.
        System.assert(((List<String>) r.document.meta.get('resources')).contains('accounts'));
    }

    // ---- Query builder: typed coercion of filter values ----

    @IsTest
    static void builderCoercesNumericScalarAndListFilters() {
        JsonApiQueryOptions opts = new JsonApiQueryOptions();
        opts.filters.add(new JsonApiQueryOptions.FilterCondition('annualRevenue', 'gt', '1000000'));
        opts.filters.add(new JsonApiQueryOptions.FilterCondition('annualRevenue', 'in', '1.5,2.5'));
        opts.filters.add(new JsonApiQueryOptions.FilterCondition('numberOfEmployees', 'in', '10,20'));

        JsonApiQueryBuilder b = new JsonApiQueryBuilder(new AccountResourceConfig(), opts);
        String soql = b.buildCollectionQuery();

        System.assert(soql.contains('AnnualRevenue > :'), soql);
        System.assert(soql.contains('AnnualRevenue IN :'), soql);
        System.assert(soql.contains('NumberOfEmployees IN :'), soql);
        // Scalar currency coerces to Double; the IN lists are typed (not List<Object>).
        System.assert(b.binds.get('f0') instanceof Double, 'scalar currency -> Double');
        System.assert(b.binds.get('f1') instanceof List<Double>, 'currency list -> List<Double>');
        System.assert(b.binds.get('f2') instanceof List<Integer>, 'employee list -> List<Integer>');
    }

    @IsTest
    static void builderRejectsBadNumericScalarFilter() {
        JsonApiQueryOptions opts = new JsonApiQueryOptions();
        opts.filters.add(new JsonApiQueryOptions.FilterCondition('annualRevenue', 'gt', 'not-a-number'));
        assertBuilderBadRequest(opts);
    }

    @IsTest
    static void builderRejectsBadNumericListFilter() {
        JsonApiQueryOptions opts = new JsonApiQueryOptions();
        opts.filters.add(new JsonApiQueryOptions.FilterCondition('numberOfEmployees', 'in', 'x,y'));
        assertBuilderBadRequest(opts);
    }

    private static void assertBuilderBadRequest(JsonApiQueryOptions opts) {
        try {
            new JsonApiQueryBuilder(new AccountResourceConfig(), opts).buildCollectionQuery();
            System.assert(false, 'expected a 400');
        } catch (JsonApiException e) {
            System.assertEquals(400, e.httpStatus);
        }
    }

    // ---- Service routing (DML-free, via the in-memory gateway) ----

    private static JsonApiTestQueryGateway routingGateway() {
        Id accId = fakeId(Account.SObjectType, 1);
        Account acc = new Account(Name = 'Acme');
        acc.Id = accId;
        Contact con = new Contact(LastName = 'Doe', AccountId = accId);
        con.Id = fakeId(Contact.SObjectType, 1);
        return new JsonApiTestQueryGateway()
            .seed(Account.SObjectType, new List<SObject>{ acc })
            .seed(Contact.SObjectType, new List<SObject>{ con });
    }

    @IsTest
    static void emptySegmentsIsBadRequest() {
        try {
            new JsonApiService(new JsonApiTestQueryGateway())
                .handle('GET', new List<String>(), new Map<String, String>());
            System.assert(false, 'expected a 400');
        } catch (JsonApiException e) {
            System.assertEquals(400, e.httpStatus);
        }
    }

    @IsTest
    static void invalidIdFormatIsBadRequest() {
        try {
            new JsonApiService(routingGateway()).handle(
                'GET', new List<String>{ 'accounts', 'not-an-id' }, new Map<String, String>());
            System.assert(false, 'expected a 400');
        } catch (JsonApiException e) {
            System.assertEquals(400, e.httpStatus);
        }
    }

    @IsTest
    static void relatedToOneReturnsResource() {
        Id conId = fakeId(Contact.SObjectType, 1);
        JsonApiResponse r = new JsonApiService(routingGateway()).handle(
            'GET', new List<String>{ 'contacts', conId, 'account' }, new Map<String, String>());

        System.assertEquals(200, r.statusCode);
        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assertEquals('accounts', obj.type);
    }

    @IsTest
    static void relatedToManyReturnsCollection() {
        Id accId = fakeId(Account.SObjectType, 1);
        JsonApiResponse r = new JsonApiService(routingGateway()).handle(
            'GET', new List<String>{ 'accounts', accId, 'contacts' }, new Map<String, String>());

        System.assertEquals(200, r.statusCode);
        List<JsonApiResourceObject> data = (List<JsonApiResourceObject>) r.document.data;
        System.assertEquals(1, data.size());
        System.assertEquals('contacts', data[0].type);
    }

    @IsTest
    static void toManyLinkageReturnsIdentifiers() {
        Id accId = fakeId(Account.SObjectType, 1);
        JsonApiResponse r = new JsonApiService(routingGateway()).handle(
            'GET', new List<String>{ 'accounts', accId, 'relationships', 'contacts' },
            new Map<String, String>());

        System.assertEquals(200, r.statusCode);
        List<JsonApiResourceIdentifier> ids = (List<JsonApiResourceIdentifier>) r.document.data;
        System.assertEquals(1, ids.size());
        System.assertEquals('contacts', ids[0].type);
    }

    @IsTest
    static void unknownRelatedRelationshipIsNotFound() {
        assertRoutingNotFound(new List<String>{ 'accounts', fakeId(Account.SObjectType, 1), 'bogus' });
    }

    @IsTest
    static void unknownLinkageRelationshipIsNotFound() {
        assertRoutingNotFound(new List<String>{
            'accounts', fakeId(Account.SObjectType, 1), 'relationships', 'bogus' });
    }

    @IsTest
    static void unrecognizedPathShapeIsNotFound() {
        assertRoutingNotFound(new List<String>{
            'accounts', fakeId(Account.SObjectType, 1), 'foo', 'bar' });
    }

    private static void assertRoutingNotFound(List<String> segments) {
        try {
            new JsonApiService(routingGateway()).handle('GET', segments, new Map<String, String>());
            System.assert(false, 'expected a 404');
        } catch (JsonApiException e) {
            System.assertEquals(404, e.httpStatus);
        }
    }

    @IsTest
    static void errorSourceFactoriesSetTheRightMember() {
        JsonApiErrorSource byPointer = JsonApiErrorSource.forPointer('/data/id');
        System.assertEquals('/data/id', byPointer.pointer);
        System.assertEquals(null, byPointer.parameter);

        JsonApiErrorSource byParam = JsonApiErrorSource.forParameter('include');
        System.assertEquals('include', byParam.parameter);
        System.assertEquals(null, byParam.pointer);
    }

    @IsTest
    static void serializesSingleResourceWithoutDml() {
        Id accId = fakeId(Account.SObjectType, 1);
        Account acc = new Account(Name = 'Acme', Industry = 'Technology');
        acc.Id = accId;

        JsonApiTestQueryGateway mock =
            new JsonApiTestQueryGateway().seed(Account.SObjectType, new List<SObject>{ acc });

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'accounts', accId }, new Map<String, String>());

        System.assertEquals(200, r.statusCode);
        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assertEquals('accounts', obj.type);
        System.assertEquals(accId, (Id) obj.id);
        System.assertEquals('Acme', obj.attributes.get('name'));
        System.assertEquals(0, Limits.getDmlStatements(), 'no DML expected');
        System.assertEquals(1, mock.queryCountFor(Account.SObjectType));
    }

    @IsTest
    static void serializesCollectionWithMetaAndLinks() {
        Account a1 = new Account(Name = 'Acme');
        a1.Id = fakeId(Account.SObjectType, 1);
        Account a2 = new Account(Name = 'Globex');
        a2.Id = fakeId(Account.SObjectType, 2);

        JsonApiTestQueryGateway mock =
            new JsonApiTestQueryGateway().seed(Account.SObjectType, new List<SObject>{ a1, a2 });
        mock.countValue = 2;

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'accounts' }, new Map<String, String>());

        List<JsonApiResourceObject> data = (List<JsonApiResourceObject>) r.document.data;
        System.assertEquals(2, data.size());
        System.assertEquals(2, (Integer) r.document.meta.get('total'));
        System.assert(r.document.links.containsKey('first'));
        System.assertEquals(0, Limits.getDmlStatements());
    }

    @IsTest
    static void sideLoadsToManyIncludeWithoutDml() {
        Id accId = fakeId(Account.SObjectType, 1);
        Id conId = fakeId(Contact.SObjectType, 1);
        Account acc = new Account(Name = 'Acme');
        acc.Id = accId;
        Contact con = new Contact(LastName = 'Doe', AccountId = accId);
        con.Id = conId;

        JsonApiTestQueryGateway mock = new JsonApiTestQueryGateway()
            .seed(Account.SObjectType, new List<SObject>{ acc })
            .seed(Contact.SObjectType, new List<SObject>{ con });

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'accounts', accId },
            new Map<String, String>{ 'include' => 'contacts' });

        System.assertEquals(200, r.statusCode);
        System.assertEquals(1, r.document.included.size());
        System.assertEquals('contacts', r.document.included[0].type);
        System.assertEquals(conId, (Id) r.document.included[0].id);
        System.assertEquals(1, mock.queryCountFor(Contact.SObjectType), 'contacts fetched once');
        System.assertEquals(0, Limits.getDmlStatements());
    }

    @IsTest
    static void sideLoadsToOneIncludeWithoutDml() {
        Id accId = fakeId(Account.SObjectType, 1);
        Id conId = fakeId(Contact.SObjectType, 1);
        Account acc = new Account(Name = 'Parent Co');
        acc.Id = accId;
        Contact con = new Contact(LastName = 'Doe', AccountId = accId);
        con.Id = conId;

        JsonApiTestQueryGateway mock = new JsonApiTestQueryGateway()
            .seed(Contact.SObjectType, new List<SObject>{ con })
            .seed(Account.SObjectType, new List<SObject>{ acc });

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'contacts', conId },
            new Map<String, String>{ 'include' => 'account' });

        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assert(obj.relationships.containsKey('account'));
        System.assertEquals(1, r.document.included.size());
        System.assertEquals('accounts', r.document.included[0].type);
        System.assertEquals(0, Limits.getDmlStatements());
    }

    @IsTest
    static void emptyToOneRelationshipSerializesExplicitNullData() {
        Id accId = fakeId(Account.SObjectType, 1);
        Account acc = new Account(Name = 'Acme'); // ParentId is null
        acc.Id = accId;

        JsonApiTestQueryGateway mock =
            new JsonApiTestQueryGateway().seed(Account.SObjectType, new List<SObject>{ acc });

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'accounts', accId }, new Map<String, String>());

        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        Map<String, Object> parentRel = (Map<String, Object>) obj.relationships.get('parent');
        System.assert(parentRel.containsKey('data'), 'empty to-one must include data');
        System.assertEquals(null, parentRel.get('data'), 'empty to-one data must be null');

        // to-many linkage is NOT inlined → no data key.
        Map<String, Object> contactsRel = (Map<String, Object>) obj.relationships.get('contacts');
        System.assert(!contactsRel.containsKey('data'), 'to-many data is not inlined');

        // And it survives serialization as an explicit null, not a dropped member.
        System.assert(r.document.toJson().contains('"data":null'), r.document.toJson());
    }

    @IsTest
    static void presentToOneRelationshipSerializesIdentifier() {
        Id accId = fakeId(Account.SObjectType, 1);
        Id parentId = fakeId(Account.SObjectType, 2);
        Account acc = new Account(Name = 'Acme', ParentId = parentId);
        acc.Id = accId;

        JsonApiTestQueryGateway mock =
            new JsonApiTestQueryGateway().seed(Account.SObjectType, new List<SObject>{ acc });

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'accounts', accId }, new Map<String, String>());

        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        Map<String, Object> parentRel = (Map<String, Object>) obj.relationships.get('parent');
        JsonApiResourceIdentifier ident = (JsonApiResourceIdentifier) parentRel.get('data');
        System.assertEquals('accounts', ident.type);
        System.assertEquals(parentId, (Id) ident.id);
    }

    @IsTest
    static void emptyRelationshipLinkageEndpointEmitsNullData() {
        Id accId = fakeId(Account.SObjectType, 1);
        Account acc = new Account(Name = 'Acme'); // no parent
        acc.Id = accId;

        JsonApiTestQueryGateway mock =
            new JsonApiTestQueryGateway().seed(Account.SObjectType, new List<SObject>{ acc });

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'accounts', accId, 'relationships', 'parent' },
            new Map<String, String>());

        System.assertEquals(200, r.statusCode);
        System.assertEquals(null, r.document.data, 'empty linkage data is null');
        System.assert(r.document.toJson().contains('"data":null'),
            'top-level data must serialize as null, got ' + r.document.toJson());
    }
}
