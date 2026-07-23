import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import generateResponseFile from '@salesforce/apex/ResponseFileWriter.generateResponseFile';

const STATE = {
    DEFAULT: 'default',
    LOADING: 'loading'
};

export default class GenerateResponseFile extends LightningElement {
    @api recordId;

    state = STATE.DEFAULT;

    get isDefault() {
        return this.state === STATE.DEFAULT;
    }

    get isLoading() {
        return this.state === STATE.LOADING;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleGenerate() {
        this.state = STATE.LOADING;

        try {
            await generateResponseFile({ settlementId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Response file initiated',
                    message: 'File will appear in the outbound folder in a few seconds.',
                    variant: 'success',
                    mode: 'sticky'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error generating response file',
                    message: error?.body?.message || error?.message || 'An unexpected error occurred.',
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        }

        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
