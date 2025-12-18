public with sharing class InvoiceTriggerHandler {
    private static Set<String> executedContexts = new Set<String>();

    public static void run() {
        String ctx = contextKey();
        if (executedContexts.contains(ctx)) {
            return;
        }
        executedContexts.add(ctx);

        if (Trigger.isBefore) {
            if (Trigger.isInsert) {
                beforeInsert(Trigger.new);
            } else if (Trigger.isUpdate) {
                beforeUpdate(Trigger.new, Trigger.oldMap);
            }
        } else if (Trigger.isAfter) {
            if (Trigger.isUpdate) {
                afterUpdate(Trigger.new, Trigger.oldMap);
            }
        }
    }

    @TestVisible
    private static String contextKey() {
        // Ensures the handler executes once per trigger context in the transaction.
        return String.valueOf(Trigger.operationType);
    }

    @TestVisible
    private static void beforeInsert(List<Invoice__c> newList) {
        for (Invoice__c inv : newList) {
            validateAmountNotNegative(inv);
            validateAccountRequiredWhenBecomingApproved(inv, null);
        }
    }

    @TestVisible
    private static void beforeUpdate(List<Invoice__c> newList, Map<Id, Invoice__c> oldMap) {
        for (Invoice__c inv : newList) {
            Invoice__c oldInv = oldMap != null ? oldMap.get(inv.Id) : null;
            validateAmountNotNegative(inv);
            validateAccountRequiredWhenBecomingApproved(inv, oldInv);
        }
    }

    @TestVisible
    private static void afterUpdate(List<Invoice__c> newList, Map<Id, Invoice__c> oldMap) {
        InvoiceStatusChangeEventPublisher.publishFromAfterUpdate(newList, oldMap);
    }

    private static void validateAmountNotNegative(Invoice__c inv) {
        if (inv == null) {
            return;
        }
        if (inv.Amount__c != null && inv.Amount__c < 0) {
            inv.Amount__c.addError('Amount__c não pode ser negativo.');
        }
    }

    private static void validateAccountRequiredWhenBecomingApproved(Invoice__c inv, Invoice__c oldInv) {
        if (inv == null) {
            return;
        }

        String newStatus = inv.Status__c;
        String oldStatus = oldInv == null ? null : oldInv.Status__c;

        // If status "changes" (including null->Approved on insert) to Approved, Account__c is required.
        if (newStatus == 'Approved' && oldStatus != 'Approved') {
            if (inv.Account__c == null) {
                inv.Account__c.addError('Account__c é obrigatório quando Status__c for Approved.');
            }
        }
    }
}
