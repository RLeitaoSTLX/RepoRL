import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import INVOICE_OBJECT from '@salesforce/schema/Invoice__c';
import STATUS_FIELD from '@salesforce/schema/Invoice__c.Status__c';

import getInvoices from '@salesforce/apex/InvoiceTableController.getInvoices';
import submitInvoices from '@salesforce/apex/InvoiceTableController.submitInvoices';

import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

const ALL_VALUE = '__ALL__';

export default class InvoiceTable extends LightningElement {
    columns = [
        { label: 'Name', fieldName: 'Name', type: 'text' },
        { label: 'Amount', fieldName: 'Amount__c', type: 'currency' },
        { label: 'Status', fieldName: 'Status__c', type: 'text' }
    ];

    statusFilter = ALL_VALUE;
    statusOptions = [{ label: 'All', value: ALL_VALUE }];

    rows = [];
    selectedRowIds = [];
    isLoading = false;

    wiredInvoicesResult;

    @wire(getObjectInfo, { objectApiName: INVOICE_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: STATUS_FIELD
    })
    wiredStatusValues({ data, error }) {
        if (data) {
            this.statusOptions = [
                { label: 'All', value: ALL_VALUE },
                ...data.values.map((v) => ({ label: v.label, value: v.value }))
            ];
        } else if (error) {
            // Fall back to just "All" (still functional)
            this.statusOptions = [{ label: 'All', value: ALL_VALUE }];
        }
    }

    @wire(getInvoices, { statusFilter: '$statusFilterForApex' })
    wiredInvoices(result) {
        this.wiredInvoicesResult = result;
        const { data, error } = result;

        // Wire w/ cacheable Apex: show spinner while first load/refresh is pending
        this.isLoading = !data && !error;

        if (data) {
            this.rows = data;
        } else if (error) {
            this.rows = [];
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading invoices',
                    message: this.reduceError(error),
                    variant: 'error'
                })
            );
        }
    }

    get statusFilterForApex() {
        return this.statusFilter === ALL_VALUE ? null : this.statusFilter;
    }

    get selectedCount() {
        return this.selectedRowIds.length;
    }

    get isSubmitDisabled() {
        return this.selectedRowIds.length === 0 || this.isLoading;
    }

    handleStatusChange(event) {
        this.statusFilter = event.detail.value;
        this.selectedRowIds = [];
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows || [];
        this.selectedRowIds = selectedRows.map((r) => r.Id);
    }

    async handleSubmitSelected() {
        if (this.selectedRowIds.length === 0) return;

        this.isLoading = true;
        try {
            await submitInvoices({ invoiceIds: this.selectedRowIds });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Submitted',
                    message: `${this.selectedRowIds.length} invoice(s) submitted.`,
                    variant: 'success'
                })
            );

            this.selectedRowIds = [];
            await refreshApex(this.wiredInvoicesResult);
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Submit failed',
                    message: this.reduceError(e),
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    reduceError(error) {
        // Apex errors can be: { body: { message } } or { body: [ { message } ] }
        const body = error?.body;
        if (Array.isArray(body)) return body.map((e) => e.message).filter(Boolean).join(', ');
        if (typeof body?.message === 'string') return body.message;
        if (typeof error?.message === 'string') return error.message;
        return 'Unknown error';
    }
}

