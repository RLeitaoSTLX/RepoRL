@isTest
public class InvoiceTestFactory {
    public static Account createAccount() {
        Account a = new Account(
            Name = 'Test Account ' + String.valueOf(DateTime.now().getTime())
        );
        insert a;
        return a;
    }

    public static List<Invoice__c> createInvoices(Integer count, String status, Id accountId) {
        System.assertNotEquals(null, count, 'count não pode ser null');
        System.assert(count > 0, 'count deve ser > 0');

        List<Invoice__c> invoices = new List<Invoice__c>();
        Long seed = DateTime.now().getTime();
        for (Integer i = 0; i < count; i++) {
            Invoice__c inv = new Invoice__c();
            inv.Name = 'INV-' + String.valueOf(seed) + '-' + String.valueOf(i);
            inv.Status__c = status;
            inv.Amount__c = 100;
            if (accountId != null) {
                inv.Account__c = accountId;
            }
            invoices.add(inv);
        }
        insert invoices;
        return invoices;
    }

    public static Invoice__c createInvoice(String status, Boolean withAccount) {
        Id accountId = withAccount ? createAccount().Id : null;
        return createInvoices(1, status, accountId)[0];
    }
}

