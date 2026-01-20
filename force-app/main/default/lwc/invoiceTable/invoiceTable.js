import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import INVOICE_OBJECT from '@salesforce/schema/Invoice__c';
import STATUS_FIELD from '@salesforce/schema/Invoice__c.Status__c';

import getInvoices from '@salesforce/apex/InvoiceTableController.getInvoices';
import submitInvoices from '@salesforce/apex/InvoiceTableController.submitInvoices';

import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

// Sentinel value for "All" filter option.
const ALL_VALUE = '__ALL__';
// Datatable column configuration.
const COLUMNS = [
    { label: 'Name', fieldName: 'Name', type: 'text' },
    { label: 'Amount', fieldName: 'Amount__c', type: 'currency' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' }
];
// Default options are available even if picklist fetch fails.
const DEFAULT_STATUS_OPTIONS = [{ label: 'All', value: ALL_VALUE }];

export default class InvoiceTable extends LightningElement {
    // Reused in the template for lightning-datatable.
    columns = COLUMNS;

    // Current filter and combobox options for Status.
    statusFilter = ALL_VALUE;
    statusOptions = DEFAULT_STATUS_OPTIONS;

    // Datatable rows and selected Ids.
    rows = [];
    selectedRowIds = [];

    // Split loading states to avoid wire overriding submit/refresh spinner state.
    isWiring = true;
    isSubmitting = false;
    isRefreshing = false;

    lastInvoicesErrorMessage;

    wiredInvoicesResult;

    @wire(getObjectInfo, { objectApiName: INVOICE_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: STATUS_FIELD
    })
    wiredStatusValues({ data, error }) {
        if (data) {
            // Build combobox options from the picklist values.
            this.statusOptions = [
                ...DEFAULT_STATUS_OPTIONS,
                ...data.values.map((v) => ({ label: v.label, value: v.value }))
            ];
        } else if (error) {
            // Fall back to just "All" (still functional)
            this.statusOptions = DEFAULT_STATUS_OPTIONS;
        }
    }

    @wire(getInvoices, { statusFilter: '$statusFilterForApex' })
    wiredInvoices(result) {
        // Keep the wired result so we can refresh after submit.
        this.wiredInvoicesResult = result;
        const { data, error } = result;

        if (data) {
            this.rows = data;
            this.isWiring = false;
            this.lastInvoicesErrorMessage = undefined;
        } else if (error) {
            this.rows = [];
            this.isWiring = false;
            this.toastInvoicesLoadErrorOnce(error);
        }
    }

    get statusFilterForApex() {
        // Translate "All" to null so Apex returns everything.
        return this.statusFilter === ALL_VALUE ? null : this.statusFilter;
    }

    get selectedCount() {
        return this.selectedRowIds.length;
    }

    get isLoading() {
        return this.isWiring || this.isSubmitting || this.isRefreshing;
    }

    get isSubmitDisabled() {
        return this.selectedRowIds.length === 0 || this.isLoading;
    }

    handleStatusChange(event) {
        // Trigger a new wire call with the updated filter.
        this.isWiring = true;
        this.statusFilter = event.detail.value;
        this.selectedRowIds = [];
    }

    handleRowSelection(event) {
        // Datatable provides full rows; store just the Ids for submit.
        const selectedRows = event.detail.selectedRows || [];
        this.selectedRowIds = selectedRows.map((r) => r.Id);
    }

    async handleSubmitSelected() {
        if (this.selectedRowIds.length === 0) return;

        this.isSubmitting = true;
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
            // Refresh the datatable data to reflect updated statuses.
            this.isRefreshing = true;
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
            this.isRefreshing = false;
            this.isSubmitting = false;
        }
    }

    toastInvoicesLoadErrorOnce(error) {
        const message = this.reduceError(error);
        if (message && message === this.lastInvoicesErrorMessage) return;
        this.lastInvoicesErrorMessage = message;

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error loading invoices',
                message,
                variant: 'error'
            })
        );
    }

    reduceError(error) {
        // Normalize Apex/UI API errors into a single string.
        const body = error?.body;
        if (Array.isArray(body)) return body.map((e) => e.message).filter(Boolean).join(', ');
        if (typeof body?.message === 'string') return body.message;
        if (typeof error?.message === 'string') return error.message;
        return 'Unknown error';
    }
}

