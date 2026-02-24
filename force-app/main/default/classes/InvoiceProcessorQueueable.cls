public with sharing class InvoiceProcessorQueueable implements Queueable {
    private final Set<Id> invoiceIds;

    public InvoiceProcessorQueueable(Set<Id> invoiceIds) {
        this.invoiceIds = invoiceIds == null ? new Set<Id>() : new Set<Id>(invoiceIds);
    }

    public void execute(QueueableContext context) {
        if (invoiceIds.isEmpty()) {
            return;
        }

        // Defensive: remove nulls to avoid wasted work / exceptions.
        invoiceIds.remove(null);
        if (invoiceIds.isEmpty()) {
            return;
        }

        // Process invoices in bulk. Intentionally avoid touching Status__c to prevent side effects
        // (e.g., platform event publishing) when this job only needs to normalize amounts.
        List<Invoice__c> updates = new List<Invoice__c>();
        for (Invoice__c inv : [
            SELECT Id, Amount__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ]) {
            if (inv.Amount__c == null) {
                updates.add(new Invoice__c(
                    Id = inv.Id,
                    Amount__c = 0
                ));
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }
}

