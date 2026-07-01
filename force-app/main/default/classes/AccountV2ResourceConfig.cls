/**
 * Exposes the Account SObject as the JSON:API "accounts" resource under **v2**,
 * demonstrating multiple versions of one type. v2 adds `rating` to the base group
 * (v1 does not return it). Reached at /jsonapi/v2/accounts.
 *
 * The version is declared on the CMDT record (`JsonApiResource.AccountsV2` with
 * `Versions__c = "v2"`), not in code — versions are configured in one place.
 *
 * Relationships resolve within the same version: "parent" points at v2/accounts
 * (this config) and "contacts" at v2/contacts (ContactResourceConfig is registered
 * under both v1 and v2 via its CMDT record's Versions__c = "v1,v2").
 */
public with sharing class AccountV2ResourceConfig extends JsonApiResourceConfig {

    public override String getType() {
        return 'accounts';
    }

    public override Schema.SObjectType getSObjectType() {
        return Account.SObjectType;
    }

    public override Map<String, Map<String, String>> getAttributeGroups() {
        return new Map<String, Map<String, String>>{
            // v2 base adds `rating` on top of v1's name/industry.
            'base' => new Map<String, String>{
                'name' => 'Name',
                'industry' => 'Industry',
                'rating' => 'Rating'
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
            // Self-referential parent lookup, resolving to v2/accounts.
            'parent' => JsonApiRelationshipDef.toOne('parent', 'accounts', 'ParentId'),
            // Child contacts, resolving to v2/contacts (shared config, Versions__c=v1,v2).
            'contacts' => JsonApiRelationshipDef.toMany('contacts', 'contacts', 'AccountId')
        };
    }
}
