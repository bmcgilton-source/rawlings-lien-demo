import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import importClaimants from '@salesforce/apex/ClaimantImportController.importClaimants';

const STATE = {
    DEFAULT: 'default',
    LOADING: 'loading',
    ERROR: 'error'
};

export default class ClaimantImport extends NavigationMixin(LightningElement) {
    @api recordId;

    state = STATE.DEFAULT;
    errorMessage = '';

    get isDefault() {
        return this.state === STATE.DEFAULT;
    }

    get isLoading() {
        return this.state === STATE.LOADING;
    }

    get isError() {
        return this.state === STATE.ERROR;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleRunImport() {
        this.state = STATE.LOADING;

        try {
            const result = await importClaimants({ settlementId: this.recordId });
            this.showResultToast(result);
            this.dispatchEvent(new CloseActionScreenEvent());
            this.navigateToSettlement();
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.state = STATE.ERROR;
        }
    }

    showResultToast(result) {
        const hasRejections = result.rejectedCount > 0;

        let message =
            `${result.rowsReceived} rows processed — ${result.createdCount} created, ` +
            `${result.updatedCount} updated, ${result.rejectedCount} rejected; ` +
            `${result.automatedCount} processing automatically and ${result.escalatedCount} routed for coverage review.`;
        if (hasRejections && result.rejectionFilename) {
            message += ` Rejection file: ${result.rejectionFilename}.`;
        }

        this.dispatchEvent(
            new ShowToastEvent({
                title: hasRejections ? 'Import complete with data-quality issues' : 'Import complete',
                message,
                variant: hasRejections ? 'warning' : 'success',
                mode: 'sticky'
            })
        );
    }

    navigateToSettlement() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                actionName: 'view'
            }
        });
    }

    extractErrorMessage(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'An unexpected error occurred while importing claimants.'
        );
    }
}
