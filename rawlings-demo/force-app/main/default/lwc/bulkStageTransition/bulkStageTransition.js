import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getStageOptions from '@salesforce/apex/BulkStageTransitionController.getStageOptions';
import previewCount from '@salesforce/apex/BulkStageTransitionController.previewCount';
import enqueueBulkTransition from '@salesforce/apex/BulkStageTransitionController.enqueueBulkTransition';
import getJobStatus from '@salesforce/apex/BulkStageTransitionController.getJobStatus';

const STATE = {
    LOADING: 'loading',
    SELECT: 'select',
    PREVIEW: 'preview',
    SUBMITTING: 'submitting',
    PROGRESS: 'progress',
    ERROR: 'error'
};

const POLL_INTERVAL_MS = 5000;

// Mirrors BulkStageTransitionController's server-enforced From->To map — for display only
// (auto-filling To Stage as soon as From Stage is picked). The server re-validates every
// submission regardless, so a stale/incorrect copy here can't force a bad transition through.
const STAGE_TRANSITIONS = {
    Intake: 'Coverage Confirmed',
    'Coverage Confirmed': 'Response Ready',
    'Response Ready': 'Response Submitted',
    'Response Submitted': 'Negotiation',
    Negotiation: 'Agreed',
    Agreed: 'Recovery Calculated',
    'Recovery Calculated': 'Collected',
    Collected: 'Closed'
};

export default class BulkStageTransition extends LightningElement {
    @api recordId;

    state = STATE.LOADING;
    errorMessage = '';
    stageOptions = [];
    fromStage;
    toStage;
    previewedCount;
    jobId;
    jobItemsProcessed = 0;
    totalJobItems = 0;
    pollTimer;

    connectedCallback() {
        this.loadStageOptions();
    }

    disconnectedCallback() {
        this.clearPoll();
    }

    async loadStageOptions() {
        try {
            const options = await getStageOptions();
            this.stageOptions = options.map((stage) => ({ label: stage, value: stage }));
            this.state = STATE.SELECT;
        } catch (error) {
            this.handleError(error);
        }
    }

    get isLoading() {
        return this.state === STATE.LOADING;
    }

    get isSelect() {
        return this.state === STATE.SELECT;
    }

    get isPreview() {
        return this.state === STATE.PREVIEW;
    }

    get isSubmitting() {
        return this.state === STATE.SUBMITTING;
    }

    get isProgress() {
        return this.state === STATE.PROGRESS;
    }

    get isError() {
        return this.state === STATE.ERROR;
    }

    get isPreviewDisabled() {
        return !this.fromStage;
    }

    get isConfirmDisabled() {
        return !this.previewedCount;
    }

    get previewMessage() {
        return `This will advance ${this.previewedCount} liens from ${this.fromStage} to ${this.toStage}.`;
    }

    get progressPercent() {
        return this.totalJobItems > 0
            ? Math.round((this.jobItemsProcessed / this.totalJobItems) * 100)
            : 0;
    }

    get progressLabel() {
        return `${this.jobItemsProcessed} of ${this.totalJobItems} batches processed`;
    }

    handleFromStageChange(event) {
        this.fromStage = event.detail.value;
        this.toStage = STAGE_TRANSITIONS[this.fromStage];
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleBackToSelect() {
        this.previewedCount = undefined;
        this.state = STATE.SELECT;
    }

    async handlePreview() {
        if (!this.fromStage) {
            return;
        }
        try {
            this.previewedCount = await previewCount({
                settlementId: this.recordId,
                fromStage: this.fromStage
            });
            this.state = STATE.PREVIEW;
        } catch (error) {
            this.handleError(error);
        }
    }

    async handleConfirm() {
        this.state = STATE.SUBMITTING;
        try {
            this.jobId = await enqueueBulkTransition({
                settlementId: this.recordId,
                fromStage: this.fromStage,
                toStage: this.toStage
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Bulk transition started',
                    message: `Advancing ${this.previewedCount} liens from ${this.fromStage} to ${this.toStage}.`,
                    variant: 'success',
                    mode: 'sticky'
                })
            );
            this.state = STATE.PROGRESS;
            this.startPolling();
        } catch (error) {
            this.handleError(error);
        }
    }

    startPolling() {
        this.pollJobStatus();
        this.pollTimer = setInterval(() => this.pollJobStatus(), POLL_INTERVAL_MS);
    }

    clearPoll() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = undefined;
        }
    }

    async pollJobStatus() {
        try {
            const status = await getJobStatus({ jobId: this.jobId });
            this.jobItemsProcessed = status.jobItemsProcessed || 0;
            this.totalJobItems = status.totalJobItems || 0;

            const isDone = ['Completed', 'Failed', 'Aborted'].includes(status.status);
            if (isDone) {
                this.clearPoll();
                const succeeded = status.status === 'Completed';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: succeeded ? 'Bulk transition complete' : `Bulk transition ${status.status.toLowerCase()}`,
                        message: succeeded
                            ? `${this.previewedCount} liens moved from ${this.fromStage} to ${this.toStage}.`
                            : `The batch job ended with status ${status.status}. Check Setup > Apex Jobs for details.`,
                        variant: succeeded ? 'success' : 'error',
                        mode: 'sticky'
                    })
                );
                this.dispatchEvent(new CloseActionScreenEvent());
            }
        } catch (error) {
            this.clearPoll();
            this.handleError(error);
        }
    }

    handleError(error) {
        this.errorMessage = this.extractErrorMessage(error);
        this.state = STATE.ERROR;
    }

    extractErrorMessage(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'An unexpected error occurred.'
        );
    }
}
