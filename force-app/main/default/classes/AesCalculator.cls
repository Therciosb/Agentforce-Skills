/**
 * @description Utility class for the Agent Effectiveness Score (AES).
 *
 *              AES is a CUMULATIVE score: it is the running total, across all of an
 *              agent's sessions in chronological order, of each session's lesson-
 *              application contribution. The more an agent is used and successfully
 *              applies lessons, the higher its AES climbs — proving that the agent
 *              learns and becomes more effective over time, and giving a single
 *              number that is directly comparable across agents.
 *
 *              Per-session lesson-application contribution (the only driver):
 *              - lesson applied & successful   -> +15
 *              - lesson applied & unsuccessful -> +5
 *              - no lesson applied             ->  0
 *
 *              `calculateAes` still produces the per-session Goal/Efficiency/Learning
 *              sub-scores used by the console's AES Breakdown widget and per-session
 *              detail; those are informational and do NOT drive the cumulative headline.
 */
public class AesCalculator {

    // Per-session lesson-application increments (the cumulative AES driver).
    public static final Decimal APPLY_SUCCESS_POINTS = 15;
    public static final Decimal APPLY_FAILURE_POINTS = 5;

    /**
     * @description The learning contribution a single session adds to the cumulative AES,
     *              based solely on whether a lesson was applied and whether it succeeded.
     * @param lessonApplied Whether at least one lesson was applied in the session
     * @param lessonSuccessful Whether the session succeeded after applying the lesson
     * @return 15 (applied + successful), 5 (applied + unsuccessful), or 0 (no lesson applied)
     */
    public static Decimal sessionLessonContribution(Boolean lessonApplied, Boolean lessonSuccessful) {
        if (lessonApplied != true) {
            return 0;
        }
        return (lessonSuccessful == true) ? APPLY_SUCCESS_POINTS : APPLY_FAILURE_POINTS;
    }

    /**
     * @description Calculates the AES score and its component parts.
     * @param finalOutcome 'success', 'partial', or 'failure'
     * @param actionsTaken Number of actions the session took
     * @param optimalActions Configured optimal action count (defaults to 3)
     * @param lessonApplied Whether a lesson was referenced during session
     * @param lessonSuccessful Whether the session succeeded after applying lesson
     * @param lessonCreated Whether the agent documented a new lesson
     * @return Map with keys: aes_score, aes_goal, aes_efficiency, aes_learning
     */
    public static Map<String, Decimal> calculateAes(
        String finalOutcome,
        Integer actionsTaken,
        Integer optimalActions,
        Boolean lessonApplied,
        Boolean lessonSuccessful,
        Boolean lessonCreated
    ) {
        // Handle null defaults
        if (optimalActions == null || optimalActions <= 0) {
            optimalActions = 3;
        }
        if (lessonApplied == null) {
            lessonApplied = false;
        }
        if (lessonSuccessful == null) {
            lessonSuccessful = false;
        }
        if (lessonCreated == null) {
            lessonCreated = false;
        }
        if (finalOutcome == null) {
            finalOutcome = 'failure';
        }
        finalOutcome = finalOutcome.toLowerCase();

        // Goal component (0-40)
        Decimal goalScore;
        if (finalOutcome == 'success') {
            goalScore = 40;
        } else if (finalOutcome == 'partial') {
            goalScore = 20;
        } else {
            goalScore = 0;
        }

        // Efficiency component (0-30)
        Decimal efficiencyScore;
        if (actionsTaken == null || actionsTaken <= optimalActions) {
            efficiencyScore = 30;
        } else {
            Decimal penalty = Math.min(1.0, (Decimal)(actionsTaken - optimalActions) / optimalActions);
            efficiencyScore = 30 * (1 - penalty);
        }

        // Learning component (0-30, capped)
        Decimal learningScore = 0;
        if (lessonApplied && lessonSuccessful) {
            learningScore += 15;
        } else if (lessonApplied && !lessonSuccessful) {
            learningScore += 5;
        }
        if (lessonCreated) {
            learningScore += 10;
        }
        learningScore = Math.min(30, learningScore);

        // Total AES
        Decimal aesScore = goalScore + efficiencyScore + learningScore;

        Map<String, Decimal> result = new Map<String, Decimal>();
        result.put('aes_score', aesScore);
        result.put('aes_goal', goalScore);
        result.put('aes_efficiency', efficiencyScore);
        result.put('aes_learning', learningScore);
        return result;
    }
}