function sig = pulseTrain(nSamples, amplitude, Fs, frequency, dutyCycle)
%PULSETRAIN  One gated pulse burst -- the carrier kernel shared by the rig code.
%
%   SIG = PULSETRAIN(NSAMPLES, AMPLITUDE, FS, FREQUENCY, DUTYCYCLE) returns an
%   NSAMPLES x 1 column vector that equals AMPLITUDE while the carrier is on and
%   0 while it is off. The phase starts at 0, so a burst always begins with a
%   rising edge.
%
%   FREQUENCY of [] or 0 gives a continuous burst (every sample = AMPLITUDE);
%   DUTYCYCLE is then ignored.
%
%   WHY THE MODULAR FORM
%   A modular phase keeps the carrier rate exact on average even when the period
%   is not a whole number of samples. Building the burst by repeating a rounded
%   integer-length cycle instead slips the rate -- 300 Hz at 20 kHz becomes
%   round(66.67) = 67 samples, i.e. 298.51 Hz -- and loses a whole pulse every few
%   hundred cycles, while the saved metadata still claims 300 Hz.
%
%   The comparison is done as mod(n*f, Fs) < duty*Fs rather than the more obvious
%   mod(n*f/Fs, 1) < duty. With integer f and Fs the products stay exact integers
%   (well inside 2^53), so samples sitting exactly on the duty boundary fall the
%   same way every cycle. The divided form accumulates floating-point error: at
%   200 Hz / 20 kHz / duty 0.6 it drifts to 12148 on-samples per 20000 instead of
%   12000, because boundary samples intermittently round just under the threshold.
%
%   ERRORS
%     pulseTrain:invalidDutyCycle  DUTYCYCLE outside (0 1]
%     pulseTrain:frequencyTooHigh  FREQUENCY above Nyquist (FS/2)
%     pulseTrain:pulseTooShort     the on-phase is under one sample, which would
%                                  otherwise produce a silently all-zero burst
%
%   See also MAKESTIMTRAIN, RUN_SESSION_UNIFIED.

if nSamples <= 0
    sig = zeros(0, 1);
    return;
end

if isempty(frequency) || frequency == 0        % continuous: no carrier to gate with
    sig = amplitude * ones(nSamples, 1);
    return;
end

if dutyCycle <= 0 || dutyCycle > 1
    error('pulseTrain:invalidDutyCycle', ...
        'DutyCycle must be greater than 0 and at most 1 (got %g).', dutyCycle);
end
if frequency > Fs / 2
    error('pulseTrain:frequencyTooHigh', ...
        'Frequency (%g Hz) exceeds Nyquist (%g Hz) for Fs = %g Hz.', ...
        frequency, Fs / 2, Fs);
end
if dutyCycle * Fs / frequency < 1
    error('pulseTrain:pulseTooShort', ...
        ['A duty cycle of %g at %g Hz is only %.3g samples on at Fs = %g Hz. ' ...
         'Raise DutyCycle, lower Frequency, or raise Fs.'], ...
        dutyCycle, frequency, dutyCycle * Fs / frequency, Fs);
end

phase = mod((0:nSamples - 1)' * frequency, Fs);   % integer domain: exact for integer f, Fs
sig   = amplitude * (phase < dutyCycle * Fs);
end
