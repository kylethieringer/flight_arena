function tests = test_run_session_gui
%TEST_RUN_SESSION_GUI Tests for run_session_gui and the run_session_unified('defaults')
% query it is built on. The GUI tests drive the real window headlessly; every run is
% hw.simulate into a scratch folder, so no hardware is touched. Expected values come
% from the USER SETTINGS themselves, so editing a default does not break a test.
tests = functiontests(localfunctions);
end

%% ---- fixtures ------------------------------------------------------------

function setup(~)
closeGui();   % every test starts without a settings window
end

function teardown(~)
closeGui();
end

%% ---- run_session_unified('defaults') -----------------------------------

function testDefaultsQueryReturnsTheUserSettings(testCase)
% Exactly the USER SETTINGS block. The values run_session_unified derives afterwards
% (duty cycle, trigger time, ...) are not valid overrides, so a GUI built from them
% would send fields the run rejects.
S = run_session_unified('defaults');
verifyClass(testCase, S.saveFolder, 'char');
verifyTrue(testCase, isfield(S.meta, 'flyNumber') && isfield(S.opto, 'mode') && isfield(S.basler.top, 'serial'), ...
    'The settings sections must come back as nested structs.');
verifyFalse(testCase, isfield(S.opto, 'duty_cycle'), 'Derived opto settings must not be returned.');
verifyFalse(testCase, isfield(S.phantom, 'trigger_time_s'), 'Derived Phantom settings must not be returned.');
end

function testDefaultsQueryLeavesOpenFiguresAlone(testCase)
% The query must stop after USER SETTINGS -- before the close all / clc a real
% session starts with, which would take the caller's figures (and the GUI) with it.
f = figure('Visible', 'off');
testCase.addTeardown(@() delete(f(isvalid(f))));
run_session_unified('defaults');
verifyTrue(testCase, isvalid(f), 'A defaults query must not close open figures.');
end

%% ---- window: built from the file ---------------------------------------

function testEverySettingHasOneControl(testCase)
% The window is generated from the settings struct: every setting in USER SETTINGS
% must be editable, none dropped or doubled, with no GUI edit when one is added.
fig = run_session_gui();
paths = leafPaths(run_session_unified('defaults'));
for i = 1:numel(paths)
    verifyNumElements(testCase, findall(fig, 'Tag', paths{i}), 1, paths{i});
end
end

function testFieldsShowTheFileDefaults(testCase)
S = run_session_unified('defaults');
fig = run_session_gui();
verifyEqual(testCase, val(fig, 'saveFolder'), S.saveFolder);
verifyEqual(testCase, val(fig, 'meta.experiment_name'), S.meta.experiment_name);
verifyEqual(testCase, val(fig, 'hw.simulate'), S.hw.simulate);
verifyEqual(testCase, str2num(val(fig, 'opto.stimDurations')), S.opto.stimDurations); %#ok<ST2NM>
verifyEqual(testCase, str2num(val(fig, 'basler.side.gain')), S.basler.side.gain);     %#ok<ST2NM>
verifyEqual(testCase, strtrim(strsplit(val(fig, 'acq.ai_names'), ',')), S.acq.ai_names);
end

function testControlTypeFollowsTheDefault(testCase)
fig = run_session_gui();
verifyClass(testCase, ctrl(fig, 'hw.simulate'),       'matlab.ui.control.CheckBox');
verifyClass(testCase, ctrl(fig, 'basler.top.enable'), 'matlab.ui.control.CheckBox');
verifyClass(testCase, ctrl(fig, 'acq.TrialLength'),   'matlab.ui.control.EditField');
verifyClass(testCase, ctrl(fig, 'meta.genotype'),     'matlab.ui.control.EditField');
end

function testModeSettingsOfferEveryValidMode(testCase)
% The values run_session_unified accepts; a dropdown missing one makes it unreachable.
S = run_session_unified('defaults');
fig = run_session_gui();
modes = struct('path', {'visual.mode', 'opto.mode', 'phantom.mode', 'phantom.trigger_at', ...
                        'phantom.save_format', 'basler.top.line_inverter'}, ...
               'valid', {{'closed_loop_stripe', 'closed_loop_oscillating', 'none'}, ...
                         {'randomized', 'windows', 'both', 'none'}, {'framesync', 'fixed_fps'}, ...
                         {'end', 'start'}, {'tif12', 'cine'}, {'False', 'True'}});
for m = modes
    dd = ctrl(fig, m.path);
    verifyClass(testCase, dd, 'matlab.ui.control.DropDown', m.path);
    verifyTrue(testCase, all(ismember(m.valid, dd.Items)), [m.path ' is missing a valid value.']);
    verifyEqual(testCase, dd.Value, defaultAt(S, m.path), [m.path ' must start at the file default.']);
end
end

function testTooltipIsTheSettingsLineComment(testCase)
% Hovering a field shows the comment written next to it in USER SETTINGS.
fig = run_session_gui();
c = ctrl(fig, 'hw.simulate');
tip = char(c.Tooltip);
verifyNotEmpty(testCase, tip);
verifyTrue(testCase, endsWith(strtrim(settingsLine('hw.simulate')), tip), 'The tooltip must be the end-of-line comment.');
verifyFalse(testCase, startsWith(tip, '%') || contains(tip, 'hw.simulate'), 'Only the comment text, not the code.');
end

function testSettingWithoutACommentHasNoTooltip(testCase)
% It must not borrow the comment of a neighbouring line.
assumeFalse(testCase, contains(settingsLine('meta.flyNumber'), '%'), 'meta.flyNumber has gained a comment.');
fig = run_session_gui();
c = ctrl(fig, 'meta.flyNumber');
verifyEmpty(testCase, char(c.Tooltip));
end

function testSecondCallReusesTheOpenWindow(testCase)
% Two windows could start two sessions on one rig; a second call brings back the first.
fig1 = run_session_gui();
fig2 = run_session_gui();
verifySameHandle(testCase, fig2, fig1);
verifyNumElements(testCase, findall(groot, 'Type', 'figure', 'Tag', 'run_session_gui'), 1);
end

function testEveryRowIsVisibleWhenTabsCannotScroll(testCase)
% Before grid layouts could scroll (R2019a, for one), a row below the bottom of its
% tab can never be reached, so there every tab's rows must fit inside the tab.
% Skipped where the tabs scroll; it does its work on the older MATLAB on the rig.
fig = run_session_gui();
% Sizes arrive asynchronously: until the window has been laid out, the tab group still
% reports its creation default (250 x 210 px). Laid out = stretched across the window.
tg = findall(fig, 'Type', 'uitabgroup');
t0 = tic;
while tg.Position(3) < fig.Position(3) / 2 && toc(t0) < 10
    drawnow; pause(0.1);
end
assertGreaterThanOrEqual(testCase, tg.Position(3), fig.Position(3) / 2, 'The window was never laid out.');
avail = tg.SelectedTab.Position(4);   % every tab of the group has the same content area
for t = tg.Children'
    g = t.Children(1);
    assumeFalse(testCase, isprop(g, 'Scrollable') && strcmp(char(g.Scrollable), 'on'), ...
        'The settings tabs scroll on this release.');
    need = sum([g.RowHeight{:}]) + g.RowSpacing * (numel(g.RowHeight) - 1) + g.Padding(2) + g.Padding(4);
    verifyLessThanOrEqual(testCase, need, avail, ...
        sprintf('Tab "%s" needs %g px for its rows but is %g px tall.', t.Title, need, avail));
end
end

function testSettingsUnderAHeadingBelongToIt(testCase)
% A heading (basler.top, plotting.ch, ...) must be followed only by that struct's own
% settings: a plain setting listed after it would read as one of them. Every nested
% struct gets exactly one heading, so the check cannot pass by finding none.
fig = run_session_gui();
nHeadings = 0;
for t = findall(fig, 'Type', 'uitab')'
    kids = t.Children(1).Children;
    [~, order] = sort(arrayfun(@(k) k.Layout.Row, kids));
    under = '';   % path of the heading in force; '' above the first one
    for k = kids(order)'
        if startsWith(k.Tag, 'heading:')
            under = extractAfter(k.Tag, 'heading:');
            nHeadings = nHeadings + 1;
        elseif ~contains(k.Tag, ':') && ~isempty(under)
            verifyTrue(testCase, startsWith(k.Tag, [under '.']), ...
                sprintf('%s is listed under the %s heading.', k.Tag, under));
        end
    end
end
verifyEqual(testCase, nHeadings, nestedCount(run_session_unified('defaults'), 0), ...
    'Every nested settings struct must have exactly one heading.');
end

%% ---- editing: changed and invalid fields -------------------------------

function testEditedSettingsAreMarkedChanged(testCase)
% Every kind of control: text, checkbox, dropdown, number.
S = run_session_unified('defaults');
fig = run_session_gui();
setField(fig, 'meta.flyNumber', [S.meta.flyNumber 'x']);
setField(fig, 'hw.simulate', ~S.hw.simulate);
setField(fig, 'opto.mode', otherItem(ctrl(fig, 'opto.mode')));
setField(fig, 'acq.TrialLength', num2str(S.acq.TrialLength + 1));
for p = {'meta.flyNumber', 'hw.simulate', 'opto.mode', 'acq.TrialLength'}
    verifyTrue(testCase, isMarkedChanged(fig, p{1}), [p{1} ' must be marked as changed.']);
end
verifyFalse(testCase, isMarkedChanged(fig, 'meta.genotype'), 'An untouched setting must not be marked.');
end

function testSettingEditedBackToItsValueIsUnmarked(testCase)
% "Changed" means "differs from the file", compared as values: 90 retyped as 90.0 is not a change.
S = run_session_unified('defaults');
fig = run_session_gui();
setField(fig, 'acq.TrialLength', num2str(S.acq.TrialLength + 1));
setField(fig, 'acq.TrialLength', sprintf('%.1f', S.acq.TrialLength));
verifyFalse(testCase, isMarkedChanged(fig, 'acq.TrialLength'));
end

function testUnreadableNumberIsFlagged(testCase)
% 'pi' is valid MATLAB that yields a number: it must still be refused, because an
% entry is only ever read as numeric syntax, never run as code.
fig = run_session_gui();
for bad = {'3000 abc', '[0 3000', 'disp(1)', 'pi'}
    setField(fig, 'opto.stimDurations', bad{1});
    verifyTrue(testCase, isFlagged(fig, 'opto.stimDurations'), sprintf('"%s" must be flagged.', bad{1}));
end
setField(fig, 'opto.stimDurations', '[0 3000]');
verifyFalse(testCase, isFlagged(fig, 'opto.stimDurations'), 'Fixing the entry must clear the flag.');
end

function testSingleNumberSettingRejectsAListOrNothing(testCase)
% acq.TrialLength is one number in the file; '[4 5]' or an empty box is a typo, not a setting.
fig = run_session_gui();
for bad = {'[4 5]', ''}
    setField(fig, 'acq.TrialLength', bad{1});
    verifyTrue(testCase, isFlagged(fig, 'acq.TrialLength'), sprintf('"%s" must be flagged.', bad{1}));
end
end

function testListSettingMayBeEmptied(testCase)
S = run_session_unified('defaults');
assumeFalse(testCase, isscalar(S.opto.stimDurations), 'opto.stimDurations is no longer a list.');
fig = run_session_gui();
setField(fig, 'opto.stimDurations', '');
verifyFalse(testCase, isFlagged(fig, 'opto.stimDurations'));
end

function testResetRestoresTheFileDefaults(testCase)
S = run_session_unified('defaults');
fig = run_session_gui();
setField(fig, 'meta.flyNumber', [S.meta.flyNumber 'x']);
setField(fig, 'opto.stimDurations', 'abc');
click(fig, 'resetButton');
verifyEqual(testCase, val(fig, 'meta.flyNumber'), S.meta.flyNumber);
verifyEqual(testCase, str2num(val(fig, 'opto.stimDurations')), S.opto.stimDurations); %#ok<ST2NM>
verifyFalse(testCase, isMarkedChanged(fig, 'meta.flyNumber'));
verifyFalse(testCase, isFlagged(fig, 'opto.stimDurations'));
end

%% ---- Run ---------------------------------------------------------------

function testRunRefusesInvalidSettings(testCase)
fig = simulatedGui(testCase, 4);
setField(fig, 'opto.stimDurations', 'abc');
click(fig, 'runButton');
verifyEmpty(testCase, dir(fullfile(testCase.TestData.dir, '*.mat')), 'No session may start.');
verifySubstring(testCase, statusText(fig), 'opto.stimDurations', 'The status must name the bad setting.');
end

function testRunSendsTheEditsToTheSession(testCase)
% Text, number, list, checkbox: each must reach the run with the type of its default.
fig = simulatedGui(testCase, 4);
setField(fig, 'meta.flyNumber', '7');
setField(fig, 'opto.stimDurations', '[500 1000]');
click(fig, 'runButton');
params = savedParams(testCase);
verifyEqual(testCase, params.meta.flyNumber, '7');
verifyEqual(testCase, params.opto.stimDurations, [500 1000]);
verifyEqual(testCase, params.acq.TrialLength, 4);
verifyEqual(testCase, params.hw.simulate, true);
verifySubstring(testCase, params.baseFileName, 'Fly7');
end

function testRunLogsOnlyTheChangedSettings(testCase)
% The command window records what this session changed from the file, and nothing else.
fig = simulatedGui(testCase, 4);
setField(fig, 'meta.flyNumber', '7');
b = ctrl(fig, 'runButton'); %#ok<NASGU> -- used inside the evalc string
txt = evalc('b.ButtonPushedFcn(b, [])');
verifySubstring(testCase, txt, 'meta.flyNumber = ''7''');
verifySubstring(testCase, txt, 'acq.TrialLength = 4');
verifyFalse(testCase, contains(txt, 'meta.genotype'), 'An unchanged setting must not be listed.');
end

function testRunResultIsPutInTheBaseWorkspace(testCase)
% The result of *this* run: an out left by an earlier session is cleared first, and
% the one found afterwards must belong to this test's own (unique) save folder.
fig = simulatedGui(testCase, 4);
evalin('base', 'clear out');
testCase.addTeardown(@() evalin('base', 'clear out'));
click(fig, 'runButton');
out = evalin('base', 'out');
verifyEqual(testCase, out.params.saveFolder, testCase.TestData.dir);
end

function testWindowStaysOpenWithTheValuesAfterARun(testCase)
% Ready for the next trial: same values, still marked, Run available again.
fig = simulatedGui(testCase, 4);
setField(fig, 'meta.flyNumber', '7');
click(fig, 'runButton');
verifyTrue(testCase, isvalid(fig), 'The session''s close all must not close the window.');
verifyEqual(testCase, val(fig, 'meta.flyNumber'), '7');
verifyTrue(testCase, isMarkedChanged(fig, 'meta.flyNumber'));
b = ctrl(fig, 'runButton');
verifyEqual(testCase, char(b.Enable), 'on');
end

function testWindowIsLockedWhileRunning(testCase)
% Mid-run, Run must not start a second session and the window must refuse to close.
% A timer looks at the window while the session is running (it fires in the run's pause).
fig = simulatedGui(testCase, 30);   % ~3 s of wall time at hw.sim_speed 10
seen = containers.Map();
t = timer('StartDelay', 1, 'TimerFcn', @(~, ~) probeLock(fig, seen));
testCase.addTeardown(@() delete(t));
start(t);
click(fig, 'runButton');
assertTrue(testCase, isKey(seen, 'openAfterClose'), 'The probe never ran during the session.');
verifyEqual(testCase, seen('runEnabled'), 'off', 'Run must be disabled while a session runs.');
verifyEqual(testCase, seen('fieldEnabled'), 'off', 'Settings must be locked while a session runs.');
verifyTrue(testCase, seen('openAfterClose'), 'Closing the window must be refused while a session runs.');
end

function testRunErrorIsReportedAndTheWindowRecovers(testCase)
% A window past the end of the block is rejected by run_session_unified's own checks.
fig = simulatedGui(testCase, 4);
setField(fig, 'opto.mode', 'windows');
setField(fig, 'opto.windows_s', '[10 11]');
click(fig, 'runButton');
% The message the session itself gives for these settings, obtained without the window.
ov = struct('saveFolder', testCase.TestData.dir, 'hw', struct('simulate', true), ...
            'acq', struct('TrialLength', 4), 'opto', struct('mode', 'windows', 'windows_s', [10 11]));
msg = '';
try
    run_session_unified(ov);
catch ME
    msg = ME.message;
end
assertNotEmpty(testCase, msg, 'These settings no longer make run_session_unified fail.');
verifySubstring(testCase, statusText(fig), msg);
verifyEmpty(testCase, dir(fullfile(testCase.TestData.dir, '*.mat')));
b = ctrl(fig, 'runButton');
verifyEqual(testCase, char(b.Enable), 'on', 'Run must be available again after a failed session.');
end

%% ---- Save as file defaults ---------------------------------------------
% These tests rewrite a private copy of run_session_unified.m placed ahead of the
% real one on the path, so the real file is never touched.

function testSaveDefaultsWritesTheValuesIntoTheFile(testCase)
% Every kind of control, plus a setting inside a struct(...) call (basler.side.gain):
% the file re-read gives the new values, the window shows them unmarked, and Reset
% now returns to them.
file = tempSettingsFile(testCase);
S = run_session_unified('defaults');
fig = run_session_gui();
setappdata(fig, 'skipConfirm', true);
want = {'meta.flyNumber',     [S.meta.flyNumber '7']
        'hw.simulate',        ~S.hw.simulate
        'opto.mode',          otherItem(ctrl(fig, 'opto.mode'))
        'acq.TrialLength',    S.acq.TrialLength + 1
        'opto.stimDurations', [0 500 750]
        'basler.side.gain',   S.basler.side.gain + 1
        'saveFolder',         [S.saveFolder 'newdefault\']};
for k = 1:size(want, 1)
    v = want{k, 2};
    if isnumeric(v), v = mat2str(v); end
    setField(fig, want{k, 1}, v);
end
click(fig, 'saveDefaultsButton');
verifySubstring(testCase, statusText(fig), 'Saved', 'The status must report the save.');
S2 = run_session_unified('defaults');
for k = 1:size(want, 1)
    verifyEqual(testCase, defaultAt(S2, want{k, 1}), want{k, 2}, [want{k, 1} ' must be the new file default.']);
    verifyFalse(testCase, isMarkedChanged(fig, want{k, 1}), [want{k, 1} ' must no longer be marked as changed.']);
end
click(fig, 'resetButton');
verifyEqual(testCase, val(fig, 'meta.flyNumber'), want{1, 2}, 'Reset must return to the new defaults.');
verifySubstring(testCase, fileread(file), ['acq.TrialLength     = ' mat2str(want{4, 2}) ';'], ...
    'The value must be written in place, keeping the alignment of the = sign.');
verifyEqual(testCase, fileread(testCase.TestData.realFile), testCase.TestData.realText, ...
    'The real run_session_unified.m must not be touched.');
end

function testSaveDefaultsKeepsTheRestOfTheFile(testCase)
% Only the value changes: the comment next to the setting, its alignment and every
% other line survive, and a struct(...) statement keeps its shape.
file = tempSettingsFile(testCase);
before = splitlines(fileread(file));
S = run_session_unified('defaults');
fig = run_session_gui();
setappdata(fig, 'skipConfirm', true);
setField(fig, 'acq.TrialLength', num2str(S.acq.TrialLength + 1));
setField(fig, 'basler.side.gain', num2str(S.basler.side.gain + 1));
click(fig, 'saveDefaultsButton');
after = splitlines(fileread(file));
assertEqual(testCase, numel(after), numel(before), 'The number of lines must not change.');
diffLines = find(~strcmp(before, after));
verifyNumElements(testCase, diffLines, 2, 'Exactly the two assignments may differ.');
for i = diffLines'
    verifyEqual(testCase, regexp(after{i}, '%.*$', 'match', 'once'), regexp(before{i}, '%.*$', 'match', 'once'), ...
        sprintf('Line %d must keep its comment.', i));
    verifyEqual(testCase, find(after{i} == '=', 1), find(before{i} == '=', 1), ...
        sprintf('Line %d must keep the column of its = sign.', i));
end
verifyTrue(testCase, any(contains(after(diffLines), 'acq.TrialLength')), 'The acq.TrialLength line must be the one rewritten.');
verifyTrue(testCase, any(contains(after(diffLines), ['''gain'', ' num2str(S.basler.side.gain + 1)])), ...
    'The gain value inside the basler.side struct(...) call must be the one rewritten.');
end

function testSaveDefaultsRefusesInvalidEntries(testCase)
file = tempSettingsFile(testCase);
before = fileread(file);
fig = run_session_gui();
setappdata(fig, 'skipConfirm', true);
setField(fig, 'meta.flyNumber', '9');
setField(fig, 'opto.stimDurations', 'abc');
click(fig, 'saveDefaultsButton');
verifyEqual(testCase, fileread(file), before, 'Nothing may be written while an entry is invalid.');
verifySubstring(testCase, statusText(fig), 'opto.stimDurations', 'The status must name the bad setting.');
verifyTrue(testCase, isMarkedChanged(fig, 'meta.flyNumber'), 'The pending edit must stay in the window.');
end

function testSaveDefaultsWithNothingChangedLeavesTheFileAlone(testCase)
file = tempSettingsFile(testCase);
before = fileread(file);
fig = run_session_gui();
setappdata(fig, 'skipConfirm', true);
click(fig, 'saveDefaultsButton');
verifyEqual(testCase, fileread(file), before);
verifySubstring(testCase, statusText(fig), 'nothing to save');
end

%% ---- helpers -------------------------------------------------------------

function file = tempSettingsFile(testCase)
% A private copy of run_session_unified.m that shadows the real one, so that saving
% defaults rewrites the copy. MATLAB resolves the current folder before the path, so
% the copy is made the current folder (the real code folder stays reachable on the
% path). The real file's path and text are kept in TestData so a test can check it
% was left alone.
realFile = which('run_session_unified');
realDir  = fileparts(realFile);
testCase.TestData.realFile = realFile;
testCase.TestData.realText = fileread(realFile);
onPath = contains([pathsep path pathsep], [pathsep realDir pathsep]);
if ~onPath, addpath(realDir); end
d = tempname;
mkdir(d);
file = fullfile(d, 'run_session_unified.m');
copyfile(realFile, file);
fileattrib(file, '+w');
oldDir = cd(d);
clear('run_session_unified');
testCase.addTeardown(@() removeTempSettingsFile(d, oldDir, realDir, ~onPath));
assert(strcmp(which('run_session_unified'), file), 'The temporary copy does not shadow the real file.');
end

function removeTempSettingsFile(d, oldDir, realDir, dropPath)
cd(oldDir);
if dropPath, rmpath(realDir); end
clear('run_session_unified');
rmdir(d, 's');
end

function fig = simulatedGui(testCase, trialLength)
% The window set up for a fast, hardware-free session into a scratch folder:
% trialLength s of synthetic data at 10x real time, one block, no opto, no live plot.
testCase.TestData.dir = tempname;
mkdir(testCase.TestData.dir);
testCase.addTeardown(@() rmdir(testCase.TestData.dir, 's'));
fig = run_session_gui();
setField(fig, 'saveFolder', testCase.TestData.dir);
setField(fig, 'hw.simulate', true);
setField(fig, 'hw.sim_speed', '10');
setField(fig, 'acq.TrialLength', num2str(trialLength));
setField(fig, 'acq.blocks', '1');
setField(fig, 'opto.mode', 'none');
setField(fig, 'plotting.enable', false);
setField(fig, 'meta.auto_trial_number', false);
end

function params = savedParams(testCase)
f = dir(fullfile(testCase.TestData.dir, '*.mat'));
assert(isscalar(f), 'Expected one session file in the scratch folder, found %d.', numel(f));
L = load(fullfile(f.folder, f.name), 'params');
params = L.params;
end

function t = statusText(fig)
s = ctrl(fig, 'statusLabel');
t = char(strjoin(cellstr(s.Text), ' '));
end

function probeLock(fig, seen)
b = findall(fig, 'Tag', 'runButton');
c = findall(fig, 'Tag', 'meta.flyNumber');
seen('runEnabled')   = char(b.Enable);
seen('fieldEnabled') = char(c.Enable);
close(fig);
seen('openAfterClose') = isvalid(fig); %#ok<NASGU> -- seen is a handle (containers.Map)
end

function setField(fig, path, value)
% Enter a value the way a user would: set the control, then fire its callback.
c = ctrl(fig, path);
c.Value = value;
if ~isempty(c.ValueChangedFcn), c.ValueChangedFcn(c, []); end
end

function click(fig, tag)
b = ctrl(fig, tag);
b.ButtonPushedFcn(b, []);
end

function tf = isMarkedChanged(fig, path)
lbl = ctrl(fig, ['label:' path]);
tf = strcmp(char(lbl.FontWeight), 'bold');
end

function tf = isFlagged(fig, path)
% Flagged = coloured differently from a field that is always valid (free text).
c  = ctrl(fig, path);
ok = ctrl(fig, 'meta.genotype');
tf = ~isequal(c.BackgroundColor, ok.BackgroundColor);
end

function v = otherItem(dd)
others = dd.Items(~strcmp(dd.Items, dd.Value));
v = others{1};
end

function n = nestedCount(s, depth)
% Structs below the section level (basler.top, plotting.ch, ...): the ones that get a heading.
n = 0;
f = fieldnames(s);
for i = 1:numel(f)
    if isstruct(s.(f{i}))
        n = n + (depth >= 1) + nestedCount(s.(f{i}), depth + 1);
    end
end
end

function closeGui()
% delete, not close: close is refused while a session runs.
delete(findall(groot, 'Type', 'figure', 'Tag', 'run_session_gui'));
end

function c = ctrl(fig, path)
c = findall(fig, 'Tag', path);
assert(isscalar(c), 'Expected one control tagged "%s", found %d.', path, numel(c));
end

function v = val(fig, path)
c = ctrl(fig, path);
v = c.Value;
end

function v = defaultAt(S, path)
parts = strsplit(path, '.');
v = getfield(S, parts{:});
end

function p = leafPaths(s, prefix)
% Dotted path of every non-struct setting, e.g. 'basler.top.gain'.
if nargin < 2, prefix = ''; end
p = {};
f = fieldnames(s);
for i = 1:numel(f)
    if isempty(prefix), here = f{i}; else, here = [prefix '.' f{i}]; end
    if isstruct(s.(f{i}))
        p = [p, leafPaths(s.(f{i}), here)]; %#ok<AGROW>
    else
        p{end + 1} = here; %#ok<AGROW>
    end
end
end

function line = settingsLine(path)
% The line of run_session_unified.m that assigns this setting.
src = splitlines(fileread(which('run_session_unified')));
hit = src(~cellfun(@isempty, regexp(src, ['^\s*' regexptranslate('escape', path) '\s*='], 'once')));
assert(isscalar(hit), 'Expected one line assigning %s, found %d.', path, numel(hit));
line = hit{1};
end
