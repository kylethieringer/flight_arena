function tests = test_compress_video_h264
%TEST_COMPRESS_VIDEO_H264 Round trip: a Grayscale AVI as the Basler disk logger writes
% it -> ffmpeg -> mp4 that MATLAB reads back with the right frame count, size and
% orientation. Skipped where ffmpeg is not installed.
tests = functiontests(localfunctions);
end

function setup(testCase)
testCase.TestData.dir = tempname;
mkdir(testCase.TestData.dir);
end

function teardown(testCase)
rmdir(testCase.TestData.dir, 's');
end

%% -------------------------------------------------------------------------

function testEncodesEveryFrameAndRotatesClockwise(testCase)
raw = makeGrayAvi(testCase, 48, 64, 40);            % 48 rows x 64 cols, 40 frames
out = fullfile(testCase.TestData.dir, 'out.mp4');
opts = defaultOpts(testCase, 90);
info = compress_video_h264(raw, out, opts);
assertTrue(testCase, info.ok, sprintf('ffmpeg failed:\n%s\n%s', info.command, info.output));
verifyEqual(testCase, info.frames, 40, 'ffprobe must count every frame.');
verifyGreaterThan(testCase, info.bytes_out, 0);
verifyLessThan(testCase, info.bytes_out, info.bytes_in, 'H.264 must be smaller than the raw AVI.');
v = VideoReader(out);
frames = 0; first = [];
while hasFrame(v)
    f = readFrame(v);
    frames = frames + 1;
    if isempty(first), first = f; end
end
verifyEqual(testCase, frames, 40, 'MATLAB must read every frame back.');
verifyEqual(testCase, size(first, 1), 64, 'A 90 deg rotation makes the height the old width.');
verifyEqual(testCase, size(first, 2), 48);
% The source is a horizontal ramp, dark on the left. Rotated 90 deg clockwise, the
% dark (left) edge becomes the top edge.
top    = mean(double(first(1:4,   :, 1)), 'all');
bottom = mean(double(first(end-3:end, :, 1)), 'all');
verifyLessThan(testCase, top, bottom, 'Rotation must be clockwise: the dark left edge ends up on top.');
end

function testNoRotationKeepsTheFrameSize(testCase)
raw = makeGrayAvi(testCase, 48, 64, 10);
out = fullfile(testCase.TestData.dir, 'out.mp4');
info = compress_video_h264(raw, out, defaultOpts(testCase, 0));
assertTrue(testCase, info.ok, info.output);
v = VideoReader(out);
verifyEqual(testCase, [v.Height v.Width], [48 64]);
verifyEqual(testCase, info.rotate_deg_applied, 0);
end

function testFfmpegFailureIsReportedNotThrown(testCase)
% A bad preset makes ffmpeg exit non-zero: the caller must get ok = false and the
% message, so the raw file can be kept and the session finish.
raw = makeGrayAvi(testCase, 16, 16, 3);
out = fullfile(testCase.TestData.dir, 'out.mp4');
opts = defaultOpts(testCase, 0);
opts.preset = 'not_a_preset';
info = compress_video_h264(raw, out, opts);
verifyFalse(testCase, info.ok);
verifyNotEmpty(testCase, info.output);
end

function testMissingFfmpegErrors(testCase)
raw = makeGrayAvi(testCase, 16, 16, 3);
opts = defaultOpts(testCase, 0);
opts.ffmpeg = fullfile(testCase.TestData.dir, 'no_such_ffmpeg.exe');
verifyError(testCase, @() compress_video_h264(raw, fullfile(testCase.TestData.dir, 'o.mp4'), opts), ...
            'compress_video_h264:ffmpegNotFound');
end

function testMissingInputErrors(testCase)
opts = defaultOpts(testCase, 0);
verifyError(testCase, @() compress_video_h264(fullfile(testCase.TestData.dir, 'nope.avi'), ...
            fullfile(testCase.TestData.dir, 'o.mp4'), opts), 'compress_video_h264:noInput');
end

%% ---- helpers -------------------------------------------------------------

function opts = defaultOpts(testCase, rotate)
S = run_session_unified('defaults');
opts = S.basler.h264;
opts.rotate_deg = rotate;
if isempty(opts.ffmpeg) || exist(opts.ffmpeg, 'file') ~= 2
    [st, ~] = system('where ffmpeg');
    assumeEqual(testCase, st, 0, 'ffmpeg is not installed on this machine.');
end
end

function f = makeGrayAvi(testCase, h, w, n)
% What the disk logger produces: 8-bit grayscale, uncompressed. Content is a
% horizontal ramp (dark left, bright right) so orientation can be checked.
f = fullfile(testCase.TestData.dir, 'raw.avi');
vw = VideoWriter(f, 'Grayscale AVI');
vw.FrameRate = 200;
open(vw);
ramp = repmat(uint8(round(linspace(20, 235, w))), h, 1);
for k = 1:n
    writeVideo(vw, ramp);
end
close(vw);
end
