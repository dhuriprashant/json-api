/**
 * Exposes the Account SObject as the JSON:API "accounts" resource.
 * Serves as the reference example for writing your own configs.
 */
public with sharing class AccountResourceConfig extends JsonApiResourceConfig {

    public override String getType() {
        return 'accounts';
    }

    public override Schema.SObjectType getSObjectType() {
        return Account.SObjectType;
    }

    public override Map<String, String> getAttributeMap() {
        return new Map<String, String>{
            'name' => 'Name',
            'industry' => 'Industry',
            'phone' => 'Phone',
            'website' => 'Website',
            'annualRevenue' => 'AnnualRevenue',
            'numberOfEmployees' => 'NumberOfEmployees'
        };
    }

    public override Map<String, JsonApiRelationshipDef> getRelationships() {
        return new Map<String, JsonApiRelationshipDef>{
            // Self-referential parent lookup (Account.ParentId -> accounts).
            'parent' => JsonApiRelationshipDef.toOne('parent', 'accounts', 'ParentId'),
            // Child contacts (Contact.AccountId -> contacts).
            'contacts' => JsonApiRelationshipDef.toMany('contacts', 'contacts', 'AccountId')
        };
    }
}
