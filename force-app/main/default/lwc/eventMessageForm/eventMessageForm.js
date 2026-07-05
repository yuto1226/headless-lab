import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import submitMessage from '@salesforce/apex/EventMessageFormController.submitMessage';
import EVENT_MESSAGE_OBJECT from '@salesforce/schema/EventMessage__c';
import ATTENDEE_ROLE_FIELD from '@salesforce/schema/EventMessage__c.AttendeeRole__c';

export default class EventMessageForm extends LightningElement {
    attendeeRole = '';
    enthusiasm = '';
    isSubmitting = false;
    isLoadingRoles = true;
    recordTypeId;
    attendeeRoleOptions = [];

    get isBusy() {
        return this.isSubmitting || this.isLoadingRoles;
    }

    @wire(getObjectInfo, { objectApiName: EVENT_MESSAGE_OBJECT })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
            return;
        }
        if (error) {
            this.isLoadingRoles = false;
            this.showToast('読み込みエラー', this.reduceError(error), 'error');
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: ATTENDEE_ROLE_FIELD
    })
    wiredAttendeeRoles({ data, error }) {
        if (data) {
            this.attendeeRoleOptions = data.values.map((entry) => ({
                label: entry.label,
                value: entry.value
            }));
            this.isLoadingRoles = false;
            return;
        }
        if (error) {
            this.attendeeRoleOptions = [];
            this.isLoadingRoles = false;
            this.showToast('読み込みエラー', this.reduceError(error), 'error');
        }
    }

    handleRoleChange(event) {
        this.attendeeRole = event.detail.value;
    }

    handleEnthusiasmChange(event) {
        this.enthusiasm = event.detail.value;
    }

    async handleSubmit() {
        if (!this.reportValidity()) {
            return;
        }

        this.isSubmitting = true;
        try {
            await submitMessage({
                attendeeRole: this.attendeeRole,
                enthusiasm: this.enthusiasm
            });
            this.showToast('送信完了', '意気込みを送信しました！', 'success');
            this.clearForm();
        } catch (error) {
            this.showToast('送信エラー', this.reduceError(error), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    reportValidity() {
        return [...this.template.querySelectorAll('lightning-combobox, lightning-textarea')]
            .reduce((isValid, field) => field.reportValidity() && isValid, true);
    }

    clearForm() {
        this.attendeeRole = '';
        this.enthusiasm = '';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }
        return error?.body?.message || error?.message || '送信に失敗しました。時間をおいて再度お試しください。';
    }
}
