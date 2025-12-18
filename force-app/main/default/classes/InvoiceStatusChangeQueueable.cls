public with sharing class InvoiceStatusChangeQueueable implements Queueable {
    public class Change {
        @AuraEnabled public Id invoiceId;
        @AuraEnabled public String oldStatus;
        @AuraEnabled public String newStatus;
    }

    private final List<Change> changes;

    public InvoiceStatusChangeQueueable(List<Change> changes) {
        this.changes = changes == null ? new List<Change>() : changes;
    }

    public void execute(QueueableContext context) {
        if (changes.isEmpty()) {
            return;
        }

        Set<Id> invoiceIds = new Set<Id>();
        for (Change c : changes) {
            if (c != null && c.invoiceId != null) {
                invoiceIds.add(c.invoiceId);
            }
        }
        if (invoiceIds.isEmpty()) {
            return;
        }

        // Single SOQL for this chunk.
        Map<Id, Invoice__c> invoicesById = new Map<Id, Invoice__c>([
            SELECT Id, Status__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ]);

        // High-volume-friendly processing point.
        // - No DML in loops: aggregate any updates into a list, then do one DML call.
        // - Keep logic idempotent (platform events can be replayed).
        InvoiceStatusChangeProcessor.process(changes, invoicesById);
    }
}
