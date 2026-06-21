/**
 * Creates isolated test records used by Apex tests in this project.
 */
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
}
