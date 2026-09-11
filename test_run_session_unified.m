function tests = test_run_session_unified
%TEST_RUN_SESSION_UNIFIED Session teardown, exercised through hardware-free
% (hw.simulate) sessions written to a scratch folder.
tests = functiontests(localfunctions);
end

%% ---- teardown ----------------------------------------------------------

function testTeardownRunsCleanlyAfterANormalSession(testCase)
% The teardown used to run after MATLAB had already cleared the variables it reads,
% so it failed part-way -- skipping the DAQ, camera and Phantom release -- on every exit.
ov = simulatedSession(testCase);
verifyWarningFree(testCase, @() run_session_unified(ov));
end

function testTeardownRunsCleanlyAfterAFailedSession(testCase)
% The error (and Ctrl+C) path, which is the one that must return the LED to 0 V.
% Decreasing plot limits make the live plot fail after the teardown is armed.
ov = simulatedSession(testCase);
ov.plotting.enable = true;
ov.plotting.ylim   = [50 -100];
testCase.addTeardown(@() close('all'));
lastwarn('', '');
verifyError(testCase, @() run_session_unified(ov), ?MException);
[msg, id] = lastwarn;
verifyEmpty(testCase, msg, sprintf('The session left a warning (%s): %s', id, msg));
end

%% ---- helpers -------------------------------------------------------------

function ov = simulatedSession(testCase)
% Overrides for a 4 s hardware-free session into a scratch folder.
d = tempname;
mkdir(d);
testCase.addTeardown(@() rmdir(d, 's'));
ov = struct('saveFolder', d, 'hw', struct('simulate', true), 'acq', struct('TrialLength', 4), ...
            'opto', struct('mode', 'none'), 'plotting', struct('enable', false));
end
