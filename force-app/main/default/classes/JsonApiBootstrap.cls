/**
 * The single place where resource configs are wired into the framework.
 * Add a line here for every {@link JsonApiResourceConfig} you create.
 *
 * (If you prefer configuration-driven registration, swap the body of
 * {@link #registerAll} for a Custom Metadata Type query that instantiates
 * each config class via Type.forName.)
 */
public with sharing class JsonApiBootstrap {
    public static void registerAll() {
        JsonApiRegistry.register(new AccountResourceConfig());
        JsonApiRegistry.register(new ContactResourceConfig());
    }
}
