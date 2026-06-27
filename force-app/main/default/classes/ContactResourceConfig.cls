/**
 * Exposes the Contact SObject as the JSON:API "contacts" resource, with a
 * to-one relationship back to its Account.
 */
public with sharing class ContactResourceConfig extends JsonApiResourceConfig {

    public override String getType() {
        return 'contacts';
    }

    public override Schema.SObjectType getSObjectType() {
        return Contact.SObjectType;
    }

    public override Map<String, String> getAttributeMap() {
        return new Map<String, String>{
            'firstName' => 'FirstName',
            'lastName' => 'LastName',
            'email' => 'Email',
            'phone' => 'Phone',
            'title' => 'Title'
        };
    }

    public override Map<String, JsonApiRelationshipDef> getRelationships() {
        return new Map<String, JsonApiRelationshipDef>{
            'account' => JsonApiRelationshipDef.toOne('account', 'accounts', 'AccountId')
        };
    }
}
