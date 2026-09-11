function varargout = run_session_gui()
% RUN_SESSION_GUI  Window for editing the USER SETTINGS of run_session_unified and
% starting a session with them.
%
% USAGE
%   run_session_gui          % open the window (or bring the open one to the front)
%   fig = run_session_gui;   % ... and return its uifigure
%
% The window is generated from run_session_unified('defaults'), so it always opens on
% the values currently in the USER SETTINGS block, and a setting added there shows up
% here with no change to this file. One tab per settings section; hover over a field
% for the comment written next to it in the file. A setting that differs from the
% file has a bold orange label; an entry that cannot be read as a value turns red.
%
%   Run    starts run_session_unified with every setting that differs from the file
%          as an override. The window is locked until the session ends, then keeps
%          your values for the next trial. The session's result is left in `out` in
%          the base workspace, and the changed settings are listed in the command
%          window when it ends. Errors are shown in the window.
%   Reset  re-reads the file, dropping your edits.
%
% Runs on R2019a and newer. Where grid layouts cannot scroll yet (R2019a, for one),
% the window is a little wider and long sections continue on extra tabs
% ("Basler 2", ...) so that every setting stays on screen.
%
% Author: Kyle Thieringer, 2026-09

GUI_TAG  = 'run_session_gui';
ROW_H    = 22;     % px per settings row
LABEL_W  = 180;
BROWSE_W = 80;
CHANGED_COLOR = [0.85 0.33 0];    % label of a setting that differs from the file
BAD_COLOR     = [1 0.78 0.78];    % background of an entry that cannot be read
ERROR_COLOR   = [0.8 0 0];        % status text after a failure
RUNNING_TEXT  = 'Running...';
% Only where grid layouts cannot scroll:
FALLBACK_SIZE   = [760 760];      % window size, wide enough for the extra tabs
PAGE_ROWS       = 22;             % rows per tab: 22*22 + 21*4 + 20 = 588 px, inside the ~650 px a tab gets
COMPACT_SPACING = 4;              % px between rows
% Only where grid rows and columns cannot be sized to 'fit':
BAR_H   = 26;                     % bottom bar height
RESET_W = 150;                    % Reset button width
RUN_W   = 60;                     % Run button width
SECTION_TITLES = struct('meta', 'Meta', 'hw', 'Hardware', 'acq', 'Acquisition', 'visual', 'Visual', ...
                        'opto', 'Opto', 'basler', 'Basler', 'phantom', 'Phantom', 'plotting', 'Plotting');
% Settings with a fixed set of values, as validated by run_session_unified.
CHOICES = {'visual.mode',               {'closed_loop_stripe', 'closed_loop_oscillating', 'none'}
           'opto.mode',                 {'randomized', 'windows', 'both', 'none'}
           'phantom.mode',              {'framesync', 'fixed_fps'}
           'phantom.trigger_at',        {'end', 'start'}
           'phantom.save_format',       {'tif12', 'cine'}
           'basler.top.line_inverter',  {'False', 'True'}
           'basler.side.line_inverter', {'False', 'True'}};
FOLDERS = {'saveFolder', 'phantom.saveRoot'};   % get a Browse button

% One window per MATLAB: two could start two sessions on the same rig.
existing = findall(groot, 'Type', 'figure', 'Tag', GUI_TAG);
if ~isempty(existing)
    fig = existing(1);
    figure(fig);
    if nargout > 0, varargout{1} = fig; end
    return;
end

% HandleVisibility 'off' keeps the window out of the close all a session starts with.
fig = uifigure('Name', 'Flight arena session', 'Tag', GUI_TAG, 'HandleVisibility', 'off', ...
               'Position', [100 100 640 760], 'CloseRequestFcn', @(~, ~) onClose());
root = uigridlayout(fig, [3 1]);
% Layout features newer than R2019a are used only where this MATLAB has them: 'fit'
% grid sizes (R2019b), label WordWrap (R2020b) and scrollable grid layouts (present by
% R2021a). Without scrolling, long sections continue on extra tabs instead.
canFit    = acceptsFit(root);
canScroll = isprop(root, 'Scrollable');
if canFit, root.RowHeight = {'fit', '1x', 'fit'}; else, root.RowHeight = {ROW_H, '1x', BAR_H}; end
if ~canScroll, fig.Position(3:4) = FALLBACK_SIZE; end
topGrid = uigridlayout(root, [1 3], 'Padding', [0 0 0 0]);
topGrid.ColumnWidth = {LABEL_W, '1x', BROWSE_W};
tabs = uitabgroup(root);
bottom = uigridlayout(root, [1 3], 'Padding', [0 0 0 0]);
if canFit, bottom.ColumnWidth = {'1x', 'fit', 'fit'}; else, bottom.ColumnWidth = {'1x', RESET_W, RUN_W}; end
statusLabel = uilabel(bottom, 'Text', '', 'Tag', 'statusLabel');
if canFit && isprop(statusLabel, 'WordWrap'), statusLabel.WordWrap = 'on'; end   % grows the 'fit' row
statusFg = statusLabel.FontColor;
uibutton(bottom, 'Text', 'Reset to file defaults', 'Tag', 'resetButton', ...
         'Tooltip', 'Re-read the USER SETTINGS block of run_session_unified.m', ...
         'ButtonPushedFcn', @(~, ~) onReset());
uibutton(bottom, 'Text', 'Run', 'Tag', 'runButton', 'FontWeight', 'bold', ...
         'Tooltip', 'Start run_session_unified with these settings', ...
         'ButtonPushedFcn', @(~, ~) onRun());
running = false;   % a session started from this window is in progress

% One entry per editable setting. fg / bg / labelFg are the colours the controls were
% created with, restored when a flag or mark is cleared (so a dark theme survives).
fields = struct('path', {}, 'kind', {}, 'default', {}, 'ctrl', {}, 'label', {}, ...
                'fg', {}, 'bg', {}, 'labelFg', {});
buildForm(run_session_unified('defaults'));

if nargout > 0, varargout{1} = fig; end

%% ======================= NESTED FUNCTIONS ===============================

    function buildForm(S)
        % (Re)create every control from the settings struct S: top-level plain
        % settings (saveFolder) above the tabs, one tab per settings section.
        tips = settingComments();
        delete(topGrid.Children);
        delete(tabs.Children);
        fields = fields([]);
        names = fieldnames(S);
        isSection = cellfun(@(n) isstruct(S.(n)), names);
        top = names(~isSection);
        topGrid.RowHeight = repmat({ROW_H}, 1, numel(top));
        if ~canFit   % what 'fit' would have made of this row
            root.RowHeight{1} = numel(top) * ROW_H + max(0, numel(top) - 1) * topGrid.RowSpacing;
        end
        for i = 1:numel(top)
            addSetting(topGrid, i, top{i}, top{i}, S.(top{i}), tips);
        end
        secs = names(isSection);
        for i = 1:numel(secs)
            items = flatten(S.(secs{i}), secs{i});
            if canScroll, pages = {items}; else, pages = pageItems(items, PAGE_ROWS); end
            for p = 1:numel(pages)
                tabTitle = sectionTitle(secs{i});
                if p > 1, tabTitle = sprintf('%s %d', tabTitle, p); end
                addTab(tabTitle, pages{p}, tips);
            end
        end
    end

    function addTab(tabTitle, items, tips)
        tab = uitab(tabs, 'Title', tabTitle);
        g = uigridlayout(tab, [max(1, numel(items)) 3]);
        g.RowHeight   = repmat({ROW_H}, 1, numel(items));
        g.ColumnWidth = {LABEL_W, '1x', BROWSE_W};
        if canScroll, g.Scrollable = 'on'; else, g.RowSpacing = COMPACT_SPACING; end
        for r = 1:numel(items)
            if items(r).heading
                h = uilabel(g, 'Text', items(r).name, 'FontWeight', 'bold', 'Tag', ['heading:' items(r).path]);
                h.Layout.Row = r; h.Layout.Column = [1 3];
            else
                addSetting(g, r, items(r).name, items(r).path, items(r).value, tips);
            end
        end
    end

    function addSetting(g, r, name, path, value, tips)
        lbl = uilabel(g, 'Text', name, 'Tag', ['label:' path]);
        lbl.Layout.Row = r; lbl.Layout.Column = 1;
        [kind, items] = kindOf(path, value);
        switch kind
            case 'logical', c = uicheckbox(g, 'Text', '', 'Value', value);
            case 'choice',  c = uidropdown(g, 'Items', items, 'Value', value);
            otherwise,      c = uieditfield(g, 'text', 'Value', toText(kind, value));
        end
        if strcmp(kind, 'fixed'), c.Editable = 'off'; end
        c.Tag = path;
        c.Layout.Row = r; c.Layout.Column = 2;
        c.ValueChangedFcn = @(~, ~) refreshField(path);
        if isKey(tips, path), c.Tooltip = tips(path); lbl.Tooltip = tips(path); end
        if any(strcmp(path, FOLDERS))
            b = uibutton(g, 'Text', 'Browse...', 'Tag', ['browse:' path], ...
                         'ButtonPushedFcn', @(~, ~) browse(c, path));
            b.Layout.Row = r; b.Layout.Column = 3;
        end
        fg = []; bg = [];
        if isprop(c, 'FontColor'),       fg = c.FontColor;       end
        if isprop(c, 'BackgroundColor'), bg = c.BackgroundColor; end
        fields(end + 1) = struct('path', path, 'kind', kind, 'default', {value}, 'ctrl', c, 'label', lbl, ...
                                 'fg', fg, 'bg', bg, 'labelFg', lbl.FontColor);
    end

    function [kind, items] = kindOf(path, value)
        items = {};
        hit = strcmp(CHOICES(:, 1), path);
        if any(hit) && ischar(value)
            kind  = 'choice';
            items = CHOICES{hit, 2};
            if ~any(strcmp(items, value)), items = [{value}, items]; end   % keep an unlisted file value
        elseif islogical(value) && isscalar(value)
            kind = 'logical';
        elseif ischar(value) && (isrow(value) || isempty(value))
            kind = 'char';
        elseif isnumeric(value) && isreal(value) && ismatrix(value)
            kind = 'numeric';
        elseif iscellstr(value) && (isvector(value) || isempty(value))
            kind = 'cellstr';
        else
            kind = 'fixed';   % shown read-only and never sent; edit it in the file
        end
    end

    function refreshField(path)
        % Mark a setting that differs from the file; flag an entry that cannot be read.
        f = fields(strcmp({fields.path}, path));
        [v, ok] = readField(f);
        if ok && ~sameValue(v, f.default)
            f.label.FontWeight = 'bold';   f.label.FontColor = CHANGED_COLOR;
        else
            f.label.FontWeight = 'normal'; f.label.FontColor = f.labelFg;
        end
        if strcmp(f.kind, 'numeric')
            if ok, f.ctrl.BackgroundColor = f.bg;        f.ctrl.FontColor = f.fg;
            else,  f.ctrl.BackgroundColor = BAD_COLOR;   f.ctrl.FontColor = [0 0 0];
            end
        end
    end

    function [ov, changed, bad] = collectOverrides()
        % The settings that differ from the file, as the nested override struct
        % run_session_unified takes. changed = {path, value} rows for the log;
        % bad = paths of entries that cannot be read.
        ov = struct(); changed = cell(0, 2); bad = {};
        for k = 1:numel(fields)
            f = fields(k);
            refreshField(f.path);            % so the marks match exactly what is sent
            [v, ok] = readField(f);
            if ~ok, bad{end + 1} = f.path; continue; end %#ok<AGROW>
            if sameValue(v, f.default), continue; end
            parts = strsplit(f.path, '.');
            ov = setfield(ov, parts{:}, v);
            changed(end + 1, :) = {f.path, v}; %#ok<AGROW>
        end
    end

    function onRun()
        if running, return; end
        [ov, changed, bad] = collectOverrides();
        if ~isempty(bad)
            setStatus(['Not started. Fix the red entries: ' strjoin(bad, ', ')], true);
            uialert(fig, sprintf('These entries cannot be read as values:\n\n%s', strjoin(bad, newline)), ...
                    'Invalid settings');
            return;
        end
        setRunning(true);
        setStatus(RUNNING_TEXT, false);
        drawnow;
        finish = onCleanup(@() finishRun(changed));   % runs on success, error or Ctrl+C
        try
            out = run_session_unified(ov);
            assignin('base', 'out', out);
            setStatus(['Saved ' out.params.files.mat], false);
        catch ME
            fprintf(2, 'run_session_gui: the session failed.\n%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
            setStatus(['Failed: ' ME.message], true);
            if isvalid(fig), uialert(fig, ME.message, 'Session failed'); end
        end
    end

    function finishRun(changed)
        setRunning(false);
        logChanges(changed);
        if isvalid(fig) && strcmp(statusLabel.Text, RUNNING_TEXT)   % interrupted with Ctrl+C
            setStatus('Stopped before the session finished; see the command window.', true);
        end
    end

    function setRunning(tf)
        % Lock every control (Run and Reset included) while a session runs.
        running = tf;
        if ~isvalid(fig), return; end
        if tf, e = 'off'; else, e = 'on'; end
        for k = 1:numel(fields), fields(k).ctrl.Enable = e; end
        set(findall(fig, 'Type', 'uibutton'), 'Enable', e);
    end

    function setStatus(text, isError)
        if ~isvalid(fig), return; end
        statusLabel.Text = text;
        if isError, statusLabel.FontColor = ERROR_COLOR; else, statusLabel.FontColor = statusFg; end
    end

    function onClose()
        % The session is still using the window (and the Run callback is its caller).
        if running
            uialert(fig, ['A session is running. Wait for it to finish, or stop it with Ctrl+C ' ...
                          'in the MATLAB command window, then close this window.'], 'Session running');
            return;
        end
        delete(fig);
    end

    function onReset()
        % Re-read the file (picking up edits made since the window opened), keeping the tab.
        sel = '';
        if ~isempty(tabs.SelectedTab), sel = tabs.SelectedTab.Title; end
        buildForm(run_session_unified('defaults'));
        kids = tabs.Children;
        hit  = kids(strcmp({kids.Title}, sel));
        if ~isempty(hit), tabs.SelectedTab = hit(1); end
    end

    function t = sectionTitle(name)
        if isfield(SECTION_TITLES, name), t = SECTION_TITLES.(name); else, t = name; end
    end

    function browse(c, path)
        start = c.Value;
        if ~isfolder(start), start = pwd; end
        d = uigetdir(start, 'Choose folder');
        figure(fig);                        % the dialog can leave the window behind others
        if ischar(d), c.Value = d; refreshField(path); end
    end

end   % run_session_gui

%% ======================= LOCAL FUNCTIONS ================================

function tf = acceptsFit(g)
% True when this MATLAB takes 'fit' as a grid row height (R2019b on); R2019a rejects it.
old = g.RowHeight;
try
    g.RowHeight = repmat({'fit'}, size(old));
    tf = true;
catch
    tf = false;
end
g.RowHeight = old;
end

function pages = pageItems(items, maxRows)
% Split one section's rows over tabs of at most maxRows, for releases whose grid
% layouts cannot scroll. A nested struct's heading stays on the same tab as its
% settings; only a group longer than a whole tab is cut, into equal parts.
if isempty(items), pages = {items}; return; end
starts = unique([1, find([items.heading])]);
ends   = [starts(2:end) - 1, numel(items)];
pages  = {};
cur    = items([]);
for k = 1:numel(starts)
    grp = items(starts(k):ends(k));
    if ~isempty(cur) && numel(cur) + numel(grp) > maxRows
        pages{end + 1} = cur; %#ok<AGROW>
        cur = items([]);
    end
    while numel(grp) > maxRows
        n = ceil(numel(grp) / ceil(numel(grp) / maxRows));
        pages{end + 1} = grp(1:n); %#ok<AGROW>
        grp = grp(n + 1:end);
    end
    cur = [cur, grp]; %#ok<AGROW>
end
if ~isempty(cur), pages{end + 1} = cur; end
end

function [v, ok] = readField(f)
% The setting's value as entered, converted back to the type of its file default.
ok = true;
switch f.kind
    case 'numeric', [v, ok] = parseNumber(f.ctrl.Value, f.default);
    case 'cellstr', v = parseList(f.ctrl.Value, f.default);
    case 'fixed',   v = f.default;
    otherwise,      v = f.ctrl.Value;
end
end

function [v, ok] = parseNumber(txt, default)
% Numbers as MATLAB writes them: 90, [0 3000 3000], [88 88.5; 90 91], [0:11 14].
% Only digits and array punctuation get as far as str2num, so nothing typed here
% can run as code. A setting that is a single number in the file must stay one.
v = []; ok = false;
txt = strtrim(txt);
if isempty(txt)                       % before the regexp, which never matches ''
    ok = ~isscalar(default);          % clearing a list is fine; a single number cannot be blank
    return;
end
if isempty(regexp(txt, '^[-+\d\s.,;:\[\]eE]*$', 'once')), return; end
[v, ok] = str2num(txt);               % input already restricted to numeric syntax
if ok && isscalar(default) && ~isscalar(v), ok = false; end
if ok, v = cast(v, class(default)); end
end

function v = parseList(txt, default)
% 'a, b, c' -> {'a', 'b', 'c'}, oriented like the default.
v = strtrim(strsplit(txt, ','));
v = v(~cellfun(@isempty, v));
if size(default, 1) > 1, v = v(:); end
end

function tf = sameValue(a, b)
% Values, not text: 90 and 90.0 match. Any two empties match ('' vs 1x0 char, [] vs zeros(0, 2)).
tf = isequal(a, b) || (isempty(a) && isempty(b));
end

function logChanges(changed)
% What this session changed from the file. Printed when the session ends, because
% run_session_unified clears the command window as it starts.
if isempty(changed)
    fprintf('\nrun_session_gui: this session used the settings in run_session_unified.m unchanged.\n');
    return;
end
fprintf('\nrun_session_gui: this session changed %d setting(s) from run_session_unified.m:\n', size(changed, 1));
for k = 1:size(changed, 1)
    fprintf('  %s = %s\n', changed{k, 1}, valueText(changed{k, 2}));
end
end

function t = valueText(v)
% A value as it would be typed in MATLAB: 'text', 4, [0 3000], true, {'a', 'b'}.
if ischar(v)
    t = ['''' strrep(v, '''', '''''') ''''];
elseif islogical(v) && isscalar(v)
    if v, t = 'true'; else, t = 'false'; end
elseif iscellstr(v)
    t = ['{' strjoin(cellfun(@valueText, v, 'UniformOutput', false), ', ') '}'];
else
    t = mat2str(v);
end
end

function items = flatten(s, prefix)
% Rows for one settings section: its plain settings in file order, then a heading for
% each nested struct (basler.top, plotting.ch, ...) followed by that struct's rows.
% Nested structs go last so that no plain setting is ever listed under a heading
% (plotting.ch sits mid-section in the file, with plain settings after it).
items  = struct('heading', {}, 'name', {}, 'path', {}, 'value', {});
nested = items;
f = fieldnames(s);
for k = 1:numel(f)
    p = [prefix '.' f{k}];
    v = s.(f{k});
    if isstruct(v) && isscalar(v)
        nested(end + 1) = struct('heading', true, 'name', p(find(p == '.', 1) + 1:end), 'path', p, 'value', []); %#ok<AGROW>
        nested = [nested, flatten(v, p)]; %#ok<AGROW>
    else
        items(end + 1) = struct('heading', false, 'name', f{k}, 'path', p, 'value', {v}); %#ok<AGROW>
    end
end
items = [items, nested];
end

function t = toText(kind, v)
switch kind
    case 'char'
        t = v;
    case 'numeric'
        if isempty(v), t = '[]'; else, t = mat2str(double(v)); end
    case 'cellstr'
        t = strjoin(v, ', ');
    otherwise
        t = sprintf('(%s %s: edit in run_session_unified.m)', mat2str(size(v)), class(v));
end
end

function tips = settingComments()
% End-of-line comment of every assignment in the USER SETTINGS block, by setting path.
tips = containers.Map('KeyType', 'char', 'ValueType', 'char');
src = splitlines(fileread(which('run_session_unified')));
inBlock = false;
for k = 1:numel(src)
    ln = src{k};
    if ~inBlock
        inBlock = ~isempty(regexp(ln, '^\s*%%\s*=+\s*USER SETTINGS', 'once'));
        continue;
    end
    if ~isempty(regexp(ln, '^\s*%%\s*=+\s*END USER SETTINGS', 'once')), break; end
    tok = regexp(ln, '^\s*([A-Za-z]\w*(?:\.\w+)*)\s*=', 'tokens', 'once');
    if isempty(tok), continue; end
    c = commentOf(ln);
    if ~isempty(c), tips(tok{1}) = c; end
end
end

function c = commentOf(ln)
% Text after the first % outside a quoted string ('' when the line has none), so a
% value such as '50% power' is not mistaken for the start of the comment.
c = '';
nameEnd = ['A':'Z' 'a':'z' '0':'9' '_.)]}'''];   % a ' straight after one of these is a transpose
q = '';   % quote character of the string being scanned, '' when outside one
j = 1;
while j <= numel(ln)
    ch = ln(j);
    if ~isempty(q)
        if ch == q
            if j < numel(ln) && ln(j + 1) == q, j = j + 1;   % doubled quote inside the string
            else, q = ''; end
        end
    elseif ch == '%'
        c = strtrim(ln(j + 1:end));
        return;
    elseif ch == '"' || (ch == '''' && (j == 1 || ~any(ln(j - 1) == nameEnd)))
        q = ch;
    end
    j = j + 1;
end
end
