public with sharing class InvoiceStatusChangeSubscriberHandler {
    private static Boolean isRunning = false;

    /**
     * Bulk-safe subscriber for Invoice_Status_Change__e.
     *
     * Notes:
     * - No SOQL/DML here (keep platform-event trigger fast).
     * - Work is offloaded to Queueable (and Batch fallback for very large volumes).
     */
    public static void handle(List<Invoice_Status_Change__e> events) {
        if (isRunning) {
            return;
        }
        isRunning = true;
        try {
            if (events == null || events.isEmpty()) {
                return;
            }

            List<InvoiceStatusChangeQueueable.Change> changes = new List<InvoiceStatusChangeQueueable.Change>();
            for (Invoice_Status_Change__e evt : events) {
                if (evt == null) {
                    continue;
                }
                Object rawId = evt.get('InvoiceId__c');
                if (rawId == null) {
                    continue;
                }

                // InvoiceId__c may be Id or Text(18). Normalize safely.
                Id invoiceId;
                try {
                    invoiceId = (Id)rawId;
                } catch (Exception e) {
                    try {
                        invoiceId = (Id)String.valueOf(rawId);
                    } catch (Exception ignore) {
                        continue; // ignore invalid ids
                    }
                }

                InvoiceStatusChangeQueueable.Change c = new InvoiceStatusChangeQueueable.Change();
                c.invoiceId = invoiceId;
                c.oldStatus = (String)evt.get('OldStatus__c');
                c.newStatus = (String)evt.get('NewStatus__c');
                changes.add(c);
            }

            if (changes.isEmpty()) {
                return;
            }

            // Offload work. Chunking avoids heap spikes and stays within queueable-per-tx limits.
            InvoiceStatusChangeAsyncDispatcher.dispatch(changes);
        } finally {
            isRunning = false;
        }
    }
}
