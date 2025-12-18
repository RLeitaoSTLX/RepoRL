public with sharing class InvoiceService {
    /**
     * Simple result container for bulk operations.
     */
    public class Result {
        public Set<Id> successIds { get; private set; }
        public Map<Id, String> errorById { get; private set; }

        public Result() {
            successIds = new Set<Id>();
            errorById = new Map<Id, String>();
        }

        public Boolean hasErrors() {
            return !errorById.isEmpty();
        }
    }

    private static final String STATUS_DRAFT = 'Draft';
    private static final String STATUS_SUBMITTED = 'Submitted';
    private static final String STATUS_APPROVED = 'Approved';

    /**
     * Transition Invoice__c.Status__c from Draft -> Submitted.
     */
    public static Result submitInvoices(Set<Id> invoiceIds) {
        return transition(invoiceIds, STATUS_DRAFT, STATUS_SUBMITTED);
    }

    /**
     * Transition Invoice__c.Status__c from Submitted -> Approved.
     */
    public static Result approveInvoices(Set<Id> invoiceIds) {
        return transition(invoiceIds, STATUS_SUBMITTED, STATUS_APPROVED);
    }

    @TestVisible
    private static Result transition(Set<Id> invoiceIds, String fromStatus, String toStatus) {
        Result result = new Result();

        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return result;
        }

        // Defensive: remove nulls to avoid NPEs and wasted work.
        invoiceIds.remove(null);
        if (invoiceIds.isEmpty()) {
            return result;
        }

        // CRUD checks
        Schema.DescribeSObjectResult d = Invoice__c.SObjectType.getDescribe();
        if (!d.isAccessible()) {
            // Avoid O(n) error population on permission failures.
            result.errorById.put(invoiceIds.iterator().next(), 'Sem permissão de leitura em Invoice__c.');
            return result;
        }
        if (!d.isUpdateable()) {
            // Avoid O(n) error population on permission failures.
            result.errorById.put(invoiceIds.iterator().next(), 'Sem permissão de atualização em Invoice__c.');
            return result;
        }

        // FLS checks
        Schema.DescribeFieldResult statusFld = Invoice__c.Status__c.getDescribe();
        if (!statusFld.isAccessible()) {
            // Avoid O(n) error population on permission failures.
            result.errorById.put(invoiceIds.iterator().next(), 'Sem permissão de leitura no campo Status__c.');
            return result;
        }
        if (!statusFld.isUpdateable()) {
            // Avoid O(n) error population on permission failures.
            result.errorById.put(invoiceIds.iterator().next(), 'Sem permissão de atualização no campo Status__c.');
            return result;
        }

        // Fetch only invoices that are eligible for the transition (reduces rows/CPU on the happy path).
        // We already enforce CRUD/FLS via describe checks above, so we avoid redundant WITH SECURITY_ENFORCED
        // and stripInaccessible overhead for this narrow update (Status__c only).
        Map<Id, Invoice__c> eligibleById = new Map<Id, Invoice__c>([
            SELECT Id, Status__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
            AND Status__c = :fromStatus
        ]);

        List<Invoice__c> toUpdate = new List<Invoice__c>();
        for (Invoice__c inv : eligibleById.values()) {
            inv.Status__c = toStatus;
            toUpdate.add(inv);
        }

        // Any id not returned by the filtered query is either missing, inaccessible, or not in the required fromStatus.
        // To keep SOQL usage low, we return a generic error for those ids (instead of a second query to disambiguate).
        if (eligibleById.size() != invoiceIds.size()) {
            Set<Id> notEligible = new Set<Id>(invoiceIds);
            notEligible.removeAll(eligibleById.keySet());
            for (Id invoiceId : notEligible) {
                result.errorById.put(invoiceId, 'Invoice não encontrado, sem acesso, ou com status inválido para transição.');
            }
        }

        if (toUpdate.isEmpty()) {
            return result;
        }

        Database.SaveResult[] srList = Database.update(toUpdate, false);
        for (Integer idx = 0; idx < srList.size(); idx++) {
            Database.SaveResult sr = srList[idx];
            Id recordId = toUpdate[idx].Id;

            if (sr.isSuccess()) {
                result.successIds.add(recordId);
            } else {
                String msg = (sr.getErrors() != null && !sr.getErrors().isEmpty())
                    ? sr.getErrors()[0].getMessage()
                    : 'Falha desconhecida ao atualizar.';
                result.errorById.put(recordId, msg);
            }
        }

        return result;
    }
}
