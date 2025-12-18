public with sharing class InvoiceStatusChangeSubscriberHandler {
    private static Boolean isRunning = false;

    /**
     * Bulk-safe subscriber for Invoice_Status_Change__e.
     *
     * Notes:
     * - No per-event SOQL/DML.
     * - Example implementation performs a single SOQL (optional) and no DML.
     * - Extend this method to apply business side-effects.
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

            Set<Id> invoiceIds = new Set<Id>();
            for (Invoice_Status_Change__e evt : events) {
                if (evt == null) {
                    continue;
                }
                Object rawId = evt.get('InvoiceId__c');
                if (rawId == null) {
                    continue;
                }

                // InvoiceId__c may be Id or Text(18). Normalize safely.
                try {
                    invoiceIds.add((Id)rawId);
                } catch (Exception e) {
                    try {
                        invoiceIds.add((Id)String.valueOf(rawId));
                    } catch (Exception ignore) {
                        // ignore invalid ids
                    }
                }
            }

            if (invoiceIds.isEmpty()) {
                return;
            }

            // Optional single SOQL for downstream processing.
            // Keep it narrow to remain CPU/row efficient.
            Map<Id, Invoice__c> invoicesById = new Map<Id, Invoice__c>([
                SELECT Id, Status__c
                FROM Invoice__c
                WHERE Id IN :invoiceIds
            ]);

            // Example: no-op. Put your side effects here using invoicesById.
            // e.g., enqueue a Queueable per chunk, aggregate metrics, etc.
            Integer touched = invoicesById.size();
            touched++;
            touched--;
        } finally {
            isRunning = false;
        }
    }
}
