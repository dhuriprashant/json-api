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

    /**
     * "base" is always returned; "contactInfo" and "financials" are returned
     * only when requested via `?extend=contactInfo,financials`.
     */
    public override Map<String, Map<String, String>> getAttributeGroups() {
        return new Map<String, Map<String, String>>{
            'base' => new Map<String, String>{
                'name' => 'Name',
                'industry' => 'Industry'
            },
            'contactInfo' => new Map<String, String>{
                'phone' => 'Phone',
                'website' => 'Website'
            },
            'financials' => new Map<String, String>{
                'annualRevenue' => 'AnnualRevenue',
                'numberOfEmployees' => 'NumberOfEmployees'
            }
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
