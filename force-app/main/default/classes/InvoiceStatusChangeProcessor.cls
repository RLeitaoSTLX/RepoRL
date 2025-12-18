public with sharing class InvoiceStatusChangeProcessor {
    /**
     * Processing entry point when we still have event payload (old/new status).
     *
     * IMPORTANT for scale:
     * - Never do SOQL/DML inside loops.
     * - Aggregate updates into lists, then perform 1 DML.
     * - Keep logic idempotent (platform events can be replayed).
     */
    public static void process(
        List<InvoiceStatusChangeQueueable.Change> changes,
        Map<Id, Invoice__c> invoicesById
    ) {
        if (changes == null || changes.isEmpty() || invoicesById == null || invoicesById.isEmpty()) {
            return;
        }

        // Default behavior: no-op.
        // Add your business side-effects here.
        // Example pattern (commented):
        // List<Invoice__c> updates = new List<Invoice__c>();
        // for (InvoiceStatusChangeQueueable.Change c : changes) {
        //     Invoice__c inv = invoicesById.get(c.invoiceId);
        //     if (inv == null) continue;
        //     // ... decide changes ...
        //     updates.add(new Invoice__c(Id = inv.Id, SomeField__c = '...'));
        // }
        // if (!updates.isEmpty()) {
        //     update updates;
        // }
    }

    /**
     * Fallback processing when we only have invoice ids (Batch path).
     */
    public static void processIdsOnly(Set<Id> invoiceIds, Map<Id, Invoice__c> invoicesById) {
        if (invoiceIds == null || invoiceIds.isEmpty() || invoicesById == null || invoicesById.isEmpty()) {
            return;
        }

        // Default behavior: no-op.
    }
}
