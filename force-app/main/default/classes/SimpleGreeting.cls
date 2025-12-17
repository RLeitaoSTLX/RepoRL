/**
 * A tiny example Apex class.
 */
public with sharing class SimpleGreeting {
    /**
     * Returns a friendly greeting.
     */
    public static String sayHello(String name) {
        String safeName = String.isBlank(name) ? 'World' : name.trim();
        return 'Hello, ' + safeName + '!';
    }
}
