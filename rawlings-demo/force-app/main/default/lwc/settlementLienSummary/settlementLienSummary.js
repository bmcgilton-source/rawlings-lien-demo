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

    get activeStageTiles() {
        return this.stageTiles.filter((tile) => tile.count > 0);
    }

    get hasActiveStages() {
        return this.activeStageTiles.length > 0;
    }

    get hiddenStageNote() {
        const hiddenCount = this.stageTiles.length - this.activeStageTiles.length;
        if (hiddenCount <= 0) {
            return '';
        }
        return hiddenCount === 1
            ? '1 stage with 0 liens hidden'
            : `${hiddenCount} stages with 0 liens hidden`;
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

    get hasDeadlineData() {
        return this.greenCount + this.yellowCount + this.redCount > 0;
    }

    get deadlineSegments() {
        return [
            { key: 'green', count: this.greenCount, cssClass: 'lsg-seg lsg-seg_green' },
            { key: 'yellow', count: this.yellowCount, cssClass: 'lsg-seg lsg-seg_yellow' },
            { key: 'red', count: this.redCount, cssClass: 'lsg-seg lsg-seg_red' }
        ]
            .filter((seg) => seg.count > 0)
            .map((seg) => ({ ...seg, style: `flex-grow: ${seg.count}` }));
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
