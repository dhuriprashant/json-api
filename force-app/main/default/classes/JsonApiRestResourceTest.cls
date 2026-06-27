@IsTest
private class JsonApiRestResourceTest {

    @TestSetup
    static void setup() {
        insert new Account(Name = 'Acme', Industry = 'Technology');
    }

    private static RestRequest newRequest(String method, String uri) {
        RestRequest req = new RestRequest();
        req.httpMethod = method;
        req.requestURI = uri;
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return req;
    }

    @IsTest
    static void getCollectionReturnsJsonApiDocument() {
        newRequest('GET', '/services/apexrest/jsonapi/accounts');

        Test.startTest();
        JsonApiRestResource.doGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(JsonApiConstants.MEDIA_TYPE,
            RestContext.response.headers.get('Content-Type'));
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('"type":"accounts"'), 'body: ' + body);
    }

    @IsTest
    static void unknownTypeRendersErrorDocument() {
        newRequest('GET', '/services/apexrest/jsonapi/widgets');

        JsonApiRestResource.doGet();

        System.assertEquals(404, RestContext.response.statusCode);
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('"errors"'), 'body: ' + body);
        System.assert(body.contains('NOT_FOUND'));
    }

    @IsTest
    static void wrongContentTypeIsUnsupportedMediaType() {
        RestRequest req = newRequest('POST', '/services/apexrest/jsonapi/accounts');
        req.addHeader('Content-Type', 'text/plain');
        req.requestBody = Blob.valueOf('{"data":{}}');

        JsonApiRestResource.doPost();

        System.assertEquals(415, RestContext.response.statusCode);
    }

    @IsTest
    static void parameterizedAcceptIsNotAcceptable() {
        RestRequest req = newRequest('GET', '/services/apexrest/jsonapi/accounts');
        req.addHeader('Accept', JsonApiConstants.MEDIA_TYPE + ';charset=utf-8');

        JsonApiRestResource.doGet();

        System.assertEquals(406, RestContext.response.statusCode);
    }

    @IsTest
    static void postCreatesViaHttpLayer() {
        RestRequest req = newRequest('POST', '/services/apexrest/jsonapi/accounts');
        req.addHeader('Content-Type', JsonApiConstants.MEDIA_TYPE);
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'data' => new Map<String, Object>{
                'type' => 'accounts',
                'attributes' => new Map<String, Object>{ 'name' => 'Via HTTP' }
            }
        }));

        Test.startTest();
        JsonApiRestResource.doPost();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode);
        System.assert(RestContext.response.headers.containsKey('Location'));
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'Via HTTP']);
    }

    @IsTest
    static void segmentsAreExtractedAfterBase() {
        List<String> segments = JsonApiRestResource.segmentsOf(
            '/services/apexrest/jsonapi/accounts/001000000000001/contacts');
        System.assertEquals(
            new List<String>{ 'accounts', '001000000000001', 'contacts' }, segments);
    }

    @IsTest
    static void blankUriYieldsNoSegments() {
        System.assertEquals(0, JsonApiRestResource.segmentsOf('').size());
        System.assertEquals(0, JsonApiRestResource.segmentsOf(null).size());
    }
}
