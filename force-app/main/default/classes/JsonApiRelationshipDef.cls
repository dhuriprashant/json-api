/**
 * Declares a single relationship on a resource, mapping a JSON:API
 * relationship name to the underlying Salesforce relationship.
 *
 * Two shapes are supported:
 *  - to-one  : backed by a lookup/master-detail field on this SObject
 *              (e.g. Contact.AccountId -> "account").
 *  - to-many : backed by a child relationship, identified by the foreign-key
 *              field on the child SObject (e.g. Account <- Contact.AccountId
 *              -> "contacts").
 */
public class JsonApiRelationshipDef {
    /** Relationship name as exposed in JSON:API (e.g. "account"). */
    public String name;
    /** JSON:API `type` of the related resource (e.g. "contacts"). */
    public String targetType;
    public Boolean isToMany;

    /** to-one: API name of the lookup field on THIS object (e.g. "AccountId"). */
    public String lookupField;

    /** to-many: API name of the foreign-key field on the CHILD object. */
    public String childForeignKeyField;

    private JsonApiRelationshipDef() {}

    public static JsonApiRelationshipDef toOne(String name, String targetType, String lookupField) {
        JsonApiRelationshipDef d = new JsonApiRelationshipDef();
        d.name = name;
        d.targetType = targetType;
        d.lookupField = lookupField;
        d.isToMany = false;
        return d;
    }

    public static JsonApiRelationshipDef toMany(String name, String targetType, String childForeignKeyField) {
        JsonApiRelationshipDef d = new JsonApiRelationshipDef();
        d.name = name;
        d.targetType = targetType;
        d.childForeignKeyField = childForeignKeyField;
        d.isToMany = true;
        return d;
    }
}
