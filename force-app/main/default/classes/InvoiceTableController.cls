public with sharing class InvoiceTableController {
    private static final Integer DEFAULT_LIMIT = 200;
    private static final String SUBMITTED_STATUS = 'Submitted';

    @AuraEnabled(cacheable=true)
    public static List<Invoice__c> getInvoices(String statusFilter) {
        Integer rowLimit = DEFAULT_LIMIT;

        String baseQuery =
            'SELECT Id, Name, Amount__c, Status__c ' +
            'FROM Invoice__c ';

        List<String> whereClauses = new List<String>();
        if (String.isNotBlank(statusFilter)) {
            whereClauses.add('Status__c = :statusFilter');
        }

        String wherePart = whereClauses.isEmpty() ? '' : ('WHERE ' + String.join(whereClauses, ' AND ') + ' ');
        String fullQuery = baseQuery + wherePart + 'ORDER BY CreatedDate DESC LIMIT :rowLimit';

        List<Invoice__c> rows = Database.query(fullQuery);
        return (List<Invoice__c>) Security.stripInaccessible(AccessType.READABLE, rows).getRecords();
    }

    @AuraEnabled
    public static void submitInvoices(List<Id> invoiceIds) {
        if (invoiceIds == null || invoiceIds.isEmpty()) return;

        // Validate that the target picklist value exists (avoid runtime DML error with invalid value)
        Schema.DescribeFieldResult statusDescribe = Invoice__c.Status__c.getDescribe();
        if (!statusDescribe.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update Status.');
        }

        Boolean hasSubmittedValue = false;
        for (Schema.PicklistEntry pe : statusDescribe.getPicklistValues()) {
            if (pe.getValue() == SUBMITTED_STATUS) {
                hasSubmittedValue = true;
                break;
            }
        }
        if (!hasSubmittedValue) {
            throw new AuraHandledException('Picklist value "' + SUBMITTED_STATUS + '" not found for Status__c.');
        }

        List<Invoice__c> toUpdate = [
            SELECT Id, Status__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
            FOR UPDATE
        ];

        toUpdate = (List<Invoice__c>) Security.stripInaccessible(AccessType.UPDATABLE, toUpdate).getRecords();
        for (Invoice__c inv : toUpdate) {
            inv.Status__c = SUBMITTED_STATUS;
        }
        update toUpdate;
    }
}

