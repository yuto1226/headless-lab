/**
 * GetActiveGoalActionの利用者解決と進行中目標の優先順位を検証する。
 */
@isTest
private class GetActiveGoalActionTest {
    private static final String NO_TRAINEE_MESSAGE =
        '利用者情報が見つかりません。先にプロフィールを作成してください。';
    private static final String NO_ACTIVE_GOAL_MESSAGE =
        '現在進行中の目標はありません。新しい目標を設定しましょう。';

    @isTest
    static void shouldReturnFailureWhenCurrentUserHasNoTrainee() {
        GetActiveGoalAction.Request req = new GetActiveGoalAction.Request();

        Test.startTest();
        List<GetActiveGoalAction.Response> results = GetActiveGoalAction.execute(
            new List<GetActiveGoalAction.Request>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One response should be returned');
        Assert.isFalse(results[0].isSuccess, 'Missing trainee should fail');
        Assert.isFalse(results[0].hasActiveGoal, 'Missing trainee cannot have a goal');
        Assert.areEqual(NO_TRAINEE_MESSAGE, results[0].message, 'Guidance should be returned');
    }

    @isTest
    static void shouldReturnNoGoalWhenCurrentUserTraineeHasNoActiveGoal() {
        Trainee__c trainee = createTrainee(UserInfo.getUserId(), 'Current User');

        Test.startTest();
        List<GetActiveGoalAction.Response> results = GetActiveGoalAction.execute(
            new List<GetActiveGoalAction.Request>{ new GetActiveGoalAction.Request() }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess, 'A valid trainee lookup should succeed');
        Assert.isFalse(results[0].hasActiveGoal, 'No goal should be reported');
        Assert.areEqual(trainee.Id, results[0].traineeId, 'Current user trainee should be used');
        Assert.areEqual(NO_ACTIVE_GOAL_MESSAGE, results[0].message, 'Goal guidance should be returned');
    }

    @isTest
    static void shouldReturnGoalWhenTraineeIdHasActiveGoal() {
        Trainee__c trainee = createTrainee(UserInfo.getUserId(), 'Goal Trainee');
        TrainingGoal__c goal = createGoal(
            trainee.Id, 'Weekly Goal', '進行中',
            Date.today().addDays(-1), Date.today().addDays(7)
        );
        GetActiveGoalAction.Request req = requestFor(trainee.Id);

        Test.startTest();
        GetActiveGoalAction.Response result = GetActiveGoalAction.execute(
            new List<GetActiveGoalAction.Request>{ req }
        )[0];
        Test.stopTest();

        Assert.isTrue(result.isSuccess, 'Active goal lookup should succeed');
        Assert.isTrue(result.hasActiveGoal, 'Active goal should be reported');
        Assert.areEqual(trainee.Nickname__c, result.traineeName, 'Nickname should be returned');
        Assert.areEqual(goal.Id, result.goalId, 'Goal ID should match');
        Assert.areEqual(goal.Name, result.goalName, 'Goal name should match');
        Assert.areEqual(goal.GoalType__c, result.goalType, 'Goal type should match');
        Assert.areEqual(goal.StartDate__c, result.startDate, 'Start date should match');
        Assert.areEqual(goal.EndDate__c, result.endDate, 'End date should match');
        Assert.areEqual(goal.TargetValue__c, result.targetValue, 'Target value should match');
        Assert.areEqual(goal.Unit__c, result.unit, 'Unit should match');
        Assert.areEqual(goal.Status__c, result.status, 'Status should match');
        Assert.areEqual(goal.Notes__c, result.notes, 'Notes should match');
    }

    @isTest
    static void shouldPreferNearestEndDateWhenMultipleGoalsAreActive() {
        Trainee__c trainee = createTrainee(UserInfo.getUserId(), 'Priority Trainee');
        createGoal(trainee.Id, 'Later', '進行中', Date.today(), Date.today().addDays(14));
        TrainingGoal__c nearer = createGoal(
            trainee.Id, 'Nearer', '進行中', Date.today(), Date.today().addDays(3)
        );

        GetActiveGoalAction.Response result = executeFor(trainee.Id);

        Assert.areEqual(nearer.Id, result.goalId, 'Nearest end date should take priority');
    }

    @isTest
    static void shouldPreferNewestCreatedDateWhenEndDatesMatch() {
        Trainee__c trainee = createTrainee(UserInfo.getUserId(), 'Created Date Trainee');
        Date commonEndDate = Date.today().addDays(5);
        TrainingGoal__c older = createGoal(
            trainee.Id, 'Older', '進行中', Date.today(), commonEndDate
        );
        TrainingGoal__c newer = createGoal(
            trainee.Id, 'Newer', '進行中', Date.today(), commonEndDate
        );
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-2));
        Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));

        GetActiveGoalAction.Response result = executeFor(trainee.Id);

        Assert.areEqual(newer.Id, result.goalId, 'Newest goal should win when end dates match');
    }

    @isTest
    static void shouldExcludeNonActiveStatusesWhenGoalsAreInPeriod() {
        Trainee__c trainee = createTrainee(UserInfo.getUserId(), 'Status Trainee');
        for (String status : new List<String>{ '達成', '未達成', '中止' }) {
            createGoal(
                trainee.Id, status + ' Goal', status, Date.today().addDays(-1),
                Date.today().addDays(1)
            );
        }

        GetActiveGoalAction.Response result = executeFor(trainee.Id);

        Assert.isTrue(result.isSuccess, 'Lookup should succeed');
        Assert.isFalse(result.hasActiveGoal, 'Non-active statuses must be excluded');
        Assert.areEqual(null, result.goalId, 'No excluded goal should be returned');
    }

    @isTest
    static void shouldExcludeOutOfPeriodGoalsWhenStatusIsActive() {
        Trainee__c trainee = createTrainee(UserInfo.getUserId(), 'Period Trainee');
        createGoal(
            trainee.Id, 'Expired', '進行中', Date.today().addDays(-10),
            Date.today().addDays(-1)
        );
        createGoal(
            trainee.Id, 'Future', '進行中', Date.today().addDays(1),
            Date.today().addDays(10)
        );

        GetActiveGoalAction.Response result = executeFor(trainee.Id);

        Assert.isTrue(result.isSuccess, 'Lookup should succeed');
        Assert.isFalse(result.hasActiveGoal, 'Out-of-period goals must be excluded');
        Assert.areEqual(null, result.goalId, 'No out-of-period goal should be returned');
    }

    @isTest
    static void shouldRejectTraineeIdForAnotherSalesforceUser() {
        User otherUser = createUser('otheruser');
        Trainee__c trainee = createTrainee(otherUser.Id, 'Other User Trainee');
        createGoal(
            trainee.Id, 'Other User Goal', '進行中', Date.today().addDays(-1),
            Date.today().addDays(7)
        );

        GetActiveGoalAction.Response result = executeFor(trainee.Id);

        Assert.isFalse(result.isSuccess, 'Other user trainee lookup should fail');
        Assert.isFalse(result.hasActiveGoal, 'Other user goal must not be exposed');
        Assert.areEqual(null, result.goalId, 'Other user goal ID must not be returned');
        Assert.areEqual(NO_TRAINEE_MESSAGE, result.message, 'Safe guidance should be returned');
    }

    private static GetActiveGoalAction.Response executeFor(Id traineeId) {
        Test.startTest();
        GetActiveGoalAction.Response result = GetActiveGoalAction.execute(
            new List<GetActiveGoalAction.Request>{ requestFor(traineeId) }
        )[0];
        Test.stopTest();
        return result;
    }

    private static GetActiveGoalAction.Request requestFor(Id traineeId) {
        GetActiveGoalAction.Request req = new GetActiveGoalAction.Request();
        req.traineeId = traineeId;
        return req;
    }

    private static Trainee__c createTrainee(Id userId, String nickname) {
        return TestDataFactory.createTrainee(userId, nickname, null, null, true);
    }

    private static User createUser(String aliasPrefix) {
        String uniqueValue = String.valueOf(DateTime.now().getTime());
        User userRecord = new User(
            Alias = aliasPrefix.left(8),
            Email = aliasPrefix + uniqueValue + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Test',
            LanguageLocaleKey = 'ja',
            LocaleSidKey = 'ja_JP',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'Asia/Tokyo',
            UserName = aliasPrefix + uniqueValue + '@example.com'
        );
        insert userRecord;
        return userRecord;
    }

    private static TrainingGoal__c createGoal(
        Id traineeId,
        String name,
        String status,
        Date startDate,
        Date endDate
    ) {
        TrainingGoal__c goal = new TrainingGoal__c(
            Name = name,
            Trainee__c = traineeId,
            GoalType__c = '回数達成',
            StartDate__c = startDate,
            EndDate__c = endDate,
            TargetValue__c = 3,
            Unit__c = '回/週',
            Status__c = status,
            Notes__c = name + ' notes'
        );
        insert goal;
        return goal;
    }
}
