@IsTest
private class SimpleGreetingTest {
    @IsTest
    static void sayHello_defaultsToWorldWhenBlank() {
        System.assertEquals('Hello, World!', SimpleGreeting.sayHello(null));
        System.assertEquals('Hello, World!', SimpleGreeting.sayHello(''));
        System.assertEquals('Hello, World!', SimpleGreeting.sayHello('   '));
    }

    @IsTest
    static void sayHello_trimsName() {
        System.assertEquals('Hello, Ada!', SimpleGreeting.sayHello('  Ada  '));
    }
}
