import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import migrateFlowToApex from '@salesforce/apex/FlowToApexService.migrate';
import migrateApexToFlow from '@salesforce/apex/ApexToFlowService.migrate';

const DIR_FLOW_TO_APEX = 'flowToApex';
const DIR_APEX_TO_FLOW = 'apexToFlow';

export default class FlowToApexConverter extends NavigationMixin(LightningElement) {

    @track direction = DIR_FLOW_TO_APEX;
    @track inputName = '';
    @track isLoading = false;
    @track result    = null;

    get directionOptions() {
        return [
            { label: 'Flow → Apex', value: DIR_FLOW_TO_APEX },
            { label: 'Apex → Flow', value: DIR_APEX_TO_FLOW }
        ];
    }

    get inputLabel() {
        return this.direction === DIR_FLOW_TO_APEX ? 'Flow API Name' : 'Apex Class Name';
    }
    get inputPlaceholder() {
        return this.direction === DIR_FLOW_TO_APEX
            ? 'e.g. Account_Set_Default_Industry'
            : 'e.g. AccountSetDefaultIndustryHandler';
    }
    get isConvertDisabled() {
        return this.isLoading || !this.inputName || this.inputName.trim() === '';
    }
    get hasResult() { return this.result !== null; }
    get isHandlerGenerated() {
        return this.result && this.result.status === 'Generated' && this.direction === DIR_FLOW_TO_APEX;
    }
    get isFlowGenerated() {
        return this.result && this.result.status === 'Generated' && this.direction === DIR_APEX_TO_FLOW;
    }
    get isRefused() {
        return this.result && this.result.status === 'NotTranslatable';
    }
    get isFailed() {
        return this.result && this.result.status === 'Failed';
    }
    get objectSuffix() {
        return (this.result && this.result.objectName)
            ? ` for ${this.result.objectName}`
            : '';
    }

    handleDirectionChange(e) {
        this.direction = e.detail.value;
        this.result = null;
    }
    handleInputChange(e) {
        this.inputName = e.target.value;
    }

    async handleConvert() {
        this.isLoading = true;
        this.result = null;
        const name = this.inputName.trim();
        try {
            this.result = this.direction === DIR_FLOW_TO_APEX
                ? await migrateFlowToApex({ flowApiName: name })
                : await migrateApexToFlow({ apexClassName: name });
        } catch (error) {
            this.result = {
                status:       'Failed',
                errorMessage: (error && error.body && error.body.message)
                                || (error && error.message)
                                || 'Unknown error',
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

    copyHandler()  { this.copyToClipboard(this.result.handlerCode, 'Handler'); }
    copyFlowXml() { this.copyToClipboard(this.result.flowXml,     'Flow XML'); }

    async copyToClipboard(text, label) {
        try {
            await navigator.clipboard.writeText(text || '');
            this.dispatchEvent(new ShowToastEvent({
                title: 'Copied', message: label + ' copied to clipboard', variant: 'success'
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Copy failed', message: e.message, variant: 'error'
            }));
        }
    }
}
