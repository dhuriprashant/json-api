/**
 * Converts an incoming JSON:API resource object (as an untyped Map) into an
 * SObject ready for DML. Validates `type`, enforces the writable-attribute
 * allow-list, coerces values to their field types and maps to-one relationships
 * onto lookup fields.
 * @see https://jsonapi.org/format/#crud
 */
public with sharing class JsonApiDeserializer {

    /**
     * @param data       the `data` member of the request document (a Map)
     * @param config     config for the resource collection being written to
     * @param requireId  true for PATCH (id is mandatory), false for POST
     */
    public SObject toSObject(Object data, JsonApiResourceConfig config, Boolean requireId) {
        if (!(data instanceof Map<String, Object>)) {
            throw JsonApiException.badRequest(
                'The request document must contain a single resource object in "data".',
                JsonApiErrorSource.forPointer('/data'));
        }
        Map<String, Object> resource = (Map<String, Object>) data;

        // ---- type ----
        String type = (String) resource.get('type');
        if (String.isBlank(type)) {
            throw JsonApiException.badRequest(
                'Resource object is missing required member "type".',
                JsonApiErrorSource.forPointer('/data/type'));
        }
        if (type.toLowerCase() != config.getType().toLowerCase()) {
            throw JsonApiException.conflict(
                'Resource type "' + type + '" does not match endpoint type "' + config.getType() + '".');
        }

        // ---- id ----
        String id = (String) resource.get('id');
        if (requireId && String.isBlank(id)) {
            throw JsonApiException.badRequest(
                'Resource object is missing required member "id".',
                JsonApiErrorSource.forPointer('/data/id'));
        }

        SObject record = config.getSObjectType().newSObject();
        if (String.isNotBlank(id)) {
            record.put('Id', id);
        }

        Map<String, Schema.SObjectField> fieldMap =
            config.getSObjectType().getDescribe().fields.getMap();

        applyAttributes(record, resource, config, fieldMap);
        applyRelationships(record, resource, config);
        return record;
    }

    private void applyAttributes(
        SObject record,
        Map<String, Object> resource,
        JsonApiResourceConfig config,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        if (!(resource.get('attributes') instanceof Map<String, Object>)) {
            return;
        }
        Map<String, Object> attributes = (Map<String, Object>) resource.get('attributes');
        Set<String> writable = config.getWritableAttributes();

        for (String attr : attributes.keySet()) {
            if (!config.hasAttribute(attr)) {
                throw JsonApiException.badRequest(
                    'Unknown attribute "' + attr + '".',
                    JsonApiErrorSource.forPointer('/data/attributes/' + attr));
            }
            if (!writable.contains(attr)) {
                throw JsonApiException.forbidden(
                    'Attribute "' + attr + '" is read-only.');
            }
            String fieldName = config.fieldFor(attr);
            record.put(fieldName, coerce(fieldMap.get(fieldName.toLowerCase()), attributes.get(attr), attr));
        }
    }

    private void applyRelationships(
        SObject record,
        Map<String, Object> resource,
        JsonApiResourceConfig config
    ) {
        if (!(resource.get('relationships') instanceof Map<String, Object>)) {
            return;
        }
        Map<String, Object> relationships = (Map<String, Object>) resource.get('relationships');

        for (String relName : relationships.keySet()) {
            JsonApiRelationshipDef def = config.relationshipFor(relName);
            if (def == null) {
                throw JsonApiException.badRequest(
                    'Unknown relationship "' + relName + '".',
                    JsonApiErrorSource.forPointer('/data/relationships/' + relName));
            }
            if (def.isToMany) {
                throw JsonApiException.badRequest(
                    'To-many relationship "' + relName + '" cannot be set on this resource; ' +
                    'update the related resources instead.',
                    JsonApiErrorSource.forPointer('/data/relationships/' + relName));
            }
            Object relWrapper = relationships.get(relName);
            Object linkage = relWrapper instanceof Map<String, Object>
                ? ((Map<String, Object>) relWrapper).get('data')
                : null;

            if (linkage == null) {
                record.put(def.lookupField, null);
            } else if (linkage instanceof Map<String, Object>) {
                record.put(def.lookupField, (String) ((Map<String, Object>) linkage).get('id'));
            } else {
                throw JsonApiException.badRequest(
                    'Relationship "' + relName + '" expects a single resource identifier.',
                    JsonApiErrorSource.forPointer('/data/relationships/' + relName + '/data'));
            }
        }
    }

    /** Converts an untyped JSON value into the field's native Apex type. */
    private Object coerce(Schema.SObjectField field, Object value, String attr) {
        if (field == null || value == null) {
            return value;
        }
        Schema.DisplayType dt = field.getDescribe().getType();
        String s = String.valueOf(value);
        try {
            switch on dt {
                when Boolean {
                    return value instanceof Boolean ? value : Boolean.valueOf(s);
                }
                when Integer {
                    return Integer.valueOf(s);
                }
                when Double, Currency, Percent {
                    return Double.valueOf(s);
                }
                when Date {
                    return value instanceof Date ? value : Date.valueOf(s);
                }
                when Datetime {
                    return value instanceof Datetime ? value : Datetime.valueOfGmt(s.replace('T', ' ').replace('Z', ''));
                }
                when else {
                    return s;
                }
            }
        } catch (Exception e) {
            throw JsonApiException.badRequest(
                'Value for attribute "' + attr + '" is not valid for its field type.',
                JsonApiErrorSource.forPointer('/data/attributes/' + attr));
        }
    }
}
