/**
 * Tests weekly workout summaries, active goal progress, and explicit goal filters.
 */
@isTest
private class GetWeeklyWorkoutSummaryActionTest {
    private static final String NO_TRAINEE_MESSAGE =
        '利用者情報が見つかりません。先にプロフィールを作成してください。';
    private static final String GOAL_MISMATCH_MESSAGE =
        '指定された目標は対象利用者に紐づいていません。目標を確認してください。';

    /** 現在ユーザーに紐づく利用者がない場合、失敗レスポンスを返すことを検証する。 */
    @isTest
    static void shouldReturnFailureWhenCurrentUserHasNoTrainee() {
        Test.startTest();
        GetWeeklyWorkoutSummaryAction.Response result = execute(
            new GetWeeklyWorkoutSummaryAction.Request()
        );
        Test.stopTest();

        Assert.isFalse(result.isSuccess, 'Missing trainee should fail');
        Assert.areEqual(NO_TRAINEE_MESSAGE, result.message, 'Profile setup guidance should be returned');
    }

    /** 利用者は存在するが今週の実績がない場合、回数と時間が0になることを検証する。 */
    @isTest
    static void shouldReturnZeroWhenNoWorkoutSessionsExistThisWeek() {
        Trainee__c trainee = createTrainee('No Workout');

        GetWeeklyWorkoutSummaryAction.Response result = executeForTrainee(trainee.Id);

        Assert.isTrue(result.isSuccess, 'Summary should succeed for an existing trainee');
        Assert.areEqual(0, result.workoutCount, 'No sessions should count as zero');
        Assert.areEqual(0, result.totalDurationMinutes, 'No duration should sum to zero');
        Assert.isFalse(result.hasActiveGoal, 'No active goal should be reported');
    }

    /** 今週の複数実績について、件数と所要時間合計が正しく集計されることを検証する。 */
    @isTest
    static void shouldSummarizeMultipleWorkoutSessionsInWeek() {
        Trainee__c trainee = createTrainee('Multiple Workouts');
        Date weekStart = Date.today().toStartOfWeek();
        createWorkout(trainee.Id, null, weekStart.addDays(1), 20);
        createWorkout(trainee.Id, null, weekStart.addDays(2), 35);

        GetWeeklyWorkoutSummaryAction.Response result = executeForTraineeAndWeek(
            trainee.Id,
            weekStart
        );

        Assert.areEqual(2, result.workoutCount, 'Two weekly sessions should be counted');
        Assert.areEqual(55, result.totalDurationMinutes, 'Durations should be summed');
    }

    /** 所要時間がnullの実績を0分として扱い、件数には含めることを検証する。 */
    @isTest
    static void shouldTreatNullDurationAsZero() {
        Trainee__c trainee = createTrainee('Null Duration');
        Date weekStart = Date.today().toStartOfWeek();
        createWorkout(trainee.Id, null, weekStart.addDays(1), null);
        createWorkout(trainee.Id, null, weekStart.addDays(2), 25);

        GetWeeklyWorkoutSummaryAction.Response result = executeForTraineeAndWeek(
            trainee.Id,
            weekStart
        );

        Assert.areEqual(2, result.workoutCount, 'Null duration sessions still count');
        Assert.areEqual(25, result.totalDurationMinutes, 'Null duration should contribute zero');
    }

    /** 週開始前と翌週開始以降の実績が集計対象外になることを検証する。 */
    @isTest
    static void shouldExcludeWorkoutSessionsOutsideWeekRange() {
        Trainee__c trainee = createTrainee('Range Trainee');
        Date weekStart = Date.today().toStartOfWeek();
        createWorkout(trainee.Id, null, weekStart.addDays(-1), 30);
        createWorkout(trainee.Id, null, weekStart, 15);
        createWorkout(trainee.Id, null, weekStart.addDays(6), 20);
        createWorkout(trainee.Id, null, weekStart.addDays(7), 40);

        GetWeeklyWorkoutSummaryAction.Response result = executeForTraineeAndWeek(
            trainee.Id,
            weekStart
        );

        Assert.areEqual(2, result.workoutCount, 'Only sessions from start through end of week count');
        Assert.areEqual(35, result.totalDurationMinutes, 'Only in-range durations should be summed');
    }

    /** 進行中の週回数目標がある場合、目標回数と残り回数を計算することを検証する。 */
    @isTest
    static void shouldCalculateRemainingCountWhenWeeklyGoalIsActive() {
        Trainee__c trainee = createTrainee('Goal Progress');
        TrainingGoal__c goal = createGoal(trainee.Id, 'Weekly Three', 3, '回/週');
        Date weekStart = Date.today().toStartOfWeek();
        createWorkout(trainee.Id, goal.Id, weekStart.addDays(1), 20);
        createWorkout(trainee.Id, goal.Id, weekStart.addDays(2), 20);

        GetWeeklyWorkoutSummaryAction.Response result = executeForTraineeAndWeek(
            trainee.Id,
            weekStart
        );

        Assert.isTrue(result.hasActiveGoal, 'Active goal should be reported');
        Assert.areEqual(goal.Id, result.goalId, 'Active goal should be selected');
        Assert.areEqual(3, result.targetWorkoutCount, 'Target workout count should come from the goal');
        Assert.areEqual(1, result.remainingCount, 'One workout should remain');
        Assert.isFalse(result.isGoalAchieved, 'Two of three workouts should not be achieved');
    }

    /** 今週の実績が目標回数に到達している場合、達成済みとして返すことを検証する。 */
    @isTest
    static void shouldReportAchievedWhenWeeklyGoalTargetIsMet() {
        Trainee__c trainee = createTrainee('Achieved Goal');
        TrainingGoal__c goal = createGoal(trainee.Id, 'Weekly Two', 2, '回/週');
        Date weekStart = Date.today().toStartOfWeek();
        createWorkout(trainee.Id, goal.Id, weekStart.addDays(1), 20);
        createWorkout(trainee.Id, goal.Id, weekStart.addDays(2), 25);

        GetWeeklyWorkoutSummaryAction.Response result = executeForTraineeAndWeek(
            trainee.Id,
            weekStart
        );

        Assert.areEqual(0, result.remainingCount, 'No workouts should remain after target is met');
        Assert.isTrue(result.isGoalAchieved, 'Target count should be achieved');
        Assert.isTrue(result.message.contains('達成しています'), 'Message should report achievement');
    }

    /** goalId指定時に、その目標に紐づく実績だけが集計されることを検証する。 */
    @isTest
    static void shouldFilterWorkoutSessionsWhenGoalIdIsSpecified() {
        Trainee__c trainee = createTrainee('Goal Filter');
        TrainingGoal__c selectedGoal = createGoal(trainee.Id, 'Selected Goal', 4, '回/週');
        TrainingGoal__c otherGoal = createGoal(trainee.Id, 'Other Goal', 4, '回/週');
        Date weekStart = Date.today().toStartOfWeek();
        createWorkout(trainee.Id, selectedGoal.Id, weekStart.addDays(1), 10);
        createWorkout(trainee.Id, selectedGoal.Id, weekStart.addDays(2), 15);
        createWorkout(trainee.Id, otherGoal.Id, weekStart.addDays(3), 30);
        createWorkout(trainee.Id, null, weekStart.addDays(4), 45);

        GetWeeklyWorkoutSummaryAction.Request req = requestFor(trainee.Id, weekStart);
        req.goalId = selectedGoal.Id;

        GetWeeklyWorkoutSummaryAction.Response result = execute(req);

        Assert.areEqual(selectedGoal.Id, result.goalId, 'Specified goal should be returned');
        Assert.areEqual(2, result.workoutCount, 'Only selected goal sessions should be counted');
        Assert.areEqual(25, result.totalDurationMinutes, 'Only selected goal durations should be summed');
    }

    /** 指定goalIdが別利用者の目標の場合、情報を集計せず失敗にすることを検証する。 */
    @isTest
    static void shouldFailWhenGoalIdBelongsToAnotherTrainee() {
        Trainee__c trainee = createTrainee('Owner Trainee');
        Trainee__c otherTrainee = TestDataFactory.createTrainee(
            null,
            'Other Trainee',
            null,
            null,
            true
        );
        TrainingGoal__c otherGoal = createGoal(otherTrainee.Id, 'Other Goal', 3, '回/週');
        GetWeeklyWorkoutSummaryAction.Request req = requestFor(
            trainee.Id,
            Date.today().toStartOfWeek()
        );
        req.goalId = otherGoal.Id;

        GetWeeklyWorkoutSummaryAction.Response result = execute(req);

        Assert.isFalse(result.isSuccess, 'Mismatched goal should fail');
        Assert.areEqual(GOAL_MISMATCH_MESSAGE, result.message, 'Safe mismatch guidance should be returned');
    }

    /** 進行中目標がない場合でも、利用者の今週分実績は集計されることを検証する。 */
    @isTest
    static void shouldSummarizeWeekWhenNoActiveGoalExists() {
        Trainee__c trainee = createTrainee('No Active Goal');
        createGoal(
            trainee.Id,
            'Expired Goal',
            3,
            '回/週',
            Date.today().addDays(-10),
            Date.today().addDays(-1),
            '進行中'
        );
        Date weekStart = Date.today().toStartOfWeek();
        createWorkout(trainee.Id, null, weekStart.addDays(1), 30);

        GetWeeklyWorkoutSummaryAction.Response result = executeForTraineeAndWeek(
            trainee.Id,
            weekStart
        );

        Assert.isTrue(result.isSuccess, 'Summary should still succeed without an active goal');
        Assert.isFalse(result.hasActiveGoal, 'No active goal should be reported');
        Assert.areEqual(1, result.workoutCount, 'Weekly workouts should still be summarized');
        Assert.areEqual(null, result.targetWorkoutCount, 'No target should be returned');
    }

    /** 全期間累計値は返却しつつ、週次進捗判定には使用しないことを検証する。 */
    @isTest
    static void shouldReturnLifetimeRollupValuesWithoutUsingThemForWeeklyProgress() {
        Trainee__c trainee = createTrainee('Rollup Trainee');
        TrainingGoal__c goal = createGoal(trainee.Id, 'Weekly Two', 2, '回/週');
        Date weekStart = Date.today().toStartOfWeek();
        createWorkout(trainee.Id, goal.Id, weekStart.addDays(1), 20);
        createWorkout(trainee.Id, goal.Id, weekStart.addDays(-8), 45);

        Test.startTest();
        GetWeeklyWorkoutSummaryAction.Response result = execute(
            requestFor(trainee.Id, weekStart)
        );
        Test.stopTest();

        Assert.areEqual(1, result.workoutCount, 'Only this week should drive weekly progress');
        Assert.areEqual(1, result.remainingCount, 'Out-of-week rollup records must not satisfy the goal');
        Assert.isFalse(result.isGoalAchieved, 'Lifetime totals must not drive weekly achievement');
        Assert.areEqual(2, result.totalWorkoutCount, 'Lifetime workout count should be returned');
        Assert.areEqual(65, result.totalWorkoutMinutes, 'Lifetime workout minutes should be returned');
    }

    /** 利用者IDを指定して、今日を含む週の集計を実行する。 */
    private static GetWeeklyWorkoutSummaryAction.Response executeForTrainee(Id traineeId) {
        return executeForTraineeAndWeek(traineeId, Date.today().toStartOfWeek());
    }

    /** 利用者IDと週開始日を指定して、startTest/stopTest付きで集計を実行する。 */
    private static GetWeeklyWorkoutSummaryAction.Response executeForTraineeAndWeek(
        Id traineeId,
        Date weekStart
    ) {
        Test.startTest();
        GetWeeklyWorkoutSummaryAction.Response result = execute(requestFor(traineeId, weekStart));
        Test.stopTest();
        return result;
    }

    /** 1件の入力DTOをActionへ渡し、対応する1件目のレスポンスを返す。 */
    private static GetWeeklyWorkoutSummaryAction.Response execute(
        GetWeeklyWorkoutSummaryAction.Request req
    ) {
        return GetWeeklyWorkoutSummaryAction.execute(
            new List<GetWeeklyWorkoutSummaryAction.Request>{ req }
        )[0];
    }

    /** 利用者IDと週開始日を持つ標準入力DTOを作成する。 */
    private static GetWeeklyWorkoutSummaryAction.Request requestFor(
        Id traineeId,
        Date weekStart
    ) {
        GetWeeklyWorkoutSummaryAction.Request req = new GetWeeklyWorkoutSummaryAction.Request();
        req.traineeId = traineeId;
        req.weekStartDate = weekStart;
        return req;
    }

    /** 現在ユーザーに紐づく利用者テストデータを作成する。 */
    private static Trainee__c createTrainee(String nickname) {
        return TestDataFactory.createTrainee(UserInfo.getUserId(), nickname, null, null, true);
    }

    /** 今日時点で進行中の目標テストデータを作成する。 */
    private static TrainingGoal__c createGoal(
        Id traineeId,
        String name,
        Integer targetValue,
        String unit
    ) {
        return createGoal(
            traineeId,
            name,
            targetValue,
            unit,
            Date.today().addDays(-1),
            Date.today().addDays(7),
            '進行中'
        );
    }

    /** 期間とステータスを指定して目標テストデータを作成する。 */
    private static TrainingGoal__c createGoal(
        Id traineeId,
        String name,
        Integer targetValue,
        String unit,
        Date startDate,
        Date endDate,
        String status
    ) {
        TrainingGoal__c goal = new TrainingGoal__c(
            Name = name,
            Trainee__c = traineeId,
            GoalType__c = '回数達成',
            StartDate__c = startDate,
            EndDate__c = endDate,
            TargetValue__c = targetValue,
            Unit__c = unit,
            Status__c = status
        );
        insert goal;
        return goal;
    }

    /** 指定した日付・目標・所要時間でトレーニング実績テストデータを作成する。 */
    private static WorkoutSession__c createWorkout(
        Id traineeId,
        Id goalId,
        Date workoutDate,
        Integer durationMinutes
    ) {
        WorkoutSession__c session = new WorkoutSession__c(
            Trainee__c = traineeId,
            TrainingGoal__c = goalId,
            WorkoutDateTime__c = DateTime.newInstance(
                workoutDate,
                Time.newInstance(9, 0, 0, 0)
            ),
            DurationMinutes__c = durationMinutes
        );
        insert session;
        return session;
    }
}
