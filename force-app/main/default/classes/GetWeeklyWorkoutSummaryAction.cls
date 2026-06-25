/**
 * Agentforce action that summarizes a trainee's workout progress for one week.
 */
public with sharing class GetWeeklyWorkoutSummaryAction {
    private static final String ACTIVE_STATUS = '進行中';
    private static final String WEEKLY_COUNT_UNIT = '回/週';
    private static final String TRAINEE_NOT_FOUND_MESSAGE =
        '利用者情報が見つかりません。先にプロフィールを作成してください。';
    private static final String GOAL_MISMATCH_MESSAGE =
        '指定された目標は対象利用者に紐づいていません。目標を確認してください。';
    private static final String SYSTEM_ERROR_MESSAGE =
        '今週のトレーニング実績を集計できませんでした。管理者に権限設定を確認してください。';

    /**
     * 入力ごとに対象利用者・目標・週範囲を解決し、週次トレーニング実績を集計する。
     * traineeId省略時は現在ユーザーの利用者、goalId省略時は進行中目標、
     * weekStartDate省略時は今日を含む週の開始日を使用する。
     *
     * @param requests summary conditions supplied by Agentforce
     * @return weekly workout summary for each input request
     */
    @InvocableMethod(
        label='今週のトレーニング実績を集計'
        description='利用者の週単位トレーニング実績と進行中目標への進捗を集計します。'
        category='Agentforce'
    )
    public static List<Response> execute(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<Response>();
        }

        List<Response> responses = initializeResponses(requests.size());
        try {
            Map<Id, Trainee__c> traineesById = queryTrainees(requests);
            Trainee__c currentUserTrainee = getCurrentUserTrainee(traineesById);
            List<RequestContext> contexts = resolveContexts(
                requests,
                responses,
                traineesById,
                currentUserTrainee
            );

            Set<Id> traineeIds = collectResolvedTraineeIds(contexts);
            Map<Id, TrainingGoal__c> specifiedGoalsById = querySpecifiedGoals(requests);
            Map<Id, TrainingGoal__c> activeGoalsByTraineeId = queryActiveGoals(traineeIds);
            resolveGoals(contexts, specifiedGoalsById, activeGoalsByTraineeId);

            populateWorkoutSummaries(contexts);
        } catch (Exception error) {
            setExceptionResponses(responses, error);
        }
        return responses;
    }

    /** 入力件数と同じ数の空レスポンスを作成し、入力順で結果を返せるようにする。 */
    private static List<Response> initializeResponses(Integer responseCount) {
        List<Response> responses = new List<Response>();
        for (Integer index = 0; index < responseCount; index++) {
            responses.add(new Response());
        }
        return responses;
    }

    /** 明示指定された利用者と現在ユーザーに紐づく利用者をまとめて取得する。 */
    private static Map<Id, Trainee__c> queryTrainees(List<Request> requests) {
        Set<Id> requestedTraineeIds = new Set<Id>();
        for (Request req : requests) {
            if (req?.traineeId != null) {
                requestedTraineeIds.add(req.traineeId);
            }
        }

        Id currentUserId = UserInfo.getUserId();
        return new Map<Id, Trainee__c>([
            SELECT Id, Name, SalesforceUser__c, Nickname__c,
                TotalWorkoutCount__c, TotalWorkoutMinutes__c
            FROM Trainee__c
            WHERE Id IN :requestedTraineeIds
                OR SalesforceUser__c = :currentUserId
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
        ]);
    }

    /** 取得済み利用者の中から、現在ログイン中ユーザーに紐づく利用者を1件選ぶ。 */
    private static Trainee__c getCurrentUserTrainee(Map<Id, Trainee__c> traineesById) {
        Id currentUserId = UserInfo.getUserId();
        for (Trainee__c trainee : traineesById.values()) {
            if (trainee.SalesforceUser__c == currentUserId) {
                return trainee;
            }
        }
        return null;
    }

    /** 各入力に対して利用者と週範囲を確定し、後続処理用のコンテキストを作る。 */
    private static List<RequestContext> resolveContexts(
        List<Request> requests,
        List<Response> responses,
        Map<Id, Trainee__c> traineesById,
        Trainee__c currentUserTrainee
    ) {
        List<RequestContext> contexts = new List<RequestContext>();
        for (Integer index = 0; index < requests.size(); index++) {
            Request req = requests[index];
            Response res = responses[index];
            Trainee__c trainee = req?.traineeId == null
                ? currentUserTrainee
                : traineesById.get(req.traineeId);

            if (trainee == null) {
                setTraineeNotFoundResponse(res);
                continue;
            }

            Date startDate = req?.weekStartDate == null
                ? System.today().toStartOfWeek()
                : req.weekStartDate;
            RequestContext ctx = new RequestContext(req, res, trainee, startDate);
            setTraineeResponseFields(res, trainee, ctx.weekStartDate, ctx.weekEndDate);
            contexts.add(ctx);
        }
        return contexts;
    }

    /** 有効な入力から、実績・目標検索に使う利用者IDだけを集める。 */
    private static Set<Id> collectResolvedTraineeIds(List<RequestContext> contexts) {
        Set<Id> traineeIds = new Set<Id>();
        for (RequestContext ctx : contexts) {
            traineeIds.add(ctx.trainee.Id);
        }
        return traineeIds;
    }

    /** 入力で明示指定された目標を一括取得する。 */
    private static Map<Id, TrainingGoal__c> querySpecifiedGoals(List<Request> requests) {
        Set<Id> goalIds = new Set<Id>();
        for (Request req : requests) {
            if (req?.goalId != null) {
                goalIds.add(req.goalId);
            }
        }
        if (goalIds.isEmpty()) {
            return new Map<Id, TrainingGoal__c>();
        }

        return new Map<Id, TrainingGoal__c>([
            SELECT Id, Name, Trainee__c, GoalType__c, TargetValue__c, Unit__c
            FROM TrainingGoal__c
            WHERE Id IN :goalIds
            WITH USER_MODE
        ]);
    }

    /** 利用者ごとに、終了日が最も近い進行中目標を一括取得する。 */
    private static Map<Id, TrainingGoal__c> queryActiveGoals(Set<Id> traineeIds) {
        Map<Id, TrainingGoal__c> goalByTraineeId = new Map<Id, TrainingGoal__c>();
        if (traineeIds.isEmpty()) {
            return goalByTraineeId;
        }

        Date today = System.today();
        for (TrainingGoal__c goal : [
            SELECT Id, Name, Trainee__c, GoalType__c, TargetValue__c, Unit__c
            FROM TrainingGoal__c
            WHERE Trainee__c IN :traineeIds
                AND Status__c = :ACTIVE_STATUS
                AND StartDate__c <= :today
                AND EndDate__c >= :today
            WITH USER_MODE
            ORDER BY EndDate__c ASC, CreatedDate DESC, Id DESC
        ]) {
            if (!goalByTraineeId.containsKey(goal.Trainee__c)) {
                goalByTraineeId.put(goal.Trainee__c, goal);
            }
        }
        return goalByTraineeId;
    }

    /** 明示指定目標の所有者確認、または進行中目標の自動選択を行う。 */
    private static void resolveGoals(
        List<RequestContext> contexts,
        Map<Id, TrainingGoal__c> specifiedGoalsById,
        Map<Id, TrainingGoal__c> activeGoalsByTraineeId
    ) {
        for (RequestContext ctx : contexts) {
            if (ctx.req?.goalId != null) {
                TrainingGoal__c specifiedGoal = specifiedGoalsById.get(ctx.req.goalId);
                if (specifiedGoal == null || specifiedGoal.Trainee__c != ctx.trainee.Id) {
                    setGoalMismatchResponse(ctx.res);
                    ctx.isValid = false;
                    continue;
                }
                ctx.goal = specifiedGoal;
            } else {
                ctx.goal = activeGoalsByTraineeId.get(ctx.trainee.Id);
            }
            setGoalResponseFields(ctx.res, ctx.goal);
        }
    }

    /** 有効な入力ごとに実績件数・時間・目標進捗・返答メッセージを設定する。 */
    private static void populateWorkoutSummaries(List<RequestContext> contexts) {
        List<RequestContext> validContexts = getValidContexts(contexts);
        if (validContexts.isEmpty()) {
            return;
        }

        List<WorkoutSession__c> sessions = queryWorkoutSessions(validContexts);
        for (RequestContext ctx : validContexts) {
            Integer workoutCount = 0;
            Decimal totalDurationMinutes = 0;

            for (WorkoutSession__c session : sessions) {
                if (!matchesContext(session, ctx)) {
                    continue;
                }
                workoutCount++;
                totalDurationMinutes += session.DurationMinutes__c == null
                    ? 0
                    : session.DurationMinutes__c;
            }

            ctx.res.workoutCount = workoutCount;
            ctx.res.totalDurationMinutes = totalDurationMinutes;
            applyGoalProgress(ctx.res, ctx.goal, workoutCount);
            ctx.res.message = buildMessage(ctx.res);
            ctx.res.isSuccess = true;
        }
    }

    /** 利用者・目標の解決に成功し、集計対象として処理できる入力だけを抽出する。 */
    private static List<RequestContext> getValidContexts(List<RequestContext> contexts) {
        List<RequestContext> validContexts = new List<RequestContext>();
        for (RequestContext ctx : contexts) {
            if (ctx.isValid) {
                validContexts.add(ctx);
            }
        }
        return validContexts;
    }

    /** 全入力を包含する最小の週範囲でWorkoutSession__cを一括取得する。 */
    private static List<WorkoutSession__c> queryWorkoutSessions(
        List<RequestContext> contexts
    ) {
        Set<Id> traineeIds = new Set<Id>();
        DateTime earliestStart;
        DateTime latestEnd;
        for (RequestContext ctx : contexts) {
            traineeIds.add(ctx.trainee.Id);
            earliestStart = earliestStart == null || ctx.weekStartDateTime < earliestStart
                ? ctx.weekStartDateTime
                : earliestStart;
            latestEnd = latestEnd == null || ctx.nextWeekStartDateTime > latestEnd
                ? ctx.nextWeekStartDateTime
                : latestEnd;
        }

        return [
            SELECT Id, Trainee__c, TrainingGoal__c, WorkoutDateTime__c,
                DurationMinutes__c
            FROM WorkoutSession__c
            WHERE Trainee__c IN :traineeIds
                AND WorkoutDateTime__c >= :earliestStart
                AND WorkoutDateTime__c < :latestEnd
            WITH USER_MODE
        ];
    }

    /** 取得した実績が、指定コンテキストの利用者・週範囲・目標条件に合うか判定する。 */
    private static Boolean matchesContext(
        WorkoutSession__c session,
        RequestContext ctx
    ) {
        if (session.Trainee__c != ctx.trainee.Id) {
            return false;
        }
        if (
            session.WorkoutDateTime__c < ctx.weekStartDateTime ||
            session.WorkoutDateTime__c >= ctx.nextWeekStartDateTime
        ) {
            return false;
        }
        return ctx.goal == null || session.TrainingGoal__c == ctx.goal.Id;
    }

    /** 週回数目標の場合だけ、目標回数・残り回数・達成状況を計算する。 */
    private static void applyGoalProgress(
        Response res,
        TrainingGoal__c goal,
        Integer workoutCount
    ) {
        res.hasActiveGoal = goal != null;
        res.targetWorkoutCount = null;
        res.remainingCount = null;
        res.isGoalAchieved = false;

        if (goal == null || goal.Unit__c != WEEKLY_COUNT_UNIT) {
            return;
        }

        Integer targetCount = goal.TargetValue__c == null
            ? 0
            : goal.TargetValue__c.intValue();
        res.targetWorkoutCount = targetCount;
        res.remainingCount = Math.max(targetCount - workoutCount, 0);
        res.isGoalAchieved = workoutCount >= targetCount;
    }

    /** Agentforceがそのまま利用者へ返せる週次進捗メッセージを組み立てる。 */
    private static String buildMessage(Response res) {
        if (!res.hasActiveGoal) {
            return '今週は' + res.workoutCount + '回実施済みです。現在進行中の目標はありません。';
        }
        if (res.targetWorkoutCount == null) {
            return '今週は' + res.workoutCount + '回実施済みです。現在の目標は週回数以外の目標です。';
        }
        if (res.isGoalAchieved) {
            return '今週は' + res.workoutCount + '回実施済みです。週' +
                res.targetWorkoutCount + '回の目標を達成しています。';
        }
        return '今週は' + res.workoutCount + '回実施済みです。週' +
            res.targetWorkoutCount + '回の目標まであと' + res.remainingCount + '回です。';
    }

    /** 利用者情報、週範囲、全期間累計値をレスポンスに設定する。 */
    private static void setTraineeResponseFields(
        Response res,
        Trainee__c trainee,
        Date weekStartDate,
        Date weekEndDate
    ) {
        res.traineeId = trainee.Id;
        res.traineeName = trainee.Name;
        res.nickname = trainee.Nickname__c;
        res.weekStartDate = weekStartDate;
        res.weekEndDate = weekEndDate;
        res.totalWorkoutCount = trainee.TotalWorkoutCount__c;
        res.totalWorkoutMinutes = trainee.TotalWorkoutMinutes__c;
    }

    /** 目標がある場合に、目標の基本情報をレスポンスに設定する。 */
    private static void setGoalResponseFields(Response res, TrainingGoal__c goal) {
        res.hasActiveGoal = goal != null;
        if (goal == null) {
            return;
        }
        res.goalId = goal.Id;
        res.goalName = goal.Name;
        res.goalType = goal.GoalType__c;
    }

    /** 利用者を特定できない入力に、プロフィール作成を促す失敗レスポンスを設定する。 */
    private static void setTraineeNotFoundResponse(Response res) {
        res.isSuccess = false;
        res.hasActiveGoal = false;
        res.isGoalAchieved = false;
        res.message = TRAINEE_NOT_FOUND_MESSAGE;
    }

    /** 指定目標が対象利用者に紐づかない場合の失敗レスポンスを設定する。 */
    private static void setGoalMismatchResponse(Response res) {
        res.isSuccess = false;
        res.hasActiveGoal = false;
        res.isGoalAchieved = false;
        res.message = GOAL_MISMATCH_MESSAGE;
    }

    /** 想定外エラー時に、内部詳細を出さない共通失敗レスポンスを全件へ設定する。 */
    private static void setExceptionResponses(List<Response> responses, Exception error) {
        for (Response res : responses) {
            res.isSuccess = false;
            res.hasActiveGoal = false;
            res.isGoalAchieved = false;
            res.message = SYSTEM_ERROR_MESSAGE;
        }
    }

    private class RequestContext {
        private Request req;
        private Response res;
        private Trainee__c trainee;
        private TrainingGoal__c goal;
        private Date weekStartDate;
        private Date weekEndDate;
        private DateTime weekStartDateTime;
        private DateTime nextWeekStartDateTime;
        private Boolean isValid = true;

        /** 1入力分の処理状態と、その入力で使用する週開始・終了境界を保持する。 */
        private RequestContext(
            Request req,
            Response res,
            Trainee__c trainee,
            Date weekStartDate
        ) {
            this.req = req;
            this.res = res;
            this.trainee = trainee;
            this.weekStartDate = weekStartDate;
            this.weekEndDate = weekStartDate.addDays(6);
            this.weekStartDateTime = DateTime.newInstance(
                weekStartDate,
                Time.newInstance(0, 0, 0, 0)
            );
            this.nextWeekStartDateTime = DateTime.newInstance(
                weekStartDate.addDays(7),
                Time.newInstance(0, 0, 0, 0)
            );
        }
    }

    /** Input DTO for weekly workout summary conditions. */
    public class Request {
        @InvocableVariable(
            label='利用者ID'
            description='集計対象の利用者ID。省略時は現在のSalesforceユーザーに紐づく利用者を使用します。'
            required=false
        )
        public Id traineeId;

        @InvocableVariable(
            label='目標ID'
            description='集計対象の目標ID。省略時は対象利用者の進行中目標を自動取得します。'
            required=false
        )
        public Id goalId;

        @InvocableVariable(
            label='週開始日'
            description='集計する週の開始日。省略時は今日を含む週の開始日を使用します。'
            required=false
        )
        public Date weekStartDate;
    }

    /** Output DTO returned to Agentforce with weekly progress details. */
    public class Response {
        @InvocableVariable(label='利用者ID') public Id traineeId;
        @InvocableVariable(label='利用者名') public String traineeName;
        @InvocableVariable(label='ニックネーム') public String nickname;
        @InvocableVariable(label='目標ID') public Id goalId;
        @InvocableVariable(label='目標名') public String goalName;
        @InvocableVariable(label='目標種別') public String goalType;
        @InvocableVariable(label='週開始日') public Date weekStartDate;
        @InvocableVariable(label='週終了日') public Date weekEndDate;
        @InvocableVariable(label='今週の実施回数') public Integer workoutCount;
        @InvocableVariable(label='今週の合計時間（分）') public Decimal totalDurationMinutes;
        @InvocableVariable(label='週あたり目標回数') public Integer targetWorkoutCount;
        @InvocableVariable(label='残り回数') public Integer remainingCount;
        @InvocableVariable(label='目標達成済み') public Boolean isGoalAchieved;
        @InvocableVariable(label='進行中の目標あり') public Boolean hasActiveGoal;
        @InvocableVariable(label='全期間累計回数') public Decimal totalWorkoutCount;
        @InvocableVariable(label='全期間累計時間（分）') public Decimal totalWorkoutMinutes;
        @InvocableVariable(label='メッセージ') public String message;
        @InvocableVariable(label='成功') public Boolean isSuccess;
    }
}
