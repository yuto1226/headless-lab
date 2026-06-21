/**
 * Agentforce action that gets or creates the trainee associated with the
 * currently authenticated Salesforce user.
 */
public with sharing class GetOrCreateTraineeAction {
    private static final Set<String> ALLOWED_FITNESS_LEVELS = new Set<String>{
        '初心者',
        '初級',
        '中級'
    };
    private static final Integer MIN_WEEKLY_FREQUENCY = 1;
    private static final Integer MAX_WEEKLY_FREQUENCY = 7;
    private static final Integer MAX_NICKNAME_LENGTH = 80;
    private static final String SAVE_ERROR_MESSAGE =
        '利用者情報を保存できませんでした。入力内容と実行ユーザーの権限を確認してください。';
    private static final String SYSTEM_ERROR_MESSAGE =
        '利用者情報を取得または保存できませんでした。管理者に権限設定を確認してください。';

    /**
     * Gets or creates the current user's trainee and fills only blank profile fields.
     * Every request in one invocation belongs to the same current user. When more
     * than one request is supplied, nonblank values are merged into that user's
     * single trainee and each valid request receives the same final profile.
     *
     * @param requests profile values collected by Agentforce
     * @return one result for each input request
     */
    @InvocableMethod(
        label='利用者の取得または作成'
        description='現在のSalesforceユーザーに紐づく利用者を取得し、存在しない場合は作成します。'
        category='Agentforce'
    )
    public static List<Response> execute(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<Response>();
        }

        // 入力順と同じ順序で返せるよう、先に全レスポンスの格納先を用意する。
        List<Response> responses = initializeResponses(requests.size());
        List<RequestContext> contexts = validateRequests(requests, responses);
        if (contexts.isEmpty()) {
            return responses;
        }

        try {
            Id userId = UserInfo.getUserId();
            // このアクションは、1トランザクションにつき現在ユーザーに紐づく
            // Trainee__c 1件だけを取得または作成し、その1件のみを処理する。
            List<Trainee__c> trainees = [
                SELECT Id, Name, SalesforceUser__c, Nickname__c, FitnessLevel__c,
                    StartDate__c, DesiredWeeklyFrequency__c
                FROM Trainee__c
                WHERE SalesforceUser__c = :userId
                WITH USER_MODE
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];

            // 未登録なら作成し、登録済みなら既存値を上書きせず空欄だけを補完する。
            Boolean isNew = trainees.isEmpty();
            Trainee__c trainee = isNew
                ? createTrainee(contexts, userId)
                : trainees[0];
            Boolean changed = applyMissingProfileValues(trainee, contexts);

            Database.SaveResult saveResult;
            // CRUD/FLSを実行ユーザー権限で強制し、変更がある場合だけDMLを行う。
            if (isNew) {
                saveResult = Database.insert(
                    new List<Trainee__c>{ trainee },
                    false,
                    AccessLevel.USER_MODE
                )[0];
            } else if (changed) {
                saveResult = Database.update(
                    new List<Trainee__c>{ trainee },
                    false,
                    AccessLevel.USER_MODE
                )[0];
            }

            if (saveResult != null && !saveResult.isSuccess()) {
                setSaveErrors(contexts, saveResult.getErrors());
                return responses;
            }

            setSuccessResponses(contexts, trainee, isNew);
        } catch (Exception error) {
            // Query/DML/権限エラーは内部情報を露出せず、全有効入力へ同じ案内を返す。
            setExceptionResponses(contexts, error);
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

    private static List<RequestContext> validateRequests(
        List<Request> requests,
        List<Response> responses
    ) {
        List<RequestContext> contexts = new List<RequestContext>();
        for (Integer index = 0; index < requests.size(); index++) {
            Request req = requests[index];
            Response res = responses[index];
            String validationMessage = getValidationMessage(req);
            if (validationMessage == null) {
                // DTO同士の参照を保持し、後続処理でリストのインデックス参照を不要にする。
                contexts.add(new RequestContext(req, res));
            } else {
                setErrorResponse(res, validationMessage, 'VALIDATION_ERROR');
            }
        }
        return contexts;
    }

    private static String getValidationMessage(Request req) {
        if (req == null) {
            return '入力情報を確認できません。必要なプロフィール情報をユーザーに問いかけてください。';
        }
        if (
            req.nickname != null &&
            req.nickname.length() > MAX_NICKNAME_LENGTH
        ) {
            return 'ニックネームは80文字以内である必要があります。80文字以内のニックネームをユーザーに問いかけてください。';
        }
        if (
            String.isNotBlank(req.fitnessLevel) &&
            !ALLOWED_FITNESS_LEVELS.contains(req.fitnessLevel)
        ) {
            return '運動レベルは「初心者」「初級」「中級」のいずれかのみ指定可能です。どのレベルが適切かユーザーに問いかけてください。';
        }
        if (
            req.desiredWeeklyFrequency != null &&
            (req.desiredWeeklyFrequency < MIN_WEEKLY_FREQUENCY ||
            req.desiredWeeklyFrequency > MAX_WEEKLY_FREQUENCY)
        ) {
            return '週あたり希望回数は1〜7の数値のみ指定可能です。希望回数をユーザーに問いかけてください。';
        }
        return null;
    }

    private static Trainee__c createTrainee(
        List<RequestContext> contexts,
        Id userId
    ) {
        String traineeName = UserInfo.getName();
        for (RequestContext ctx : contexts) {
            if (String.isNotBlank(ctx.req.nickname)) {
                traineeName = ctx.req.nickname;
                break;
            }
        }
        return new Trainee__c(
            Name = traineeName,
            SalesforceUser__c = userId,
            StartDate__c = System.today()
        );
    }

    private static Boolean applyMissingProfileValues(
        Trainee__c trainee,
        List<RequestContext> contexts
    ) {
        Boolean changed = false;
        for (RequestContext ctx : contexts) {
            Request req = ctx.req;
            if (String.isBlank(trainee.Nickname__c) && String.isNotBlank(req.nickname)) {
                trainee.Nickname__c = req.nickname;
                changed = true;
            }
            if (
                String.isBlank(trainee.FitnessLevel__c) &&
                String.isNotBlank(req.fitnessLevel)
            ) {
                trainee.FitnessLevel__c = req.fitnessLevel;
                changed = true;
            }
            if (
                trainee.DesiredWeeklyFrequency__c == null &&
                req.desiredWeeklyFrequency != null
            ) {
                trainee.DesiredWeeklyFrequency__c = req.desiredWeeklyFrequency;
                changed = true;
            }
        }
        return changed;
    }

    private static void setSuccessResponses(
        List<RequestContext> contexts,
        Trainee__c trainee,
        Boolean isNew
    ) {
        // 有効な各入力に、処理対象となった同じ利用者情報を返す。
        for (RequestContext ctx : contexts) {
            Response res = ctx.res;
            res.traineeId = trainee.Id;
            res.traineeName = trainee.Name;
            res.nickname = trainee.Nickname__c;
            res.fitnessLevel = trainee.FitnessLevel__c;
            res.desiredWeeklyFrequency = trainee.DesiredWeeklyFrequency__c == null
                ? null
                : trainee.DesiredWeeklyFrequency__c.intValue();
            res.isNewTrainee = isNew;
            res.needsProfileSetup = String.isBlank(trainee.FitnessLevel__c) ||
                trainee.DesiredWeeklyFrequency__c == null;
            res.message = isNew
                ? '利用者情報を新規作成しました。'
                : '既存の利用者情報を取得しました。';
            res.isSuccess = true;
        }
    }

    private static void setSaveErrors(
        List<RequestContext> contexts,
        Database.Error[] errors
    ) {
        for (RequestContext ctx : contexts) {
            setErrorResponse(ctx.res, SAVE_ERROR_MESSAGE, String.valueOf(errors[0].getStatusCode()));
        }
    }

    private static void setExceptionResponses(
        List<RequestContext> contexts,
        Exception error
    ) {
        for (RequestContext ctx : contexts) {
            setErrorResponse(
                ctx.res,
                SYSTEM_ERROR_MESSAGE,
                error.getTypeName()
            );
        }
    }

    private static void setErrorResponse(
        Response res,
        String message,
        String errorType
    ) {
        res.isSuccess = false;
        res.needsProfileSetup = true;
        res.message = message;
        res.errorMessage = message;
        res.errorType = errorType;
    }

    /** 入力DTOと出力DTOを対にして保持し、後続処理でのインデックス参照をなくす。 */
    private class RequestContext {
        private Request req;
        private Response res;

        private RequestContext(Request req, Response res) {
            this.req = req;
            this.res = res;
        }
    }

    /** Input profile values collected during the Agentforce conversation. */
    public class Request {
        @InvocableVariable(label='ニックネーム' description='利用者のニックネーム' required=false)
        public String nickname;

        @InvocableVariable(label='運動レベル' description='初心者、初級、中級のいずれか' required=false)
        public String fitnessLevel;

        @InvocableVariable(label='週あたり希望回数' description='1〜7の範囲の数値' required=false)
        public Integer desiredWeeklyFrequency;
    }

    /** Result returned to Agentforce for each input request. */
    public class Response {
        @InvocableVariable(label='利用者ID')
        public Id traineeId;

        @InvocableVariable(label='利用者名')
        public String traineeName;

        @InvocableVariable(label='ニックネーム')
        public String nickname;

        @InvocableVariable(label='運動レベル')
        public String fitnessLevel;

        @InvocableVariable(label='週あたり希望回数')
        public Integer desiredWeeklyFrequency;

        @InvocableVariable(label='新規利用者')
        public Boolean isNewTrainee;

        @InvocableVariable(label='プロフィール設定が必要')
        public Boolean needsProfileSetup;

        @InvocableVariable(label='メッセージ')
        public String message;

        @InvocableVariable(label='成功')
        public Boolean isSuccess;

        @InvocableVariable(label='エラーメッセージ')
        public String errorMessage;

        @InvocableVariable(label='エラー種別')
        public String errorType;
    }
}
