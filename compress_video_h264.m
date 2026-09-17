function info = compress_video_h264(rawFile, outFile, opts)
%COMPRESS_VIDEO_H264  Re-encode a video file to H.264 mp4 with ffmpeg, optionally rotating it.
%
%   info = compress_video_h264(rawFile, outFile, opts)
%
%   rawFile   input video (the uncompressed Grayscale AVI the Basler disk logger writes)
%   outFile   output .mp4; overwritten if it exists
%   opts      struct with fields
%       ffmpeg        full path of ffmpeg.exe, or '' / 'ffmpeg' for the one on PATH
%       crf           libx264 constant-rate factor (0 lossless, 18 visually lossless, 23 default)
%       preset        libx264 preset, e.g. 'veryfast'
%       pixel_format  'yuv420p' (plays everywhere) or 'gray'
%       rotate_deg    clockwise rotation to apply: 0, 90, 180 or 270
%
%   info.ok            true when ffmpeg exited 0 and the output exists
%   info.frames        frames in the output per ffprobe (NaN when ffprobe is unavailable)
%   info.seconds       encode wall time
%   info.bytes_in/out  file sizes
%   info.command       the argument list that was run, as one string
%   info.output        ffmpeg's console output (its last lines are the error when ok = false)
%   info.rotate_deg_applied
%
%   WHY FFMPEG
%   MATLAB's own encoders run inside the MATLAB process: on the rig PC the Motion JPEG
%   writer manages ~75-110 fps on the Basler frame sizes, against 200 fps x 2 cameras
%   during a session. Streaming uncompressed to a local NVMe (the engine keeps up with
%   a 2-3x margin) and compressing afterwards with ffmpeg on all cores (~15 s for
%   18000 frames of 800x600) keeps the encode off the acquisition thread.
%
%   The process is started through java.lang.ProcessBuilder rather than system(), so
%   paths with spaces need no cmd.exe quoting rules.
%
%   Errors: compress_video_h264:ffmpegNotFound, compress_video_h264:noInput.
%   ffmpeg failing is NOT an error -- it is reported in info.ok / info.output so the
%   caller can keep the raw file and carry on.
%
%   exe = compress_video_h264('which', ffmpegSetting) only resolves the ffmpeg path
%   (or raises compress_video_h264:ffmpegNotFound), for checks before a session starts.
%
%   See also RUN_SESSION_UNIFIED.

if nargin == 2 && strcmp(rawFile, 'which')
    info = resolve_ffmpeg(outFile);
    return;
end
assert(exist(rawFile, 'file') == 2, 'compress_video_h264:noInput', 'Input video %s does not exist.', rawFile);
exe = resolve_ffmpeg(opts.ffmpeg);

vf = {};
switch mod(opts.rotate_deg, 360)                 % transpose=1 is 90 deg clockwise
    case 0
    case 90,  vf{end + 1} = 'transpose=1';
    case 180, vf{end + 1} = 'transpose=1,transpose=1';
    case 270, vf{end + 1} = 'transpose=2';
    otherwise
        error('compress_video_h264:badRotation', 'rotate_deg must be 0, 90, 180 or 270 (got %g).', opts.rotate_deg);
end
if strcmpi(opts.pixel_format, 'yuv420p')
    vf{end + 1} = 'pad=ceil(iw/2)*2:ceil(ih/2)*2';   % 4:2:0 needs even dimensions
end

args = {exe, '-hide_banner', '-nostdin', '-loglevel', 'error', '-y', '-i', rawFile};
if ~isempty(vf), args = [args, {'-vf', strjoin(vf, ',')}]; end
args = [args, {'-c:v', 'libx264', '-preset', opts.preset, '-crf', num2str(opts.crf), ...
               '-pix_fmt', opts.pixel_format, '-movflags', '+faststart', outFile}];

info = struct('ok', false, 'frames', NaN, 'seconds', NaN, 'bytes_in', 0, 'bytes_out', 0, ...
              'command', strjoin(quoteIfSpace(args), ' '), 'output', '', ...
              'rotate_deg_applied', opts.rotate_deg, 'crf', opts.crf, 'preset', opts.preset, ...
              'pixel_format', opts.pixel_format, 'ffmpeg', exe);
d = dir(rawFile); info.bytes_in = d.bytes;

t = tic;
[status, out] = runProcess(args);
info.seconds = toc(t);
info.output  = out;
info.ok = (status == 0) && exist(outFile, 'file') == 2;
if ~info.ok, return; end
d = dir(outFile); info.bytes_out = d.bytes;

ffprobe = fullfile(fileparts(exe), 'ffprobe.exe');
if exist(ffprobe, 'file') == 2
    [st, txt] = runProcess({ffprobe, '-v', 'error', '-select_streams', 'v:0', ...
                            '-show_entries', 'stream=nb_frames', '-of', 'csv=p=0', outFile});
    n = str2double(strtrim(txt));
    if st == 0 && isfinite(n), info.frames = n; end
end
end

function exe = resolve_ffmpeg(setting)
% The configured ffmpeg.exe, or the first one on PATH when the setting is '' or a
% bare name. Errors, rather than returning a guess, when none can be found.
if ~isempty(setting) && exist(setting, 'file') == 2
    exe = setting;
    return;
end
if isempty(setting) || ~any(setting == '\' | setting == '/'), name = 'ffmpeg'; else, name = setting; end
[st, txt] = runProcess({'where.exe', name});
lines = strsplit(strtrim(txt), {'\r', '\n'});
lines = lines(~cellfun(@isempty, lines));
if st == 0 && ~isempty(lines) && exist(lines{1}, 'file') == 2
    exe = lines{1};
    return;
end
error('compress_video_h264:ffmpegNotFound', ...
      ['ffmpeg not found (setting: ''%s''). Install it (winget install Gyan.FFmpeg) or point ' ...
       'basler.h264.ffmpeg at ffmpeg.exe.'], setting);
end

function [status, out] = runProcess(args)
% Run an executable with an argument list and return its exit status and combined
% stdout/stderr. No shell is involved, so spaces in paths need no quoting.
pb = java.lang.ProcessBuilder(args);
pb.redirectErrorStream(true);
try
    p = pb.start();
catch ME
    status = -1; out = ME.message;
    return;
end
rd = java.io.BufferedReader(java.io.InputStreamReader(p.getInputStream()));
buf = {};
ln = rd.readLine();
while ~isempty(ln)                                   % null (end of stream) comes back as []
    buf{end + 1} = char(ln); %#ok<AGROW>
    ln = rd.readLine();
end
status = p.waitFor();
rd.close();
out = strjoin(buf, newline);
end

function q = quoteIfSpace(args)
q = args;
for k = 1:numel(q)
    if any(isspace(q{k})), q{k} = ['"' q{k} '"']; end
end
end
