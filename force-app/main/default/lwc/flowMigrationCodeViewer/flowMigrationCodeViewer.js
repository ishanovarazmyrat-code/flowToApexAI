import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import GENERATED_APEX_FIELD from '@salesforce/schema/FlowMigration__c.Generated_Apex__c';

const FIELDS = [GENERATED_APEX_FIELD];

export default class FlowMigrationCodeViewer extends LightningElement {
    @api recordId;
    triggerCode = '';
    handlerCode = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            const combined = getFieldValue(data, GENERATED_APEX_FIELD) || '';
            const parsed = this.parseGeneratedApex(combined);
            this.triggerCode = parsed.trigger;
            this.handlerCode = parsed.handler;
        }
    }

    get hasCode() {
        return (this.triggerCode && this.triggerCode.length > 0)
            || (this.handlerCode && this.handlerCode.length > 0);
    }

    parseGeneratedApex(combined) {
        const trigMarker = '// ===== TRIGGER =====';
        const handMarker = '// ===== HANDLER =====';
        const trigStart = combined.indexOf(trigMarker);
        const handStart = combined.indexOf(handMarker);
        if (trigStart === -1 || handStart === -1) {
            return { trigger: '', handler: combined.trim() };
        }
        const trigger = combined.substring(trigStart + trigMarker.length, handStart).trim();
        const handler = combined.substring(handStart + handMarker.length).trim();
        return { trigger, handler };
    }

    copyTrigger() { this.copyToClipboard(this.triggerCode, 'Trigger'); }
    copyHandler() { this.copyToClipboard(this.handlerCode, 'Handler'); }

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