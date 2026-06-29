import { LightningElement } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import deleteLog from '@salesforce/apex/HabitCalendarController.deleteLog';
import deleteLogByDate from '@salesforce/apex/HabitCalendarController.deleteLogByDate';
import getMonthlyLogs from '@salesforce/apex/HabitCalendarController.getMonthlyLogs';
import saveLog from '@salesforce/apex/HabitCalendarController.saveLog';

const HABIT_OPTIONS = [
    { label: '筋トレ', value: '筋トレ' },
    { label: 'Speakでの英語学習', value: 'Speakでの英語学習' },
    { label: '読書', value: '読書' },
    { label: 'Codexでの個人開発', value: 'Codexでの個人開発' }
];
const WEEKDAY_LABELS = ['日', '月', '火', '水', '木', '金', '土'];

export default class HabitCalendar extends LightningElement {
    currentDate = new Date();
    logs = [];
    errorMessage;
    isSaving = false;
    isDeleting = false;
    isModalOpen = false;
    selectedDate;
    selectedHasLog = false;
    selectedLogId;
    form = {
        habits: [],
        memo: ''
    };

    habitOptions = HABIT_OPTIONS;
    weekdayLabels = WEEKDAY_LABELS;

    connectedCallback() {
        this.loadMonthlyLogs();
    }

    get monthLabel() {
        return new Intl.DateTimeFormat('ja-JP', {
            year: 'numeric',
            month: 'long'
        }).format(this.currentDate);
    }

    get calendarAriaLabel() {
        return `${this.monthLabel}の習慣記録カレンダー`;
    }

    get selectedDateLabel() {
        return this.selectedDate ? `${this.formatDate(this.selectedDate)}の習慣記録` : '習慣記録';
    }

    get hasExistingLog() {
        return this.selectedHasLog;
    }

    get modalModeText() {
        return this.hasExistingLog ? '登録済みの記録を編集中です。' : '新しい記録を作成します。';
    }

    get isBusy() {
        return this.isSaving || this.isDeleting;
    }

    get calendarDays() {
        const logsByDate = new Map(this.logs.map((log) => [log.logDateKey, log]));
        const year = this.currentDate.getFullYear();
        const month = this.currentDate.getMonth();
        const firstDay = new Date(year, month, 1);
        const lastDay = new Date(year, month + 1, 0);
        const todayIso = this.toIsoDate(new Date());
        const selectedIso = this.selectedDate;
        const days = [];

        for (let index = 0; index < firstDay.getDay(); index += 1) {
            days.push({
                key: `blank-start-${index}`,
                className: 'habit-day habit-day_blank',
                isBlank: true
            });
        }

        for (let dayNumber = 1; dayNumber <= lastDay.getDate(); dayNumber += 1) {
            const date = new Date(year, month, dayNumber);
            const isoDate = this.toIsoDate(date);
            const log = logsByDate.get(isoDate);
            const classes = ['habit-day'];
            if (isoDate === todayIso) {
                classes.push('habit-day_today');
            }
            if (isoDate === selectedIso) {
                classes.push('habit-day_selected');
            }
            if (log) {
                classes.push('habit-day_recorded');
            }
            days.push({
                key: isoDate,
                isoDate,
                dayNumber: String(dayNumber),
                hasLog: Boolean(log),
                habitLabel: this.getHabitLabel(log),
                className: classes.join(' '),
                ariaLabel: `${this.formatDate(isoDate)} ${log ? '記録済み' : '未記録'}`,
                isBlank: false
            });
        }

        while (days.length % 7 !== 0) {
            days.push({
                key: `blank-end-${days.length}`,
                className: 'habit-day habit-day_blank',
                isBlank: true
            });
        }
        return days;
    }

    async loadMonthlyLogs() {
        this.errorMessage = undefined;
        try {
            const monthlyLogs = await getMonthlyLogs({
                year: this.currentDate.getFullYear(),
                month: this.currentDate.getMonth() + 1
            });
            this.logs = (monthlyLogs || []).map((log) => this.normalizeLog(log));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    handlePreviousMonth() {
        this.currentDate = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth() - 1, 1);
        this.selectedDate = undefined;
        this.selectedHasLog = false;
        this.selectedLogId = undefined;
        this.loadMonthlyLogs();
    }

    handleNextMonth() {
        this.currentDate = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth() + 1, 1);
        this.selectedDate = undefined;
        this.selectedHasLog = false;
        this.selectedLogId = undefined;
        this.loadMonthlyLogs();
    }

    handleToday() {
        this.currentDate = new Date();
        this.selectedDate = this.toIsoDate(this.currentDate);
        this.loadMonthlyLogs();
    }

    handleDaySelect(event) {
        const selectedDate = event.currentTarget.dataset.date;
        const existingLog = this.logs.find((log) => log.logDateKey === selectedDate);
        this.selectedDate = selectedDate;
        this.selectedHasLog = Boolean(existingLog);
        this.selectedLogId = this.getLogId(existingLog);
        this.form = {
            habits: existingLog?.habitValues || [],
            memo: existingLog?.memo || ''
        };
        this.isModalOpen = true;
    }

    handleHabitsChange(event) {
        this.form = { ...this.form, habits: event.detail.value };
    }

    handleMemoChange(event) {
        this.form = { ...this.form, memo: event.target.value };
    }

    handleCancel() {
        this.isModalOpen = false;
    }

    async handleSave() {
        this.errorMessage = undefined;
        if (!this.selectedDate || !this.form.habits?.length) {
            this.errorMessage = '実施した習慣を1つ以上選択してください。';
            return;
        }

        this.isSaving = true;
        try {
            await saveLog({
                logDate: this.selectedDate,
                habits: this.form.habits,
                memo: this.form.memo
            });
            this.dispatchEvent(new ShowToastEvent({
                title: '保存しました',
                message: `${this.formatDate(this.selectedDate)}の習慣記録を保存しました。`,
                variant: 'success'
            }));
            this.isModalOpen = false;
            await this.loadMonthlyLogs();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleDelete() {
        if (!this.selectedHasLog || !this.selectedDate) {
            return;
        }

        const shouldDelete = await LightningConfirm.open({
            label: '習慣記録の削除',
            message: `${this.formatDate(this.selectedDate)}の習慣記録を削除しますか？`,
            theme: 'warning'
        });
        if (!shouldDelete) {
            return;
        }

        this.errorMessage = undefined;
        this.isDeleting = true;
        try {
            if (this.selectedLogId) {
                await deleteLog({ logId: this.selectedLogId });
            } else {
                await deleteLogByDate({ logDate: this.selectedDate });
            }
            this.dispatchEvent(new ShowToastEvent({
                title: '削除しました',
                message: `${this.formatDate(this.selectedDate)}の習慣記録を削除しました。`,
                variant: 'success'
            }));
            this.isModalOpen = false;
            this.selectedHasLog = false;
            this.selectedLogId = undefined;
            await this.loadMonthlyLogs();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isDeleting = false;
        }
    }

    getHabitLabel(log) {
        if (!log?.habitValues?.length) {
            return '';
        }
        return log.habitValues.length === 1
            ? log.habitValues[0]
            : `${log.habitValues.length}件`;
    }

    normalizeLog(log) {
        return {
            ...log,
            recordId: this.getLogId(log),
            logDateKey: this.normalizeIsoDate(log.logDate),
            habitValues: log.habitValues || []
        };
    }

    getLogId(log) {
        return log?.recordId || log?.id || log?.Id;
    }

    normalizeIsoDate(value) {
        if (!value) {
            return '';
        }
        if (typeof value === 'string') {
            return value.slice(0, 10);
        }
        return this.toIsoDate(new Date(value));
    }

    toIsoDate(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        const [year, month, day] = value.split('-').map((part) => Number(part));
        return new Intl.DateTimeFormat('ja-JP', {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            weekday: 'short'
        }).format(new Date(year, month - 1, day));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || '処理中にエラーが発生しました。';
    }
}
