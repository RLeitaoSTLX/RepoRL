public with sharing class InvoiceStatusChangeEventPublisher {
    /**
     * Publishes Invoice_Status_Change__e events when Invoice__c.Status__c changes.
     *
     * Assumptions about Platform Event fields:
     * - InvoiceId__c (Id or Text(18))
     * - OldStatus__c (Text/Picklist)
     * - NewStatus__c (Text/Picklist)
     */
    public static void publishFromAfterUpdate(List<Invoice__c> newList, Map<Id, Invoice__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        List<Invoice_Status_Change__e> events = new List<Invoice_Status_Change__e>();
        for (Invoice__c inv : newList) {
            if (inv == null) {
                continue;
            }
            Invoice__c oldInv = oldMap.get(inv.Id);
            if (oldInv == null) {
                continue;
            }

            String newStatus = inv.Status__c;
            String oldStatus = oldInv.Status__c;

            if (newStatus == oldStatus) {
                continue;
            }
            if (String.isBlank(newStatus) && String.isBlank(oldStatus)) {
                continue;
            }

            Invoice_Status_Change__e evt = new Invoice_Status_Change__e();
            evt.InvoiceId__c = inv.Id;
            evt.OldStatus__c = oldStatus;
            evt.NewStatus__c = newStatus;
            events.add(evt);
        }

        if (events.isEmpty()) {
            return;
        }

        // Bulk publish.
        EventBus.publish(events);
    }
}
