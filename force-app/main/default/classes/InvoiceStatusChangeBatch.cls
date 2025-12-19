public with sharing class InvoiceStatusChangeBatch implements Database.Batchable<Id> {
    private final List<Id> ids;

    public InvoiceStatusChangeBatch(Set<Id> invoiceIds) {
        this.ids = invoiceIds == null ? new List<Id>() : new List<Id>(invoiceIds);
    }

    public Iterable<Id> start(Database.BatchableContext bc) {
        return new IdIterable(ids);
    }

    public void execute(Database.BatchableContext bc, List<Id> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        Map<Id, Invoice__c> invoicesById = new Map<Id, Invoice__c>([
            SELECT Id, Status__c
            FROM Invoice__c
            WHERE Id IN :scope
        ]);

        // Batch fallback does not include old/new statuses.
        // Extend as needed if you persist the event payload elsewhere.
        InvoiceStatusChangeProcessor.processIdsOnly(new Set<Id>(scope), invoicesById);
    }

    public void finish(Database.BatchableContext bc) {
    }

    private class IdIterable implements Iterable<Id> {
        private final List<Id> inner;
        IdIterable(List<Id> inner) {
            this.inner = inner == null ? new List<Id>() : inner;
        }
        public Iterator<Id> iterator() {
            return new IdIterator(inner);
        }
    }

    private class IdIterator implements Iterator<Id> {
        private final List<Id> inner;
        private Integer idx = 0;
        IdIterator(List<Id> inner) {
            this.inner = inner == null ? new List<Id>() : inner;
        }
        public Boolean hasNext() {
            return idx < inner.size();
        }
        public Id next() {
            return inner[idx++];
        }
    }
}
