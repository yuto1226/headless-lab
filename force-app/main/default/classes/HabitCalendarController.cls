/**
 * Provides month-based calendar data and save operations for the Habit Tracker LWC.
 */
@SuppressWarnings('PMD.CyclomaticComplexity')
public with sharing class HabitCalendarController {
    private static final Integer MIN_MONTH = 1;
    private static final Integer MAX_MONTH = 12;
    private static final String ERROR_REQUIRED_INPUT = '必須項目が不足しています。';

    /**
     * Returns habit logs for the requested calendar month.
     *
     * @param year four-digit calendar year
     * @param month calendar month from 1 to 12
     * @return habit log rows for the requested month
     */
    @AuraEnabled
    public static List<HabitLogRow> getMonthlyLogs(Integer year, Integer month) {
        Date monthStart = getMonthStart(year, month);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        List<HabitLogRow> rows = new List<HabitLogRow>();
        try {
            for (HabitLog__c logRecord : [
                SELECT Id, Name, LogDate__c, Habits__c, Memo__c
                FROM HabitLog__c
                WHERE LogDate__c >= :monthStart
                    AND LogDate__c <= :monthEnd
                WITH USER_MODE
                ORDER BY LogDate__c ASC, CreatedDate ASC, Id ASC
            ]) {
                rows.add(new HabitLogRow(logRecord));
            }
        } catch (Exception error) {
            throw createHandledException(Label.HabitTracker_Load_Error);
        }
        return rows;
    }

    /**
     * Creates or updates the one habit log record for the supplied date.
     *
     * @param logDate target calendar date
     * @param habits selected habit values
     * @param memo optional reflection memo
     * @return saved habit log row
     */
    @AuraEnabled
    public static HabitLogRow saveLog(Date logDate, List<String> habits, String memo) {
        String habitsValue = validateSaveInput(logDate, habits);

        try {
            HabitLog__c logRecord = findExistingLog(logDate);
            logRecord.LogDate__c = logDate;
            logRecord.Habits__c = habitsValue;
            logRecord.Memo__c = memo;
            saveRecord(logRecord);
            return new HabitLogRow(fetchSavedLog(logRecord.Id));
        } catch (AuraHandledException handledError) {
            throw handledError;
        } catch (Exception error) {
            throw createHandledException(Label.HabitTracker_Save_Error);
        }
    }

    /**
     * Deletes an existing habit log record.
     *
     * @param logId habit log record Id to delete
     */
    @AuraEnabled
    public static void deleteLog(Id logId) {
        if (logId == null) {
            throw createHandledException(Label.HabitTracker_Validation_Error);
        }

        try {
            HabitLog__c logRecord = [
                SELECT Id
                FROM HabitLog__c
                WHERE Id = :logId
                WITH USER_MODE
                LIMIT 1
            ];
            Database.delete(logRecord, AccessLevel.USER_MODE);
        } catch (AuraHandledException handledError) {
            throw handledError;
        } catch (Exception error) {
            throw createHandledException(Label.HabitTracker_Save_Error);
        }
    }

    /**
     * Deletes the habit log for the supplied date.
     *
     * @param logDate target calendar date
     */
    @AuraEnabled
    public static void deleteLogByDate(Date logDate) {
        if (logDate == null) {
            throw createHandledException(Label.HabitTracker_Validation_Error);
        }

        try {
            HabitLog__c logRecord = findExistingLog(logDate);
            if (logRecord.Id == null) {
                throw createHandledException(Label.HabitTracker_Validation_Error);
            }
            Database.delete(logRecord, AccessLevel.USER_MODE);
        } catch (AuraHandledException handledError) {
            throw handledError;
        } catch (Exception error) {
            throw createHandledException(Label.HabitTracker_Save_Error);
        }
    }

    /** Validates year and month inputs before constructing the month start date. */
    private static Date getMonthStart(Integer year, Integer month) {
        if (year == null || month == null || month < MIN_MONTH || month > MAX_MONTH) {
            throw createHandledException(Label.HabitTracker_Validation_Error);
        }
        return Date.newInstance(year, month, 1);
    }

    /** Validates save input and returns the stored multi-select picklist value. */
    private static String validateSaveInput(Date logDate, List<String> habits) {
        if (logDate == null || habits == null || habits.isEmpty()) {
            throw createHandledException(Label.HabitTracker_Validation_Error);
        }

        String habitsValue = joinHabits(habits);
        if (String.isBlank(habitsValue)) {
            throw createHandledException(Label.HabitTracker_Validation_Error);
        }
        return habitsValue;
    }

    /** Returns the earliest log for the selected date, or a new record when none exists. */
    private static HabitLog__c findExistingLog(Date logDate) {
        List<HabitLog__c> existingLogs = [
            SELECT Id, LogDate__c, Habits__c, Memo__c
            FROM HabitLog__c
            WHERE LogDate__c = :logDate
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 1
        ];
        return existingLogs.isEmpty() ? new HabitLog__c() : existingLogs[0];
    }

    /** Inserts or updates through user-mode DML so CRUD and FLS are enforced. */
    private static void saveRecord(HabitLog__c logRecord) {
        if (logRecord.Id == null) {
            Database.insert(logRecord, AccessLevel.USER_MODE);
            return;
        }
        Database.update(logRecord, AccessLevel.USER_MODE);
    }

    /** Re-queries the saved record with readable fields enforced for the response. */
    private static HabitLog__c fetchSavedLog(Id logRecordId) {
        return [
            SELECT Id, Name, LogDate__c, Habits__c, Memo__c
            FROM HabitLog__c
            WHERE Id = :logRecordId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    /** Converts selected habits to the semicolon-delimited format used by multi-select picklists. */
    private static String joinHabits(List<String> habits) {
        List<String> cleanHabits = new List<String>();
        for (String habit : habits) {
            if (!String.isBlank(habit)) {
                cleanHabits.add(habit.trim());
            }
        }
        return String.join(cleanHabits, ';');
    }

    /** Creates a sanitized exception for LWC callers. */
    private static AuraHandledException createHandledException(String message) {
        String safeMessage = String.isBlank(message) ? ERROR_REQUIRED_INPUT : message;
        AuraHandledException handledException = new AuraHandledException(safeMessage);
        handledException.setMessage(safeMessage);
        return handledException;
    }

    /**
     * Serializable habit log row for the LWC calendar.
     */
    public class HabitLogRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Id recordId { get; set; }
        @AuraEnabled public String recordName { get; set; }
        @AuraEnabled public Date logDate { get; set; }
        @AuraEnabled public String habits { get; set; }
        @AuraEnabled public List<String> habitValues { get; set; }
        @AuraEnabled public String memo { get; set; }

        /**
         * @param logRecord source habit log
         */
        public HabitLogRow(HabitLog__c logRecord) {
            this.id = logRecord.Id;
            this.recordId = logRecord.Id;
            this.recordName = logRecord.Name;
            this.logDate = logRecord.LogDate__c;
            this.habits = logRecord.Habits__c;
            this.habitValues = String.isBlank(logRecord.Habits__c)
                ? new List<String>()
                : logRecord.Habits__c.split(';');
            this.memo = logRecord.Memo__c;
        }
    }
}
