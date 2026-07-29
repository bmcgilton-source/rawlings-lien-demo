import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class ClaimantFileUpload extends LightningElement {
    @api recordId;
    @api contentDocumentId;

    acceptedFormats = ['.csv'];

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        if (uploadedFiles && uploadedFiles.length > 0) {
            this.contentDocumentId = uploadedFiles[0].documentId;
            this.dispatchEvent(new FlowAttributeChangeEvent('contentDocumentId', this.contentDocumentId));
        }
    }
}
