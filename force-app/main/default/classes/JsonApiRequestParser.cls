/**
 * Translates raw HTTP query parameters into validated {@link JsonApiQueryOptions}.
 *
 * Salesforce exposes bracketed params verbatim (e.g. the key "fields[accounts]"),
 * so this parser splits the family ("fields") from the key ("accounts") itself.
 * Sort and filter attributes are validated against the primary resource config,
 * which both rejects bad requests early and guarantees only known fields ever
 * reach the SOQL builder.
 */
public with sharing class JsonApiRequestParser {

    private static final System.Pattern BRACKET_PATTERN =
        System.Pattern.compile('^(\\w+)\\[([^\\]]+)\\]$');

    /**
     * @param params  the raw query parameters (RestRequest.params)
     * @param config  the config of the primary resource being fetched
     */
    public static JsonApiQueryOptions parse(Map<String, String> params, JsonApiResourceConfig config) {
        JsonApiQueryOptions opts = new JsonApiQueryOptions();
        if (params == null) {
            return opts;
        }

        for (String rawKey : params.keySet()) {
            String value = params.get(rawKey);
            System.Matcher m = BRACKET_PATTERN.matcher(rawKey);

            if (m.matches()) {
                String family = m.group(1).toLowerCase();
                String key = m.group(2);
                if (family == JsonApiConstants.PARAM_FIELDS) {
                    parseSparseFields(opts, key, value);
                } else if (family == JsonApiConstants.PARAM_PAGE) {
                    parsePage(opts, key, value);
                } else if (family == JsonApiConstants.PARAM_FILTER) {
                    parseFilter(opts, config, key, value);
                }
            } else {
                String key = rawKey.toLowerCase();
                if (key == JsonApiConstants.PARAM_INCLUDE) {
                    parseInclude(opts, config, value);
                } else if (key == JsonApiConstants.PARAM_SORT) {
                    parseSort(opts, config, value);
                } else if (key == JsonApiConstants.PARAM_EXTEND) {
                    parseExtend(opts, config, value);
                }
            }
        }
        return opts;
    }

    private static void parseExtend(JsonApiQueryOptions opts, JsonApiResourceConfig config, String value) {
        if (String.isBlank(value)) {
            return;
        }
        for (String token : value.split(',')) {
            String grp = token.trim();
            if (String.isBlank(grp)) {
                continue;
            }
            // The base group is always returned; naming it is harmless but redundant.
            if (grp == JsonApiResourceConfig.BASE_GROUP) {
                continue;
            }
            if (!config.hasGroup(grp)) {
                throw JsonApiException.badRequest(
                    'Cannot extend with unknown attribute group "' + grp + '".',
                    JsonApiErrorSource.forParameter(JsonApiConstants.PARAM_EXTEND));
            }
            opts.extendGroups.add(grp);
        }
    }

    private static void parseInclude(JsonApiQueryOptions opts, JsonApiResourceConfig config, String value) {
        if (String.isBlank(value)) {
            return;
        }
        for (String path : value.split(',')) {
            String trimmed = path.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            // Validate only the first path segment against the primary config;
            // nested segments are resolved by the include resolver.
            String head = trimmed.contains('.') ? trimmed.substringBefore('.') : trimmed;
            if (config.relationshipFor(head) == null) {
                throw JsonApiException.badRequest(
                    'Cannot include unknown relationship "' + head + '".',
                    JsonApiErrorSource.forParameter(JsonApiConstants.PARAM_INCLUDE));
            }
            opts.includePaths.add(trimmed);
        }
    }

    private static void parseSparseFields(JsonApiQueryOptions opts, String type, String value) {
        Set<String> fields = new Set<String>();
        if (String.isNotBlank(value)) {
            for (String f : value.split(',')) {
                if (String.isNotBlank(f)) {
                    fields.add(f.trim());
                }
            }
        }
        opts.sparseFields.put(type.toLowerCase(), fields);
    }

    private static void parseSort(JsonApiQueryOptions opts, JsonApiResourceConfig config, String value) {
        if (String.isBlank(value)) {
            return;
        }
        for (String token : value.split(',')) {
            String trimmed = token.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            Boolean ascending = true;
            if (trimmed.startsWith('-')) {
                ascending = false;
                trimmed = trimmed.substring(1);
            }
            if (!config.hasAttribute(trimmed)) {
                throw JsonApiException.badRequest(
                    'Cannot sort by unknown attribute "' + trimmed + '".',
                    JsonApiErrorSource.forParameter(JsonApiConstants.PARAM_SORT));
            }
            opts.sorts.add(new JsonApiQueryOptions.SortField(trimmed, ascending));
        }
    }

    private static void parseFilter(JsonApiQueryOptions opts, JsonApiResourceConfig config, String attr, String value) {
        if (!config.hasAttribute(attr)) {
            throw JsonApiException.badRequest(
                'Cannot filter by unknown attribute "' + attr + '".',
                JsonApiErrorSource.forParameter('filter[' + attr + ']'));
        }
        opts.filters.put(attr, value);
    }

    private static void parsePage(JsonApiQueryOptions opts, String key, String value) {
        Integer parsed = parsePositiveInt(value, 'page[' + key + ']');
        String k = key.toLowerCase();
        if (k == JsonApiConstants.PAGE_SIZE || k == JsonApiConstants.PAGE_LIMIT) {
            opts.pageSize = Math.min(parsed, JsonApiConstants.MAX_PAGE_SIZE);
        } else if (k == JsonApiConstants.PAGE_OFFSET) {
            opts.pageOffset = Math.min(parsed, JsonApiConstants.MAX_OFFSET);
        } else if (k == JsonApiConstants.PAGE_NUMBER) {
            opts.pageNumber = Math.max(parsed, 1);
        }
        // page[number] is converted to an offset once size is known, in finalizePaging.
    }

    private static Integer parsePositiveInt(String value, String paramName) {
        try {
            Integer i = Integer.valueOf(value);
            if (i < 0) {
                throw new System.MathException();
            }
            return i;
        } catch (Exception e) {
            throw JsonApiException.badRequest(
                'Pagination parameter must be a non-negative integer.',
                JsonApiErrorSource.forParameter(paramName));
        }
    }
}
