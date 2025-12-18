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

        // CRUD checks
        Schema.DescribeSObjectResult d = Invoice__c.SObjectType.getDescribe();
        if (!d.isAccessible()) {
            for (Id i : invoiceIds) {
                result.errorById.put(i, 'Sem permissão de leitura em Invoice__c.');
            }
            return result;
        }
        if (!d.isUpdateable()) {
            for (Id i : invoiceIds) {
                result.errorById.put(i, 'Sem permissão de atualização em Invoice__c.');
            }
            return result;
        }

        // FLS checks
        Schema.DescribeFieldResult statusFld = Invoice__c.Status__c.getDescribe();
        if (!statusFld.isAccessible()) {
            for (Id i : invoiceIds) {
                result.errorById.put(i, 'Sem permissão de leitura no campo Status__c.');
            }
            return result;
        }
        if (!statusFld.isUpdateable()) {
            for (Id i : invoiceIds) {
                result.errorById.put(i, 'Sem permissão de atualização no campo Status__c.');
            }
            return result;
        }

        Map<Id, Invoice__c> byId = new Map<Id, Invoice__c>();
        try {
            for (Invoice__c inv : [
                SELECT Id, Status__c
                FROM Invoice__c
                WHERE Id IN :invoiceIds
                WITH SECURITY_ENFORCED
            ]) {
                byId.put(inv.Id, inv);
            }
        } catch (Exception e) {
            for (Id i : invoiceIds) {
                result.errorById.put(i, 'Falha ao consultar invoices (FLS/CRUD): ' + e.getMessage());
            }
            return result;
        }

        List<Invoice__c> toUpdate = new List<Invoice__c>();
        for (Id invoiceId : invoiceIds) {
            Invoice__c inv = byId.get(invoiceId);
            if (inv == null) {
                result.errorById.put(invoiceId, 'Invoice não encontrado ou sem acesso.');
                continue;
            }

            String current = inv.Status__c;
            if (String.isBlank(current)) {
                result.errorById.put(invoiceId, 'Status__c está vazio.');
                continue;
            }

            if (current != fromStatus) {
                result.errorById.put(invoiceId, 'Transição inválida: status atual = ' + current + ', esperado = ' + fromStatus + '.');
                continue;
            }

            inv.Status__c = toStatus;
            toUpdate.add(inv);
        }

        if (toUpdate.isEmpty()) {
            return result;
        }

        // Strip any fields not updatable (defensive) before DML
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
        List<SObject> safeRecords = decision.getRecords();

        Database.SaveResult[] srList = Database.update(safeRecords, false);
        for (Integer idx = 0; idx < srList.size(); idx++) {
            Database.SaveResult sr = srList[idx];
            Id recordId = (Id)safeRecords[idx].get('Id');

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
