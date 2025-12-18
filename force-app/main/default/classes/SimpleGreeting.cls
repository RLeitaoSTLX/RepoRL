public with sharing class SimpleGreeting {
    public static String sayHello(String name) {
        String safeName = String.isBlank(name) ? 'World' : name.trim();
        return 'Hello, ' + safeName + '!';
    }
}
