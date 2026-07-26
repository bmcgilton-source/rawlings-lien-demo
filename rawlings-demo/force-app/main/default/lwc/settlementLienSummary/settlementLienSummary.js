import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getSummary from '@salesforce/apex/SettlementLienSummaryController.getSummary';

const STATE = {
    LOADING: 'loading',
    ERROR: 'error',
    EMPTY: 'empty',
    READY: 'ready'
};

export default class SettlementLienSummary extends LightningElement {
    @api recordId;

    state = STATE.LOADING;
    errorMessage = '';
    summary;
    wiredResult;

    @wire(getSummary, { settlementId: '$recordId' })
    wiredSummary(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            this.summary = data;
            this.state = data.totalLiens === 0 ? STATE.EMPTY : STATE.READY;
        } else if (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.state = STATE.ERROR;
        }
    }

    get isLoading() {
        return this.state === STATE.LOADING;
    }

    get isError() {
        return this.state === STATE.ERROR;
    }

    get isEmpty() {
        return this.state === STATE.EMPTY;
    }

    get isReady() {
        return this.state === STATE.READY;
    }

    get stageTiles() {
        return this.summary ? this.summary.stageCounts : [];
    }

    get totalLiens() {
        return this.summary ? this.summary.totalLiens : 0;
    }

    get escalatedCount() {
        return this.summary ? this.summary.escalatedCount : 0;
    }

    get greenCount() {
        return this.summary ? this.summary.greenCount : 0;
    }

    get yellowCount() {
        return this.summary ? this.summary.yellowCount : 0;
    }

    get redCount() {
        return this.summary ? this.summary.redCount : 0;
    }

    async handleRefresh() {
        this.state = STATE.LOADING;
        try {
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.state = STATE.ERROR;
        }
    }

    extractErrorMessage(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'An unexpected error occurred while loading the lien summary.'
        );
    }
}
