/**
 * Creates isolated test records used by Apex tests in this project.
 */
@SuppressWarnings('PMD.AvoidBooleanMethodParameters, PMD.ExcessiveParameterList')
@isTest
public class TestDataFactory {
    /**
     * Creates a trainee associated with the supplied Salesforce user.
     *
     * @param salesforceUserId user to associate with the trainee
     * @param nickname optional nickname
     * @param fitnessLevel optional fitness level
     * @param desiredWeeklyFrequency optional desired weekly frequency
     * @param doInsert whether to insert the record
     * @return the created trainee
     */
    public static Trainee__c createTrainee(
        Id salesforceUserId,
        String nickname,
        String fitnessLevel,
        Integer desiredWeeklyFrequency,
        Boolean doInsert
    ) {
        Trainee__c trainee = new Trainee__c(
            Name = String.isBlank(nickname) ? 'Test Trainee' : nickname,
            SalesforceUser__c = salesforceUserId,
            Nickname__c = nickname,
            FitnessLevel__c = fitnessLevel,
            StartDate__c = Date.today(),
            DesiredWeeklyFrequency__c = desiredWeeklyFrequency
        );
        if (doInsert) {
            insert trainee;
        }
        return trainee;
    }

    /**
     * Creates habit logs for calendar and controller tests.
     *
     * @param count number of logs to create
     * @param habits semicolon-delimited habits to assign
     * @param doInsert whether to insert the records
     * @return the created habit logs
     */
    public static List<HabitLog__c> createHabitLogs(
        Integer count,
        String habits,
        Boolean doInsert
    ) {
        List<HabitLog__c> logs = new List<HabitLog__c>();
        for (Integer index = 0; index < count; index++) {
            logs.add(new HabitLog__c(
                LogDate__c = Date.today().toStartOfMonth().addDays(Math.mod(index, 28)),
                Habits__c = String.isBlank(habits) ? '読書' : habits,
                Memo__c = 'Test memo ' + index
            ));
        }
        if (doInsert && !logs.isEmpty()) {
            insert logs;
        }
        return logs;
    }
}
