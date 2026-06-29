/**
 * Production {@link JsonApiQueryGateway}: executes queries in
 * AccessLevel.USER_MODE, so object- and field-level security is enforced by the
 * platform on the running user's behalf. This is the only class that calls the
 * `Database` query methods directly.
 */
public with sharing class JsonApiUserModeGateway implements JsonApiQueryGateway {

    public List<SObject> query(String soql, Map<String, Object> binds) {
        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    public Integer countQuery(String soql, Map<String, Object> binds) {
        return Database.countQueryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }
}
