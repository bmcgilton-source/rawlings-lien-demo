import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import generateResponseFile from '@salesforce/apex/ResponseFileWriter.generateResponseFile';

const STATE = {
    DEFAULT: 'default',
    LOADING: 'loading',
    RESULTS: 'results'
};

const COLUMNS = [
    { label: 'Claimant', fieldName: 'claimantName' },
    { label: 'Health Plan', fieldName: 'healthPlan' },
    { label: 'Recoverable Amount', fieldName: 'recoverableAmount', type: 'currency' },
    { label: 'Response Deadline', fieldName: 'responseDeadline', type: 'date-local' }
];

export default class GenerateResponseFile extends LightningElement {
    @api recordId;

    state = STATE.DEFAULT;
    columns = COLUMNS;
    rows = [];
    filename;

    get isDefault() {
        return this.state === STATE.DEFAULT;
    }

    get isLoading() {
        return this.state === STATE.LOADING;
    }

    get isResults() {
        return this.state === STATE.RESULTS;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleGenerate() {
        this.state = STATE.LOADING;

        try {
            const result = await generateResponseFile({ settlementId: this.recordId });
            this.filename = result.filename;
            this.rows = result.rows.map((row) => ({ ...row, id: row.claimantId }));
            this.state = STATE.RESULTS;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Response file attached',
                    message: `"${this.filename}" was added to this Settlement's Files. ${this.rows.length} response(s) marked Sent and moved to Response Submitted.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.state = STATE.DEFAULT;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error generating response file',
                    message: error?.body?.message || error?.message || 'An unexpected error occurred.',
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        }
    }
}
