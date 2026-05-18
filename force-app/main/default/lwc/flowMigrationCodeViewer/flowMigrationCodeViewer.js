import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import APEX_FIELD      from '@salesforce/schema/FlowMigration__c.Generated_Apex__c';
import FLOW_XML_FIELD  from '@salesforce/schema/FlowMigration__c.Generated_Flow_XML__c';
import DIRECTION_FIELD from '@salesforce/schema/FlowMigration__c.Direction__c';
import STATUS_FIELD    from '@salesforce/schema/FlowMigration__c.Status__c';
import ERROR_FIELD     from '@salesforce/schema/FlowMigration__c.Error_Message__c';

const FIELDS = [APEX_FIELD, FLOW_XML_FIELD, DIRECTION_FIELD, STATUS_FIELD, ERROR_FIELD];

export default class FlowMigrationCodeViewer extends LightningElement {
    @api recordId;
    apexCode      = '';
    flowXml       = '';
    direction     = '';
    status        = '';
    errorMessage  = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this.apexCode     = getFieldValue(data, APEX_FIELD)      || '';
            this.flowXml      = getFieldValue(data, FLOW_XML_FIELD)  || '';
            this.direction    = getFieldValue(data, DIRECTION_FIELD) || '';
            this.status       = getFieldValue(data, STATUS_FIELD)    || '';
            this.errorMessage = getFieldValue(data, ERROR_FIELD)     || '';
        }
    }

    // Render decisions prefer Direction__c when present, but fall back to
    // whichever output field is populated. This keeps the component working
    // even when Direction__c is missing from the page layout, lacks FLS read
    // for the running user, or was null on legacy records.

    get isHandlerCase() {
        if (this.direction === 'Apex_To_Flow') return false;
        return this.apexCode.length > 0;
    }
    get isFlowCase() {
        if (this.direction === 'Flow_To_Apex') return false;
        if (this.flowXml.length === 0) return false;
        // When direction is unknown, only treat as Flow-case if no apex output exists
        return this.direction === 'Apex_To_Flow' || this.apexCode.length === 0;
    }
    get isRefusedCase() {
        if (this.direction === 'Flow_To_Apex') return false;
        return this.apexCode.length === 0
            && this.flowXml.length === 0
            && this.errorMessage.length > 0;
    }
    get isEmptyCase() {
        return !this.isHandlerCase && !this.isFlowCase && !this.isRefusedCase;
    }

    copyApex()    { this.copyToClipboard(this.apexCode, 'Handler'); }
    copyFlowXml() { this.copyToClipboard(this.flowXml,  'Flow XML'); }

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
