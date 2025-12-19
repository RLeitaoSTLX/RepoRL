trigger InvoiceTrigger on Invoice__c (before insert, before update, after update) {
    InvoiceTriggerHandler.run();
}
