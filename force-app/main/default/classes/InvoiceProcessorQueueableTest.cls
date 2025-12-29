@isTest
public class InvoiceProcessorQueueableTest {
    @isTest
    static void execute_normalizesNullAmounts_afterStopTest() {
        // Create 2 invoices; one with null Amount__c, one with a value.
        // Use explicit inserts here to control Amount__c.
        Invoice__c invNull = new Invoice__c(
            Name = 'INV-Q-NULL',
            Status__c = 'Draft',
            Amount__c = null
        );
        Invoice__c invVal = new Invoice__c(
            Name = 'INV-Q-VAL',
            Status__c = 'Draft',
            Amount__c = 123
        );
        insert new List<Invoice__c>{ invNull, invVal };

        Set<Id> ids = new Set<Id>{ invNull.Id, invVal.Id, null };

        Test.startTest();
        System.enqueueJob(new InvoiceProcessorQueueable(ids));
        Test.stopTest();

        Map<Id, Invoice__c> reloaded = new Map<Id, Invoice__c>([
            SELECT Id, Amount__c, Status__c
            FROM Invoice__c
            WHERE Id IN :new Set<Id>{ invNull.Id, invVal.Id }
        ]);

        System.assertEquals(2, reloaded.size(), 'Deveria recarregar 2 invoices');
        System.assertEquals(0, reloaded.get(invNull.Id).Amount__c, 'Amount__c null deveria ser normalizado para 0');
        System.assertEquals(123, reloaded.get(invVal.Id).Amount__c, 'Amount__c com valor deveria permanecer inalterado');

        // Ensure we did not touch status (avoids side effects/event publishing).
        System.assertEquals('Draft', reloaded.get(invNull.Id).Status__c, 'Status__c não deveria ser alterado');
        System.assertEquals('Draft', reloaded.get(invVal.Id).Status__c, 'Status__c não deveria ser alterado');
    }

    @isTest
    static void execute_nullOrEmptyInput_noop() {
        Test.startTest();
        System.enqueueJob(new InvoiceProcessorQueueable(null));
        System.enqueueJob(new InvoiceProcessorQueueable(new Set<Id>()));
        System.enqueueJob(new InvoiceProcessorQueueable(new Set<Id>{ null }));
        Test.stopTest();

        System.assert(true, 'Jobs enfileirados com inputs vazios não devem falhar');
    }
}

