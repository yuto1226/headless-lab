import { LightningElement } from 'lwc';
import Toast from 'lightning/toast';
import submitMessage from '@salesforce/apex/EventMessageFormController.submitMessage';
import getMessageFeed from '@salesforce/apex/EventMessageFormController.getMessageFeed';

const POLL_INTERVAL_MS = 5000;

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
    isTimelineLoading = false;
    messages = [];
    submittedMessageId;
    botReplyMessage = '';
    hasNotifiedBotReply = false;
    pollingTimer;
    attendeeRoleOptions = ATTENDEE_ROLE_OPTIONS;

    connectedCallback() {
        this.startPolling();
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    get isBusy() {
        return this.isSubmitting;
    }

    get hasMessages() {
        return this.messages.length > 0;
    }

    get isBotReplyVisible() {
        return Boolean(this.botReplyMessage);
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
            const messageId = await submitMessage({
                attendeeRole: this.attendeeRole,
                enthusiasm: this.enthusiasm
            });
            this.submittedMessageId = messageId;
            this.botReplyMessage = '';
            this.hasNotifiedBotReply = false;
            this.showToast('送信完了', '意気込みを送信しました！', 'success');
            this.clearForm();
            await this.pollMessages({ showErrors: true });
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

    startPolling() {
        if (this.pollingTimer) {
            return;
        }

        this.pollMessages({ showErrors: false });
        // Experience Cloud guest users cannot use empApi, so polling is intentional here.
        this.pollingTimer = window.setInterval(() => {
            this.pollMessages({ showErrors: false });
        }, POLL_INTERVAL_MS);
    }

    stopPolling() {
        if (this.pollingTimer) {
            window.clearInterval(this.pollingTimer);
            this.pollingTimer = undefined;
        }
    }

    async pollMessages({ showErrors }) {
        if (this.isTimelineLoading) {
            return;
        }

        this.isTimelineLoading = true;
        try {
            const feed = await getMessageFeed({ messageId: this.submittedMessageId });
            this.messages = (feed?.messages || []).map((message) => ({
                ...message,
                formattedCreatedDate: this.formatDateTime(message.createdDate),
                hasReply: Boolean(message.replyMessage)
            }));
            this.handleSubmittedMessage(feed?.submittedMessage);
        } catch (error) {
            if (showErrors) {
                this.showToast('取得エラー', this.reduceError(error), 'error');
            }
        } finally {
            this.isTimelineLoading = false;
        }
    }

    handleSubmittedMessage(submittedMessage) {
        const replyMessage = submittedMessage?.replyMessage;
        if (!replyMessage || this.hasNotifiedBotReply) {
            return;
        }

        this.botReplyMessage = replyMessage;
        this.hasNotifiedBotReply = true;
        this.showToast(
            'Agentforceからのお礼メッセージが届きました！',
            replyMessage,
            'success'
        );
    }

    formatDateTime(value) {
        if (!value) {
            return '';
        }

        return new Intl.DateTimeFormat('ja-JP', {
            month: 'numeric',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        }).format(new Date(value));
    }

    showToast(title, message, variant) {
        this.feedbackTitle = title;
        this.feedbackMessage = message;
        this.feedbackVariant = variant;

        try {
            Toast.show({ label: title, message, variant }, this);
        } catch {
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
