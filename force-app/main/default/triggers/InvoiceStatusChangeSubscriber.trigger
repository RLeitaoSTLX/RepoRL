trigger InvoiceStatusChangeSubscriber on Invoice_Status_Change__e (after insert) {
    InvoiceStatusChangeSubscriberHandler.handle(Trigger.new);
}
