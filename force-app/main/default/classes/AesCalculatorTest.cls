/**
 * @description Test class for AesCalculator utility.
 */
@IsTest
public class AesCalculatorTest {

    @IsTest
    static void testPerfectSession() {
        Map<String, Decimal> result = AesCalculator.calculateAes(
            'success',  // finalOutcome
            2,          // actionsTaken (under optimal)
            3,          // optimalActions
            true,       // lessonApplied
            true,       // lessonSuccessful
            true        // lessonCreated
        );

        Assert.areEqual(40, result.get('aes_goal'), 'Goal should be 40 for success');
        Assert.areEqual(30, result.get('aes_efficiency'), 'Efficiency should be 30 when under optimal');
        Assert.areEqual(25, result.get('aes_learning'), 'Learning should be 25 (15 applied+successful + 10 created)');
        Assert.areEqual(95, result.get('aes_score'), 'AES should be 95');
    }

    @IsTest
    static void testSuccessButInefficient() {
        Map<String, Decimal> result = AesCalculator.calculateAes(
            'success',  // finalOutcome
            9,          // actionsTaken (3x optimal)
            3,          // optimalActions
            false,      // lessonApplied
            false,      // lessonSuccessful
            false       // lessonCreated
        );

        Assert.areEqual(40, result.get('aes_goal'), 'Goal should be 40 for success');
        Assert.areEqual(0, result.get('aes_efficiency'), 'Efficiency should be 0 when penalty maxes out');
        Assert.areEqual(0, result.get('aes_learning'), 'Learning should be 0 with no lesson interaction');
        Assert.areEqual(40, result.get('aes_score'), 'AES should be 40');
    }

    @IsTest
    static void testFailureWithLearning() {
        Map<String, Decimal> result = AesCalculator.calculateAes(
            'failure',  // finalOutcome
            1,          // actionsTaken (under optimal)
            3,          // optimalActions
            false,      // lessonApplied
            false,      // lessonSuccessful
            true        // lessonCreated
        );

        Assert.areEqual(0, result.get('aes_goal'), 'Goal should be 0 for failure');
        Assert.areEqual(30, result.get('aes_efficiency'), 'Efficiency should be 30 when under optimal');
        Assert.areEqual(10, result.get('aes_learning'), 'Learning should be 10 for lesson created');
        Assert.areEqual(40, result.get('aes_score'), 'AES should be 40');
    }

    @IsTest
    static void testPartialWithLesson() {
        Map<String, Decimal> result = AesCalculator.calculateAes(
            'partial',  // finalOutcome
            4,          // actionsTaken (equals optimal)
            4,          // optimalActions
            true,       // lessonApplied
            true,       // lessonSuccessful
            false       // lessonCreated
        );

        Assert.areEqual(20, result.get('aes_goal'), 'Goal should be 20 for partial');
        Assert.areEqual(30, result.get('aes_efficiency'), 'Efficiency should be 30 when at optimal');
        Assert.areEqual(15, result.get('aes_learning'), 'Learning should be 15 for applied+successful');
        Assert.areEqual(65, result.get('aes_score'), 'AES should be 65');
    }
}