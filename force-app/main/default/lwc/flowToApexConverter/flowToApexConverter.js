import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import migrate from '@salesforce/apex/FlowToApexService.migrate';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class FlowToApexConverter extends NavigationMixin(LightningElement) {

    @track flowApiName = '';
    @track isLoading   = false;
    @track result      = null;

    handleInputChange(event) {
        this.flowApiName = event.target.value;
    }

    get isConvertDisabled() {
        return this.isLoading
            || !this.flowApiName
            || this.flowApiName.trim() === '';
    }

    get hasResult() {
        return this.result !== null;
    }

    get isSuccess() {
        return this.result && this.result.status === 'Generated';
    }

    async handleConvert() {
        this.isLoading = true;
        this.result    = null;

        try {
            const apiResult = await migrate({ flowApiName: this.flowApiName.trim() });
            this.result = apiResult;
        } catch (error) {
            this.result = {
                status:       'Failed',
                errorMessage: (error && error.body && error.body.message)
                                || (error && error.message)
                                || 'Unknown error',
                flowName:     this.flowApiName.trim(),
                migrationId:  null
            };
        } finally {
            this.isLoading = false;
        }
    }

    navigateToRecord() {
        if (!this.result || !this.result.migrationId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:      this.result.migrationId,
                objectApiName: 'FlowMigration__c',
                actionName:    'view'
            }
        });
    }
    copyTrigger() {
    this.copyToClipboard(this.result.triggerCode, 'Trigger');
}

copyHandler() {
    this.copyToClipboard(this.result.handlerCode, 'Handler');
}

async copyToClipboard(text, label) {
    try {
        await navigator.clipboard.writeText(text);
        this.dispatchEvent(new ShowToastEvent({
            title: 'Copied',
            message: label + ' code copied to clipboard',
            variant: 'success'
        }));
    } catch (e) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Copy failed',
            message: e.message,
            variant: 'error'
        }));
    }
}
}
