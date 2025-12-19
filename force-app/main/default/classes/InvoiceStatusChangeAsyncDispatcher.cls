public with sharing class InvoiceStatusChangeAsyncDispatcher {
    // Keep queueables small to reduce heap/CPU and allow high-volume ingestion.
    private static final Integer MAX_CHANGES_PER_QUEUEABLE = 1000;
    // Max enqueueJob calls per transaction is 50; leave buffer for other app code.
    private static final Integer MAX_QUEUEABLE_JOBS_PER_TX = 45;

    public static void dispatch(List<InvoiceStatusChangeQueueable.Change> changes) {
        if (changes == null || changes.isEmpty()) {
            return;
        }

        Integer total = changes.size();
        Integer chunks = (Integer)Math.ceil((Decimal)total / (Decimal)MAX_CHANGES_PER_QUEUEABLE);

        // If the event delivery is extremely large, fall back to Batch to avoid exceeding enqueue limits.
        if (chunks > MAX_QUEUEABLE_JOBS_PER_TX) {
            Set<Id> invoiceIds = new Set<Id>();
            for (InvoiceStatusChangeQueueable.Change c : changes) {
                if (c != null && c.invoiceId != null) {
                    invoiceIds.add(c.invoiceId);
                }
            }
            if (!invoiceIds.isEmpty()) {
                Database.executeBatch(new InvoiceStatusChangeBatch(invoiceIds), 200);
            }
            return;
        }

        for (Integer startIdx = 0; startIdx < total; startIdx += MAX_CHANGES_PER_QUEUEABLE) {
            Integer endIdxExclusive = Math.min(startIdx + MAX_CHANGES_PER_QUEUEABLE, total);
            List<InvoiceStatusChangeQueueable.Change> slice = changes.subList(startIdx, endIdxExclusive);
            System.enqueueJob(new InvoiceStatusChangeQueueable(slice));
        }
    }
}
