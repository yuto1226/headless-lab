/**
 * Tests profile creation, retrieval, completion, validation, and bulk input for
 * GetOrCreateTraineeAction.
 */
@isTest
private class GetOrCreateTraineeActionTest {
    private static final String NICKNAME = 'トレーニー';
    private static final String ORIGINAL_NICKNAME = '既存ニックネーム';
    private static final String FITNESS_BEGINNER = '初心者';
    private static final String FITNESS_INTERMEDIATE = '中級';
    private static final Integer WEEKLY_FREQUENCY = 3;

    @isTest
    static void shouldCreateIncompleteTrainee_WhenNoProfileInputProvided() {
        GetOrCreateTraineeAction.Request requestValue = createRequest(null, null, null);

        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(
            new List<GetOrCreateTraineeAction.Request>{ requestValue }
        );
        Test.stopTest();

        Trainee__c trainee = getCurrentUserTrainee();
        Assert.areEqual(1, responses.size(), 'The action should return one response');
        Assert.isTrue(responses[0].isSuccess, 'Creation should succeed');
        Assert.isTrue(responses[0].isNewTrainee, 'The trainee should be reported as new');
        Assert.isNull(trainee.FitnessLevel__c, 'Fitness level should remain blank');
        Assert.isNull(
            trainee.DesiredWeeklyFrequency__c,
            'Desired weekly frequency should remain blank'
        );
        Assert.isTrue(
            responses[0].needsProfileSetup,
            'An incomplete profile should require setup'
        );
        Assert.areEqual(Date.today(), trainee.StartDate__c, 'Start date should be today');
        Assert.areEqual(
            UserInfo.getName(),
            trainee.Name,
            'The current user name should be used when nickname is absent'
        );
    }

    @isTest
    static void shouldCreateCompleteTrainee_WhenProfileInputProvided() {
        GetOrCreateTraineeAction.Request requestValue = createRequest(
            NICKNAME,
            FITNESS_BEGINNER,
            WEEKLY_FREQUENCY
        );

        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(
            new List<GetOrCreateTraineeAction.Request>{ requestValue }
        );
        Test.stopTest();

        Trainee__c trainee = getCurrentUserTrainee();
        Assert.areEqual(NICKNAME, trainee.Name, 'Nickname should be used as the trainee name');
        Assert.areEqual(NICKNAME, trainee.Nickname__c, 'Nickname should be saved');
        Assert.areEqual(FITNESS_BEGINNER, trainee.FitnessLevel__c, 'Fitness level should be saved');
        Assert.areEqual(
            Decimal.valueOf(WEEKLY_FREQUENCY),
            trainee.DesiredWeeklyFrequency__c,
            'Desired weekly frequency should be saved'
        );
        Assert.isFalse(
            responses[0].needsProfileSetup,
            'A complete profile should not require setup'
        );
        Assert.areEqual(trainee.Id, responses[0].traineeId, 'Response should contain the trainee Id');
    }

    @isTest
    static void shouldReturnExistingTrainee_WhenTraineeExists() {
        Trainee__c existingTrainee = TestDataFactory.createTrainee(
            UserInfo.getUserId(),
            ORIGINAL_NICKNAME,
            FITNESS_BEGINNER,
            WEEKLY_FREQUENCY,
            true
        );

        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(
            new List<GetOrCreateTraineeAction.Request>{ createRequest(null, null, null) }
        );
        Test.stopTest();

        Assert.areEqual(existingTrainee.Id, responses[0].traineeId, 'Existing trainee should be returned');
        Assert.isFalse(responses[0].isNewTrainee, 'Existing trainee should not be reported as new');
        Assert.isTrue(responses[0].isSuccess, 'Retrieval should succeed');
        Assert.areEqual(
            ORIGINAL_NICKNAME,
            responses[0].nickname,
            'Response should include the existing nickname'
        );
    }

    @isTest
    static void shouldFillOnlyMissingFields_WhenExistingProfileIsIncomplete() {
        TestDataFactory.createTrainee(
            UserInfo.getUserId(),
            ORIGINAL_NICKNAME,
            null,
            null,
            true
        );

        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(
            new List<GetOrCreateTraineeAction.Request>{
                createRequest(NICKNAME, FITNESS_INTERMEDIATE, WEEKLY_FREQUENCY)
            }
        );
        Test.stopTest();

        Trainee__c trainee = getCurrentUserTrainee();
        Assert.areEqual(
            ORIGINAL_NICKNAME,
            trainee.Nickname__c,
            'Existing nickname should not be overwritten'
        );
        Assert.areEqual(
            FITNESS_INTERMEDIATE,
            trainee.FitnessLevel__c,
            'Missing fitness level should be filled'
        );
        Assert.areEqual(
            Decimal.valueOf(WEEKLY_FREQUENCY),
            trainee.DesiredWeeklyFrequency__c,
            'Missing desired weekly frequency should be filled'
        );
        Assert.isFalse(responses[0].needsProfileSetup, 'Completed profile should not require setup');
    }

    @isTest
    static void shouldPreserveExistingFields_WhenInputContainsDifferentValues() {
        Integer originalFrequency = 5;
        TestDataFactory.createTrainee(
            UserInfo.getUserId(),
            ORIGINAL_NICKNAME,
            FITNESS_BEGINNER,
            originalFrequency,
            true
        );

        Test.startTest();
        GetOrCreateTraineeAction.execute(
            new List<GetOrCreateTraineeAction.Request>{
                createRequest(NICKNAME, FITNESS_INTERMEDIATE, WEEKLY_FREQUENCY)
            }
        );
        Test.stopTest();

        Trainee__c trainee = getCurrentUserTrainee();
        Assert.areEqual(ORIGINAL_NICKNAME, trainee.Nickname__c, 'Nickname should not be overwritten');
        Assert.areEqual(FITNESS_BEGINNER, trainee.FitnessLevel__c, 'Fitness level should not be overwritten');
        Assert.areEqual(
            Decimal.valueOf(originalFrequency),
            trainee.DesiredWeeklyFrequency__c,
            'Desired weekly frequency should not be overwritten'
        );
    }

    @isTest
    static void shouldReturnValidationError_WhenFitnessLevelIsInvalid() {
        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(
            new List<GetOrCreateTraineeAction.Request>{ createRequest(null, '上級', null) }
        );
        Test.stopTest();

        Assert.isFalse(responses[0].isSuccess, 'Invalid fitness level should fail validation');
        Assert.isTrue(
            responses[0].message.contains('初心者') && responses[0].message.contains('問いかけ'),
            'Message should provide allowed values and direct Agentforce to ask the user'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Trainee__c WHERE SalesforceUser__c = :UserInfo.getUserId()],
            'Invalid input should not create a trainee'
        );
    }

    @isTest
    static void shouldReturnValidationError_WhenWeeklyFrequencyIsOutsideRange() {
        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(
            new List<GetOrCreateTraineeAction.Request>{ createRequest(null, null, 8) }
        );
        Test.stopTest();

        Assert.isFalse(responses[0].isSuccess, 'Out-of-range frequency should fail validation');
        Assert.isTrue(
            responses[0].message.contains('1〜7') && responses[0].message.contains('問いかけ'),
            'Message should provide the valid range and direct Agentforce to ask the user'
        );
        Assert.areEqual('VALIDATION_ERROR', responses[0].errorType, 'Error type should identify validation');
    }

    @isTest
    static void shouldProcessValidRequests_WhenBulkInputContainsInvalidRequest() {
        List<GetOrCreateTraineeAction.Request> requests = new List<GetOrCreateTraineeAction.Request>();
        requests.add(createRequest(NICKNAME, FITNESS_BEGINNER, WEEKLY_FREQUENCY));
        requests.add(createRequest(null, '上級', null));
        for (Integer index = 2; index < 251; index++) {
            requests.add(createRequest(null, null, null));
        }

        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(requests);
        Test.stopTest();

        Assert.areEqual(251, responses.size(), 'Every bulk input should receive a response');
        Assert.isTrue(responses[0].isSuccess, 'Valid input should succeed');
        Assert.isFalse(responses[1].isSuccess, 'Invalid input should fail independently');
        Assert.isTrue(responses[250].isSuccess, 'Later valid inputs should also succeed');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Trainee__c WHERE SalesforceUser__c = :UserInfo.getUserId()],
            'Bulk input should create only one trainee for the current user'
        );
    }

    @isTest
    static void shouldReturnEmptyResponses_WhenRequestsAreNull() {
        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(null);
        Test.stopTest();

        Assert.isTrue(responses.isEmpty(), 'Null request collection should return no responses');
    }

    @isTest
    static void shouldReturnEmptyResponses_WhenRequestsAreEmpty() {
        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(
            new List<GetOrCreateTraineeAction.Request>()
        );
        Test.stopTest();

        Assert.isTrue(responses.isEmpty(), 'Empty request collection should return no responses');
    }

    @isTest
    static void shouldReturnValidationError_WhenRequestDtoIsNull() {
        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(
            new List<GetOrCreateTraineeAction.Request>{ null }
        );
        Test.stopTest();

        Assert.isFalse(responses[0].isSuccess, 'Null request DTO should fail validation');
        Assert.areEqual('VALIDATION_ERROR', responses[0].errorType, 'Error type should identify validation');
        Assert.isTrue(
            responses[0].message.contains('問いかけ'),
            'Message should direct Agentforce to ask for the missing profile input'
        );
    }

    @isTest
    static void shouldReturnValidationError_WhenNicknameExceedsFieldLength() {
        String longNickname = '12345678901234567890123456789012345678901234567890' +
            '1234567890123456789012345678901';

        Test.startTest();
        List<GetOrCreateTraineeAction.Response> responses = GetOrCreateTraineeAction.execute(
            new List<GetOrCreateTraineeAction.Request>{ createRequest(longNickname, null, null) }
        );
        Test.stopTest();

        Assert.isFalse(responses[0].isSuccess, 'A value exceeding field length should fail validation');
        Assert.isTrue(
            responses[0].message.contains('80文字以内') && responses[0].message.contains('問いかけ'),
            'Message should provide the limit and direct Agentforce to ask the user'
        );
        Assert.areEqual('VALIDATION_ERROR', responses[0].errorType, 'Error type should identify validation');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Trainee__c WHERE SalesforceUser__c = :UserInfo.getUserId()],
            'Failed DML should not create a trainee'
        );
    }

    private static GetOrCreateTraineeAction.Request createRequest(
        String nickname,
        String fitnessLevel,
        Integer desiredWeeklyFrequency
    ) {
        GetOrCreateTraineeAction.Request requestValue = new GetOrCreateTraineeAction.Request();
        requestValue.nickname = nickname;
        requestValue.fitnessLevel = fitnessLevel;
        requestValue.desiredWeeklyFrequency = desiredWeeklyFrequency;
        return requestValue;
    }

    private static Trainee__c getCurrentUserTrainee() {
        return [
            SELECT Id, Name, SalesforceUser__c, Nickname__c, FitnessLevel__c,
                StartDate__c, DesiredWeeklyFrequency__c
            FROM Trainee__c
            WHERE SalesforceUser__c = :UserInfo.getUserId()
            LIMIT 1
        ];
    }
}
