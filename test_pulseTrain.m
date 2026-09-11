function tests = test_pulseTrain
%TEST_PULSETRAIN Unit tests for the shared carrier kernel.
tests = functiontests(localfunctions);
end

%% ---- helpers -----------------------------------------------------------

function n = countPulses(s)
n = sum(diff([0; double(s(:) > 0)]) == 1);
end

%% ---- shape and basic behaviour -----------------------------------------

function testReturnsColumnOfRequestedLength(testCase)
s = pulseTrain(1234, 10, 20000, 200, 0.6);
verifySize(testCase, s, [1234 1], 'Must return an nSamples x 1 column.');
end

function testEmptyFrequencyIsContinuous(testCase)
verifyEqual(testCase, pulseTrain(100, 10, 20000, [], 0.5), 10 * ones(100, 1), ...
    'Frequency [] must give a continuous burst.');
end

function testZeroFrequencyIsContinuous(testCase)
verifyEqual(testCase, pulseTrain(100, 10, 20000, 0, 0.5), 10 * ones(100, 1), ...
    'Frequency 0 must give a continuous burst.');
end

function testFullDutyCycleIsContinuous(testCase)
verifyEqual(testCase, pulseTrain(20000, 10, 20000, 200, 1), 10 * ones(20000, 1), ...
    'A duty cycle of 1 must be indistinguishable from continuous.');
end

function testZeroOrNegativeSamplesGivesEmpty(testCase)
verifySize(testCase, pulseTrain(0, 10, 20000, 200, 0.5),  [0 1]);
verifySize(testCase, pulseTrain(-5, 10, 20000, 200, 0.5), [0 1]);
end

function testAmplitudeIsHonoured(testCase)
s = pulseTrain(20000, 7.5, 20000, 200, 0.5);
verifyEqual(testCase, max(s), 7.5, 'On samples must equal the amplitude.');
verifyEqual(testCase, min(s), 0,   'Off samples must be 0.');
end

function testZeroAmplitudeIsAllZero(testCase)
verifyEqual(testCase, pulseTrain(1000, 0, 20000, 200, 0.5), zeros(1000, 1), ...
    'A sham (0 V) burst must be all zero.');
end

%% ---- carrier accuracy: the bugs this kernel exists to prevent -----------

function testBurstBeginsOnARisingEdge(testCase)
s = pulseTrain(20000, 10, 20000, 200, 0.25);
verifyEqual(testCase, s(1), 10, 'Phase must start at 0 so the burst opens with the pulse on.');
end

function testDeliversOnePulsePerCycle(testCase)
% 200 Hz for 1 s at 20 kHz = exactly 200 pulses.
verifyEqual(testCase, countPulses(pulseTrain(20000, 10, 20000, 200, 0.5)), 200);
end

function testOnFractionEqualsDutyCycle(testCase)
s = pulseTrain(20000, 10, 20000, 200, 0.6);
verifyEqual(testCase, mean(s > 0), 0.6, 'AbsTol', 1e-9);
end

function testNonIntegerPeriodDoesNotAccumulateDrift(testCase)
% 300 Hz at 20 kHz is 66.67 samples/period. The old repmat-of-a-rounded-cycle
% form gave 67 samples = 298.51 Hz and lost pulses over a long burst.
s = pulseTrain(5 * 20000, 10, 20000, 300, 0.5);
verifyEqual(testCase, countPulses(s), 1500, ...
    '300 Hz for 5 s must deliver exactly 1500 pulses with no drift.');
end

function testRealisedRateMatchesRequestedOverALongBurst(testCase)
% The rig default: 3 ms pulses at 200 Hz, 20 kHz, over a 3 s stimulus.
s = pulseTrain(3 * 20000, 10, 20000, 200, 0.6);
verifyEqual(testCase, countPulses(s), 600, '200 Hz for 3 s must be 600 pulses.');
end

%% ---- validation --------------------------------------------------------

function testSubSamplePulseWidthErrors(testCase)
% 0.02 ms at 200 Hz / 20 kHz is 0.4 samples on: silently produced nothing before.
verifyError(testCase, @() pulseTrain(20000, 10, 20000, 200, 0.004), ...
    'pulseTrain:pulseTooShort');
end

function testFrequencyAboveNyquistErrors(testCase)
verifyError(testCase, @() pulseTrain(20000, 10, 20000, 30000, 0.5), ...
    'pulseTrain:frequencyTooHigh');
end

function testDutyCycleAboveOneErrors(testCase)
verifyError(testCase, @() pulseTrain(20000, 10, 20000, 200, 1.5), ...
    'pulseTrain:invalidDutyCycle');
end

function testZeroDutyCycleErrors(testCase)
verifyError(testCase, @() pulseTrain(20000, 10, 20000, 200, 0), ...
    'pulseTrain:invalidDutyCycle');
end

function testValidationIsSkippedWithoutACarrier(testCase)
% DutyCycle is documented as ignored when there is no carrier.
verifyEqual(testCase, pulseTrain(10, 10, 20000, [], 99), 10 * ones(10, 1), ...
    'DutyCycle must not be validated when Frequency is empty.');
end
