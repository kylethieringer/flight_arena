function h = session_overview(matFile, channels, opts)
% SESSION_OVERVIEW  Interactive viewer for the AI channels of a flight-arena session .mat.
%
% Plots the requested channels of Data (from run_session_unified.m, or a legacy
% run_session_*.m file) as stacked panels with a shared, linked time axis: zoom
% or pan in any panel (toolbar magnifier / hand, or scroll wheel) and all panels
% follow. Opto stimuli, the Phantom window and block boundaries are overlaid.
%
% USAGE
%   session_overview                          % file picker; channels from USER SETTINGS below
%   session_overview(matFile)                 % channels from USER SETTINGS
%   session_overview(matFile, channels)
%   session_overview(matFile, channels, opts)
%   h = session_overview(...)                 % figure / axes / line handles
%
% CHANNELS  (case-insensitive; see params.data_rows in the file for the names)
%   'all'                                     every AI channel, one panel each
%   {'WBF', 'WBA_left', 'LED_driver'}         one panel per name, in that order
%   {{'WBA_left', 'WBA_right'}, 'WBF'}        inner cell = overlay on one panel
%   {'AI2', 'AI3'}  or  [2 3]                 by NI AI channel number (needs params)
%   Legacy files without params expose WBA_left, WBA_right, WBF, LED_driver and
%   row<N> for the rest.
%
% OPTS (struct, all optional)
%   time_axis    'global' (default: blocks concatenated) | 'block' (within-block time)
%   xlim         [t0 t1] initial x range in seconds (default: everything)
%   decimate     keep every n-th sample for plotting (default 1 = none)
%   show_stims   overlay stimTable opto stimuli (default true)
%   show_phantom overlay the planned Phantom window / trigger (default true)
%   show_blocks  dotted line at each block start (default true)
%   dark         black background like the live session plot (default true)
%   fig_position [x y w h] in pixels
%   decode_y     overlay the decoded arena Y velocity (right axis) on any panel that
%                shows arena_y. true (default) = only when the file's visual mode is
%                'closed_loop_oscillating'; false = never; 'always' = regardless of
%                mode. The Y voltage steps through y_frames discrete levels
%                (10 V / y_frames apart) and wraps after the last one; the wraps are
%                unwrapped and the slope over y_vel_window_s gives the velocity in
%                frames/s.
%   y_frames     number of Y frames of the pattern (default 8, e.g. pattern 2)
%   y_vel_window_s  slope window for the velocity (default 0.5 s)
%
% EXAMPLES
%   session_overview('...\2026_0914_120000_test_Fly1_Trial1.mat', {'WBF', 'EMG'})
%   session_overview(f, 'all', struct('decimate', 10))
%   session_overview(f, {{'WBA_left', 'WBA_right'}, 'LED_driver'}, struct('xlim', [20 40]))
%
% Author: Yichen Luo, 2026-09

%% ======================= USER SETTINGS ==================================
dataFolder = ['H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\', ...
              'Spiracle\Flight_Arena_Data\'];
default_channels = {'LED_driver', 'WBF', {'WBA_left', 'WBA_right'}, 'EMG', {'arena_x', 'arena_y'}, ...
                    'basler_trigger', 'phantom_recording'};
default_opts = struct('time_axis', 'global', 'xlim', [], 'decimate', 1, 'show_stims', true, ...
                      'show_phantom', true, 'show_blocks', true, 'dark', true, ...
                      'fig_position', [60 60 1400 850], ...
                      'decode_y', true, 'y_frames', 8, 'y_vel_window_s', 0.5);
%% ===================== END USER SETTINGS ================================

if nargin < 1 || isempty(matFile)
    [f, p] = uigetfile('*.mat', 'Select a session .mat file', dataFolder);
    if isequal(f, 0), h = []; return; end
    matFile = fullfile(p, f);
end
matFile = char(matFile);                       % accept "double-quoted" strings as well as 'char'
if nargin < 2 || isempty(channels), channels = default_channels; end
if isstring(channels), channels = cellstr(channels); end
if nargin < 3 || isempty(opts), opts = struct(); end
fn = fieldnames(default_opts);
for i = 1:numel(fn)
    if ~isfield(opts, fn{i}), opts.(fn{i}) = default_opts.(fn{i}); end
end

%% ---------------- load ---------------------------------------------------
assert(exist(matFile, 'file') == 2, 'File not found: %s', matFile);
S = load(matFile);
assert(isfield(S, 'Data'), 'No "Data" variable in %s', matFile);
Data = S.Data;
nRows = size(Data, 1);
hasParams = isfield(S, 'params');
[~, fileTitle] = fileparts(matFile);

if isfield(S, 'variables') && isfield(S.variables, 'SampleRate'), fs = S.variables.SampleRate;
else, fs = 1 / median(diff(Data(1, 1:min(end, 1000)))); end
TrialLength = [];
if isfield(S, 'variables') && isfield(S.variables, 'TrialLength'), TrialLength = S.variables.TrialLength; end

% Row names: params.data_rows for unified files, historical layout otherwise.
rowNames = arrayfun(@(k) sprintf('row%d', k), 1:nRows, 'UniformOutput', false);
rowNames{1} = 'time_s';
aiNumbers = nan(1, nRows);                     % NI AI channel number per Data row
if hasParams && isfield(S.params, 'data_rows')
    n = min(nRows, numel(S.params.data_rows));
    rowNames(1:n) = S.params.data_rows(1:n);
    if isfield(S.params, 'acq') && isfield(S.params.acq, 'ai_channels')
        ai = S.params.acq.ai_channels;
        aiNumbers(2:1 + numel(ai)) = ai;
    end
else
    legacy = {2, 'WBA_left'; 3, 'WBA_right'; 4, 'WBF'; 7, 'LED_driver'};
    for i = 1:size(legacy, 1)
        if legacy{i, 1} <= nRows, rowNames{legacy{i, 1}} = legacy{i, 2}; end
    end
end

%% ---------------- time axis ---------------------------------------------
t = Data(1, :);
blockStart = [1, find(diff(t) < 0) + 1];       % within-block time resets at each block
nBlocks = numel(blockStart);
blockEnd = [blockStart(2:end) - 1, numel(t)];
offsets = zeros(1, nBlocks);
if strcmpi(opts.time_axis, 'global')
    for b = 2:nBlocks
        if ~isempty(TrialLength), offsets(b) = (b - 1) * TrialLength;
        else, offsets(b) = offsets(b - 1) + t(blockEnd(b - 1)) + 1 / fs; end
    end
    for b = 1:nBlocks, t(blockStart(b):blockEnd(b)) = t(blockStart(b):blockEnd(b)) + offsets(b); end
    xlab = 'Time (s)';
else
    xlab = 'Time within block (s)';
end

%% ---------------- arena Y velocity (decoded from the wrapping position) --
yRow = find(strcmpi(rowNames, 'arena_y'), 1);
yVel = [];                                     % frames/s, same length as t
visualMode = '';
if hasParams && isfield(S.params, 'visual') && isfield(S.params.visual, 'mode'), visualMode = S.params.visual.mode; end
if ischar(opts.decode_y) || isstring(opts.decode_y)
    doDecode = strcmpi(opts.decode_y, 'always');                       % force, regardless of visual mode
else
    doDecode = logical(opts.decode_y) && strcmpi(visualMode, 'closed_loop_oscillating');
end
if doDecode && ~isempty(yRow)
    yVel = nan(size(t));
    for b = 1:nBlocks                          % unwrap within each block; the arena restarts between blocks
        seg = blockStart(b):blockEnd(b);
        yVel(seg) = arenaYVelocity(Data(yRow, seg), fs, opts.y_frames, opts.y_vel_window_s);
    end
end

%% ---------------- resolve channels ---------------------------------------
if ischar(channels) && strcmpi(channels, 'all')
    channels = rowNames(2:end);
elseif ischar(channels)
    channels = {channels};
elseif isnumeric(channels)
    channels = num2cell(channels);
end
panels = cell(1, numel(channels));             % each entry: vector of Data rows
for i = 1:numel(channels)
    spec = channels{i};
    if isstring(spec), spec = cellstr(spec); end
    if ~iscell(spec), spec = {spec}; end
    rows = zeros(1, numel(spec));
    for j = 1:numel(spec)
        rows(j) = resolveRow(spec{j}, rowNames, aiNumbers);
    end
    panels{i} = rows;
end
nP = numel(panels);
assert(nP > 0, 'No channels requested.');

dec = max(1, round(opts.decimate));
idx = 1:dec:numel(t);

%% ---------------- overlays ------------------------------------------------
stimRows = zeros(0, 3);                        % [onset offset source] in plotted time
if opts.show_stims && isfield(S, 'stimTable') && ~isempty(S.stimTable)
    st = S.stimTable;
    cols = {'block', 'stim_idx', 'onset_s', 'offset_s', 'duration_ms', 'amplitude_V', ...
            'onset_global_s', 'source_1randomized_2window'};
    if hasParams && isfield(S.params, 'stimTable_columns'), cols = S.params.stimTable_columns; end
    cB = find(strcmp(cols, 'block'), 1); cOn = find(strcmp(cols, 'onset_s'), 1);
    cOff = find(strcmp(cols, 'offset_s'), 1); cD = find(strcmp(cols, 'duration_ms'), 1);
    cSrc = find(strncmp(cols, 'source', 6), 1);
    if isempty(cSrc), src = ones(size(st, 1), 1); else, src = st(:, cSrc); end
    for k = 1:size(st, 1)
        if ~isempty(cD) && st(k, cD) <= 0, continue; end          % sham
        b = st(k, cB);
        off = 0;
        if strcmpi(opts.time_axis, 'global') && b <= nBlocks, off = offsets(b); end
        stimRows(end + 1, :) = [st(k, cOn) + off, st(k, cOff) + off, src(k)]; %#ok<AGROW>
    end
end
phWin = zeros(0, 3);                           % [start end trigger] per recorded block
if opts.show_phantom && isfield(S, 'phantom') && isfield(S.phantom, 'enable') && S.phantom.enable ...
        && isfield(S.phantom, 'window_s')
    p = S.phantom;
    trig = p.window_s(2);
    if isfield(p, 'trigger_time_s'), trig = p.trigger_time_s; end
    if isfield(p, 'record_each_block') && p.record_each_block, recBlocks = 1:nBlocks;
    elseif isfield(p, 'block_to_record'), recBlocks = p.block_to_record;
    else, recBlocks = 1; end
    for b = recBlocks(recBlocks <= nBlocks)
        off = 0;
        if strcmpi(opts.time_axis, 'global'), off = offsets(b); end
        phWin(end + 1, :) = [p.window_s(1) + off, p.window_s(2) + off, trig + off]; %#ok<AGROW>
    end
end

%% ---------------- figure --------------------------------------------------
if opts.dark, bg = 'k'; fg = 'w'; else, bg = 'w'; fg = 'k'; end
lineColors = [0 0.5 1; 0.2 0.85 0.2; 1 0.3 0.3; 1 0.85 0.2; 0.85 0.4 1; 0.2 0.9 0.9; 0.85 0.85 0.85];
if ~opts.dark, lineColors(7, :) = [0.3 0.3 0.3]; end
stimColors = [1 0.196 0.353; 1 0.6 0.2];       % randomized = crimson, window = orange
phColor = [0.3 0.5 1];

h.fig = figure('Name', ['session_overview: ' fileTitle], 'NumberTitle', 'off', 'Color', bg, ...
               'Position', opts.fig_position, 'InvertHardcopy', 'off');
h.ax = gobjects(1, nP);
h.lines = cell(1, nP);
top = 0.93; bottom = 0.07; gap = 0.012;
ph = (top - bottom - gap * (nP - 1)) / nP;
for i = 1:nP
    ax = axes('Parent', h.fig, 'Position', [0.07, top - i * ph - (i - 1) * gap, 0.86, ph]);
    hold(ax, 'on');
    rows = panels{i};
    names = cell(1, numel(rows));
    hl = gobjects(1, numel(rows));
    for j = 1:numel(rows)
        hl(j) = plot(ax, t(idx), Data(rows(j), idx), 'Color', lineColors(mod(j - 1, size(lineColors, 1)) + 1, :), ...
                     'LineWidth', 0.8);
        names{j} = strrep(rowNames{rows(j)}, '_', ' ');
    end
    yl = ylim(ax);
    yl = yl + 0.05 * diff(yl) * [-1 1];
    if diff(yl) == 0, yl = yl + [-0.5 0.5]; end
    ylim(ax, yl);
    % overlays behind the traces
    for k = 1:size(stimRows, 1)
        pch = patch(ax, [stimRows(k, 1) stimRows(k, 2) stimRows(k, 2) stimRows(k, 1)], [yl(1) yl(1) yl(2) yl(2)], ...
                    stimColors(min(2, max(1, stimRows(k, 3))), :), 'FaceAlpha', 0.2, 'EdgeColor', 'none', ...
                    'HandleVisibility', 'off');
        uistack(pch, 'bottom');
    end
    for k = 1:size(phWin, 1)
        pch = patch(ax, [phWin(k, 1) phWin(k, 2) phWin(k, 2) phWin(k, 1)], [yl(1) yl(1) yl(2) yl(2)], phColor, ...
                    'FaceAlpha', 0.1, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        uistack(pch, 'bottom');
        plot(ax, phWin(k, 3) * [1 1], yl, '-.', 'Color', [0.6 0.7 1], 'HandleVisibility', 'off');
    end
    if opts.show_blocks && strcmpi(opts.time_axis, 'global')
        for b = 2:nBlocks
            plot(ax, t(blockStart(b)) * [1 1], yl, ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
        end
    end
    set(ax, 'Color', bg, 'XColor', fg, 'YColor', fg, 'FontSize', 8, 'Box', 'off', 'XGrid', 'on', ...
            'GridColor', [0.5 0.5 0.5], 'GridAlpha', 0.3);
    if numel(rows) == 1
        lab = names{1};
        if ~isnan(aiNumbers(rows)), lab = {lab, sprintf('(AI%d, V)', aiNumbers(rows))}; else, lab = [lab ' (V)']; end
        ylabel(ax, lab, 'Color', fg, 'FontSize', 8);
    else
        ylabel(ax, '(V)', 'Color', fg, 'FontSize', 8);
    end
    % decoded arena Y velocity on a right-hand axis of the same panel
    if ~isempty(yVel) && any(rows == yRow)
        velColor = [1 0.6 0.2];
        yyaxis(ax, 'right');
        hv = plot(ax, t(idx), yVel(idx), '-', 'Color', velColor, 'LineWidth', 1.2);
        vmax = max(abs(yVel(~isnan(yVel))));
        if isempty(vmax) || vmax == 0, vmax = 1; end
        ylim(ax, 1.1 * vmax * [-1 1]);
        set(ax, 'YColor', velColor);
        ylabel(ax, 'Y velocity (frames/s)', 'Color', velColor, 'FontSize', 8);
        yyaxis(ax, 'left');
        hl(end + 1) = hv; names{end + 1} = 'arena y velocity (decoded)';
    end
    if numel(hl) > 1
        legend(ax, hl, names, 'TextColor', fg, 'Color', bg, 'FontSize', 8, 'Location', 'northeast');
    end
    if i < nP, set(ax, 'XTickLabel', []); else, xlabel(ax, xlab, 'Color', fg); end
    h.ax(i) = ax; h.lines{i} = hl;
end
linkaxes(h.ax, 'x');
if ~isempty(opts.xlim), xlim(h.ax(1), opts.xlim); else, xlim(h.ax(1), [t(1) t(end)]); end
zoom(h.fig, 'xon'); pan(h.fig, 'xon');          % default tools zoom/pan in time only; switch to 'on' for y as well

ttl = fileTitle;
if hasParams && isfield(S.params, 'FlyType'), ttl = S.params.FlyType; end
sub = sprintf('%d block(s), %g Hz, %d samples', nBlocks, fs, numel(t));
if dec > 1, sub = sprintf('%s, plotted every %d-th sample', sub, dec); end
if ~isempty(stimRows), sub = [sub sprintf(', %d opto stim', size(stimRows, 1))]; end
sgtitle(h.fig, {ttl, sub}, 'Color', fg, 'Interpreter', 'none', 'FontSize', 9);

h.matFile = matFile; h.rowNames = rowNames; h.panels = panels; h.t = t;
fprintf('Loaded %s\n  rows: %s\n', matFile, strjoin(rowNames, ', '));
if nargout == 0, clear h; end
end

%% ======================= LOCAL FUNCTIONS ================================

function v = arenaYVelocity(y, fs, nFrames, win_s)
% Velocity (frames/s) decoded from the arena Y position voltage.
% The controller outputs 10 V * frame / nFrames, so the voltage steps through
% nFrames levels and wraps from the last frame back to the first. Steps of more
% than half a cycle are taken as wraps and undone; the velocity is the slope of
% the unwrapped frame count over a centred window of win_s seconds.
y = y(:)';
n = numel(y);
v = nan(1, n);
if n < 3, return; end
ys  = movmedian(y, max(3, 2 * round(fs / 1000) + 1));       % ~2 ms median: kills switching glitches
lvl = round(ys / (10 / nFrames));                            % frame index
d   = diff(lvl);
d(d < -nFrames / 2) = d(d < -nFrames / 2) + nFrames;         % wrap upwards (last frame -> first)
d(d >  nFrames / 2) = d(d >  nFrames / 2) - nFrames;         % wrap downwards
fu  = [lvl(1), lvl(1) + cumsum(d)];                          % unwrapped frame position
h   = max(1, round(win_s * fs / 2));
if n <= 2 * h, v(:) = (fu(end) - fu(1)) / ((n - 1) / fs); return; end
core = h + 1:n - h;
v(core) = (fu(core + h) - fu(core - h)) / (2 * h / fs);
v(1:h)         = v(h + 1);                                   % hold the edges
v(n - h + 1:n) = v(n - h);
end

function r = resolveRow(name, rowNames, aiNumbers)
% Data row for a channel given by name ('WBF'), row ('row5') or AI number ('AI2' / 2).
name = convertStringsToChars(name);
if isnumeric(name)
    r = find(aiNumbers == name, 1);
    assert(~isempty(r), 'AI%d is not recorded in this file (or the file has no params).', name);
    return;
end
r = find(strcmpi(rowNames, name), 1);
if isempty(r)
    tok = regexpi(name, '^AI(\d+)$', 'tokens', 'once');
    if ~isempty(tok), r = find(aiNumbers == str2double(tok{1}), 1); end
end
if isempty(r)
    tok = regexpi(name, '^row(\d+)$', 'tokens', 'once');
    if ~isempty(tok) && str2double(tok{1}) <= numel(rowNames), r = str2double(tok{1}); end
end
assert(~isempty(r), 'Channel "%s" not found. Available: %s', name, strjoin(rowNames(2:end), ', '));
assert(r > 1, 'Row 1 is the time base; choose an AI channel.');
end
