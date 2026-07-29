import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, getFieldValue, getRecordNotifyChange } from 'lightning/uiRecordApi';
import generateInstruction from '@salesforce/apex/FinanceInstructionWriter.generateInstruction';
import CLAIMANT_NAME_FIELD from '@salesforce/schema/Lien__c.Claimant_Name__c';

const STATE = {
    CONFIRM: 'confirm',
    LOADING: 'loading',
    SUCCESS: 'success',
    ERROR: 'error'
};

export default class GenerateFinanceInstruction extends LightningElement {
    @api recordId;

    state = STATE.CONFIRM;
    errorMessage;
    result;

    @wire(getRecord, { recordId: '$recordId', fields: [CLAIMANT_NAME_FIELD] })
    lienRecord;

    get claimantName() {
        return getFieldValue(this.lienRecord.data, CLAIMANT_NAME_FIELD);
    }

    get isConfirm() {
        return this.state === STATE.CONFIRM;
    }

    get isLoading() {
        return this.state === STATE.LOADING;
    }

    get isSuccess() {
        return this.state === STATE.SUCCESS;
    }

    get isError() {
        return this.state === STATE.ERROR;
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
            this.result = await generateInstruction({ lienId: this.recordId });
            this.state = STATE.SUCCESS;
            getRecordNotifyChange([{ recordId: this.recordId }]);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Finance instruction attached',
                    message: `Finance instruction attached: ${this.result.filename}`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'An unexpected error occurred.';
            this.state = STATE.ERROR;
        }
    }
}
