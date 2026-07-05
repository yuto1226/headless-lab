import { LightningElement } from 'lwc';
import Toast from 'lightning/toast';
import submitMessage from '@salesforce/apex/EventMessageFormController.submitMessage';

const ATTENDEE_ROLE_OPTIONS = [
    { label: '管理者', value: '管理者' },
    { label: 'ユーザー', value: 'ユーザー' },
    { label: '開発者', value: '開発者' },
    { label: 'その他', value: 'その他' }
];

export default class EventMessageForm extends LightningElement {
    attendeeRole = '';
    enthusiasm = '';
    feedbackMessage = '';
    feedbackTitle = '';
    feedbackVariant = 'info';
    isSubmitting = false;
    attendeeRoleOptions = ATTENDEE_ROLE_OPTIONS;

    get isBusy() {
        return this.isSubmitting;
    }

    get feedbackClass() {
        return `slds-notify slds-notify_alert slds-alert_${this.feedbackVariant} slds-m-bottom_medium`;
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
        this.feedbackTitle = title;
        this.feedbackMessage = message;
        this.feedbackVariant = variant;

        try {
            Toast.show({ label: title, message, variant }, this);
        } catch (error) {
            // The inline feedback above is the fallback for surfaces that suppress toasts.
        }
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }
        return error?.body?.message || error?.message || '送信に失敗しました。時間をおいて再度お試しください。';
    }
}
