/**
 * 利用者の現在進行中のトレーニング目標を取得するAgentforceアクション。
 */
public with sharing class GetActiveGoalAction {
    private static final String ACTIVE_STATUS = '進行中';
    private static final String TRAINEE_NOT_FOUND_MESSAGE =
        '利用者情報が見つかりません。先にプロフィールを作成してください。';
    private static final String ACTIVE_GOAL_NOT_FOUND_MESSAGE =
        '現在進行中の目標はありません。新しい目標を設定しましょう。';
    private static final String SUCCESS_MESSAGE = '現在進行中の目標を取得しました。';
    private static final String SYSTEM_ERROR_MESSAGE =
        '目標情報を取得できませんでした。管理者に権限設定を確認してください。';

    /**
     * 各入力の利用者について、終了日が最も近い進行中の目標を取得する。
     * traineeIdが省略された場合は、現在のユーザーに紐づく利用者を使用する。
     *
     * @param requests Agentforceから受け取る利用者検索条件
     * @return 各入力に対応する検索結果
     */
    @InvocableMethod(
        label='進行中の目標を取得'
        description='利用者の現在進行中の目標を取得します。利用者ID省略時は現在のSalesforceユーザーを使用します。'
        category='Agentforce'
    )
    public static List<Response> execute(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<Response>();
        }

        List<Response> responses = initializeResponses(requests.size());
        try {
            Set<Id> requestedTraineeIds = collectTraineeIds(requests);
            Map<Id, Trainee__c> traineesById = new Map<Id, Trainee__c>();
            Trainee__c currentUserTrainee;
            Id currentUserId = UserInfo.getUserId();

            // 明示指定された利用者と現在のユーザーに紐づく利用者を1回のクエリで取得する。
            for (Trainee__c trainee : [
                SELECT Id, SalesforceUser__c, Nickname__c
                FROM Trainee__c
                WHERE Id IN :requestedTraineeIds
                    OR SalesforceUser__c = :currentUserId
                WITH USER_MODE
                ORDER BY CreatedDate ASC, Id ASC
            ]) {
                traineesById.put(trainee.Id, trainee);
                if (
                    currentUserTrainee == null &&
                    trainee.SalesforceUser__c == currentUserId
                ) {
                    currentUserTrainee = trainee;
                }
            }

            Set<Id> resolvedTraineeIds = new Set<Id>();
            List<Trainee__c> traineesByRequest = new List<Trainee__c>();
            for (Request req : requests) {
                Trainee__c trainee = resolveTraineeForRequest(
                    req,
                    currentUserTrainee,
                    traineesById,
                    currentUserId
                );
                traineesByRequest.add(trainee);
                if (trainee != null) {
                    resolvedTraineeIds.add(trainee.Id);
                }
            }

            Map<Id, TrainingGoal__c> activeGoalByTraineeId =
                getActiveGoals(resolvedTraineeIds);
            populateResponses(responses, traineesByRequest, activeGoalByTraineeId);
        } catch (Exception error) {
            setExceptionResponses(responses, error);
        }
        return responses;
    }

    private static List<Response> initializeResponses(Integer responseCount) {
        List<Response> responses = new List<Response>();
        for (Integer index = 0; index < responseCount; index++) {
            responses.add(new Response());
        }
        return responses;
    }

    private static Set<Id> collectTraineeIds(List<Request> requests) {
        Set<Id> traineeIds = new Set<Id>();
        for (Request req : requests) {
            if (req?.traineeId != null) {
                traineeIds.add(req.traineeId);
            }
        }
        return traineeIds;
    }

    private static Trainee__c resolveTraineeForRequest(
        Request req,
        Trainee__c currentUserTrainee,
        Map<Id, Trainee__c> traineesById,
        Id currentUserId
    ) {
        if (req?.traineeId == null) {
            return currentUserTrainee;
        }

        Trainee__c requestedTrainee = traineesById.get(req.traineeId);
        if (requestedTrainee?.SalesforceUser__c != currentUserId) {
            return null;
        }
        return requestedTrainee;
    }

    private static Map<Id, TrainingGoal__c> getActiveGoals(Set<Id> traineeIds) {
        Map<Id, TrainingGoal__c> goalByTraineeId = new Map<Id, TrainingGoal__c>();
        if (traineeIds.isEmpty()) {
            return goalByTraineeId;
        }

        Date today = System.today();
        // 指定された優先順位で並べ、利用者ごとの先頭レコードだけを採用する。
        for (TrainingGoal__c goal : [
            SELECT Id, Name, Trainee__c, GoalType__c, StartDate__c, EndDate__c,
                TargetValue__c, Unit__c, Status__c, Notes__c
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

    private static void populateResponses(
        List<Response> responses,
        List<Trainee__c> traineesByRequest,
        Map<Id, TrainingGoal__c> activeGoalByTraineeId
    ) {
        for (Integer index = 0; index < responses.size(); index++) {
            Response res = responses[index];
            Trainee__c trainee = traineesByRequest[index];
            if (trainee == null) {
                setTraineeNotFoundResponse(res);
                continue;
            }

            res.traineeId = trainee.Id;
            res.traineeName = trainee.Nickname__c;
            TrainingGoal__c goal = activeGoalByTraineeId.get(trainee.Id);
            if (goal == null) {
                res.isSuccess = true;
                res.hasActiveGoal = false;
                res.message = ACTIVE_GOAL_NOT_FOUND_MESSAGE;
                continue;
            }
            setActiveGoalResponse(res, goal);
        }
    }

    private static void setTraineeNotFoundResponse(Response res) {
        res.isSuccess = false;
        res.hasActiveGoal = false;
        res.message = TRAINEE_NOT_FOUND_MESSAGE;
        res.errorMessage = TRAINEE_NOT_FOUND_MESSAGE;
        res.errorType = 'NOT_FOUND';
    }

    private static void setActiveGoalResponse(Response res, TrainingGoal__c goal) {
        res.goalId = goal.Id;
        res.goalName = goal.Name;
        res.goalType = goal.GoalType__c;
        res.startDate = goal.StartDate__c;
        res.endDate = goal.EndDate__c;
        res.targetValue = goal.TargetValue__c;
        res.unit = goal.Unit__c;
        res.status = goal.Status__c;
        res.notes = goal.Notes__c;
        res.hasActiveGoal = true;
        res.message = SUCCESS_MESSAGE;
        res.isSuccess = true;
    }

    private static void setExceptionResponses(
        List<Response> responses,
        Exception error
    ) {
        for (Response res : responses) {
            res.isSuccess = false;
            res.hasActiveGoal = false;
            res.message = SYSTEM_ERROR_MESSAGE;
            res.errorMessage = SYSTEM_ERROR_MESSAGE;
            res.errorType = error.getTypeName();
        }
    }

    /** 利用者を選択する入力DTO。traineeId省略時は現在のユーザーを使用する。 */
    public class Request {
        @InvocableVariable(
            label='利用者ID'
            description='取得対象の利用者ID。省略時は現在のSalesforceユーザーに紐づく利用者を使用します。'
            required=false
        )
        public Id traineeId;
    }

    /** Agentforceへ返却する進行中目標の出力DTO。 */
    public class Response {
        @InvocableVariable(label='利用者ID') public Id traineeId;
        @InvocableVariable(label='利用者名') public String traineeName;
        @InvocableVariable(label='目標ID') public Id goalId;
        @InvocableVariable(label='目標名') public String goalName;
        @InvocableVariable(label='目標種別') public String goalType;
        @InvocableVariable(label='開始日') public Date startDate;
        @InvocableVariable(label='終了日') public Date endDate;
        @InvocableVariable(label='目標値') public Decimal targetValue;
        @InvocableVariable(label='単位') public String unit;
        @InvocableVariable(label='ステータス') public String status;
        @InvocableVariable(label='メモ') public String notes;
        @InvocableVariable(label='進行中の目標あり') public Boolean hasActiveGoal;
        @InvocableVariable(label='メッセージ') public String message;
        @InvocableVariable(label='成功') public Boolean isSuccess;
        @InvocableVariable(label='エラーメッセージ') public String errorMessage;
        @InvocableVariable(label='エラー種別') public String errorType;
    }
}
