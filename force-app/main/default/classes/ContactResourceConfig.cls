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

    /**
     * "base" is always returned; "contactInfo" and "professional" are returned
     * only when requested via `?extend=contactInfo,professional`.
     */
    public override Map<String, Map<String, String>> getAttributeGroups() {
        return new Map<String, Map<String, String>>{
            'base' => new Map<String, String>{
                'firstName' => 'FirstName',
                'lastName' => 'LastName'
            },
            'contactInfo' => new Map<String, String>{
                'email' => 'Email',
                'phone' => 'Phone'
            },
            'professional' => new Map<String, String>{
                'title' => 'Title'
            }
        };
    }

    public override Map<String, JsonApiRelationshipDef> getRelationships() {
        return new Map<String, JsonApiRelationshipDef>{
            'account' => JsonApiRelationshipDef.toOne('account', 'accounts', 'AccountId')
        };
    }
}
