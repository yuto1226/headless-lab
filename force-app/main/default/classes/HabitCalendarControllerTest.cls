@isTest
private class HabitCalendarControllerTest {
    @TestSetup
    static void setupTestData() {
        TestDataFactory.createHabitLogs(251, '読書;筋トレ', true);
    }

    @isTest
    static void shouldReturnMonthlyLogsWhenLogsExist() {
        User habitUser = createHabitTrackerUser();
        List<HabitCalendarController.HabitLogRow> rows;
        Date today = Date.today();

        System.runAs(habitUser) {
            Test.startTest();
            rows = HabitCalendarController.getMonthlyLogs(today.year(), today.month());
            Test.stopTest();
        }

        Assert.isTrue(rows.size() > 0, 'Monthly rows should be returned.');
        Assert.isTrue(
            rows[0].habitValues.contains('読書'),
            'Habit values should include the selected multi-select value.'
        );
    }

    @isTest
    static void shouldCreateLogWhenValidInputProvided() {
        User habitUser = createHabitTrackerUser();
        Date targetDate = Date.today().addMonths(1).toStartOfMonth();
        HabitCalendarController.HabitLogRow row;

        System.runAs(habitUser) {
            Test.startTest();
            row = HabitCalendarController.saveLog(
                targetDate,
                new List<String>{ '筋トレ', 'Codexでの個人開発' },
                '集中して取り組めた'
            );
            Test.stopTest();
        }

        Assert.areEqual(targetDate, row.logDate, 'Saved row should include the target date.');
        Assert.isTrue(row.habitValues.contains('筋トレ'), 'Saved row should include strength training.');
        Assert.isTrue(row.habitValues.contains('Codexでの個人開発'), 'Saved row should include Codex habit.');
        Assert.areEqual('集中して取り組めた', row.memo, 'Saved row should include memo.');
    }

    @isTest
    static void shouldUpdateExistingLogWhenSameDateProvided() {
        User habitUser = createHabitTrackerUser();
        Date targetDate = Date.today().addMonths(2).toStartOfMonth();

        System.runAs(habitUser) {
            HabitCalendarController.saveLog(targetDate, new List<String>{ '読書' }, '初回');

            Test.startTest();
            HabitCalendarController.HabitLogRow row = HabitCalendarController.saveLog(
                targetDate,
                new List<String>{ 'Speakでの英語学習', '読書' },
                '更新後'
            );
            Test.stopTest();

            Assert.isTrue(
                row.habitValues.contains('Speakでの英語学習'),
                'Updated row should include the newly selected habit.'
            );
        }

        List<HabitLog__c> logs = [
            SELECT Id, Habits__c, Memo__c
            FROM HabitLog__c
            WHERE LogDate__c = :targetDate
        ];
        Assert.areEqual(1, logs.size(), 'Same date should update the existing log.');
        Assert.areEqual('更新後', logs[0].Memo__c, 'Same date should update memo.');
    }

    @isTest
    static void shouldDeleteLogWhenExistingLogProvided() {
        User habitUser = createHabitTrackerUser();
        Date targetDate = Date.today().addMonths(3).toStartOfMonth();
        Id logId;

        System.runAs(habitUser) {
            HabitCalendarController.HabitLogRow row = HabitCalendarController.saveLog(
                targetDate,
                new List<String>{ '筋トレ' },
                '削除対象'
            );
            logId = row.id;

            Test.startTest();
            HabitCalendarController.deleteLog(logId);
            Test.stopTest();
        }

        List<HabitLog__c> logs = [
            SELECT Id
            FROM HabitLog__c
            WHERE Id = :logId
        ];
        Assert.areEqual(0, logs.size(), 'Existing log should be deleted.');
    }

    @isTest
    static void shouldDeleteLogWhenExistingDateProvided() {
        User habitUser = createHabitTrackerUser();
        Date targetDate = Date.today().addMonths(4).toStartOfMonth();

        System.runAs(habitUser) {
            HabitCalendarController.saveLog(
                targetDate,
                new List<String>{ 'Speakでの英語学習' },
                '日付指定削除'
            );

            Test.startTest();
            HabitCalendarController.deleteLogByDate(targetDate);
            Test.stopTest();
        }

        List<HabitLog__c> logs = [
            SELECT Id
            FROM HabitLog__c
            WHERE LogDate__c = :targetDate
        ];
        Assert.areEqual(0, logs.size(), 'Existing log for the date should be deleted.');
    }

    @isTest
    static void shouldThrowExceptionWhenHabitsAreEmpty() {
        User habitUser = createHabitTrackerUser();

        System.runAs(habitUser) {
            Test.startTest();
            try {
                HabitCalendarController.saveLog(Date.today(), new List<String>(), null);
                Assert.fail('Expected AuraHandledException for missing habits.');
            } catch (AuraHandledException error) {
                Assert.isTrue(
                    error.getMessage().contains('必須'),
                    'Exception message should explain missing required input.'
                );
            }
            Test.stopTest();
        }
    }

    @isTest
    static void shouldThrowExceptionWhenDeleteIdIsMissing() {
        User habitUser = createHabitTrackerUser();

        System.runAs(habitUser) {
            Test.startTest();
            try {
                HabitCalendarController.deleteLog(null);
                Assert.fail('Expected AuraHandledException for missing log Id.');
            } catch (AuraHandledException error) {
                Assert.isTrue(
                    error.getMessage().contains('必須'),
                    'Exception message should explain missing required input.'
                );
            }
            Test.stopTest();
        }
    }

    @isTest
    static void shouldThrowExceptionWhenMonthIsInvalid() {
        User habitUser = createHabitTrackerUser();

        System.runAs(habitUser) {
            Test.startTest();
            try {
                HabitCalendarController.getMonthlyLogs(Date.today().year(), 13);
                Assert.fail('Expected AuraHandledException for invalid month.');
            } catch (AuraHandledException error) {
                Assert.isTrue(
                    error.getMessage().contains('必須'),
                    'Exception message should explain invalid request.'
                );
            }
            Test.stopTest();
        }
    }

    /** Creates a user with the Habit Tracker permission set assigned. */
    private static User createHabitTrackerUser() {
        String unique = String.valueOf(DateTime.now().getTime())
            + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User habitUser = new User(
            Alias = 'hbtusr',
            Email = 'habit.user.' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'HabitUser',
            LanguageLocaleKey = 'ja',
            LocaleSidKey = 'ja_JP',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'Asia/Tokyo',
            Username = 'habit.user.' + unique + '@example.com'
        );
        insert habitUser;

        PermissionSet habitPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Habit_Tracker_User'
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = habitUser.Id,
            PermissionSetId = habitPermissionSet.Id
        );
        return habitUser;
    }
}
