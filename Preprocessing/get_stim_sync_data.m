function [sync_data] = get_stim_sync_data(datafolder,metadata_info,trials_from_whisk, whisk_buffer, baseline_moving_window)
% function [sync_data] = get_stim_sync_data(DATAFOLDER,EVENTS_CHANS,TRIALS_FROM_WHISK, WHISK_BUFFER, BASELINE_MOVING_WINDOW)
% OR
% function [sync_data] = get_stim_sync_data(DATAFOLDER,METADATA_INFO)
% 
% Get the PulsePal stimulus synchronisation data for an openephys experiment; 
% trial onset and offset times, whisk stimulus on and offset, opto stimulus 
% on and offset, amplitudes, frequencies and durations, etc.
% (PulsePal sends these sync data to the openephys system via the I/O board)
% and the recording software stores them in the ADC channels
% 
% 
% SYNC_DATA:
% A struct with fairly self-explanatory field names;
% SYNC_DATA.conditions additionally provides the trial sync data organised 
% by the set of stimulus conditions.
% 
% 
% DATAFOLDER: Full path to a folder containing the raw openephys data for 
% this experiment (a set of '.continuous' files).
% 
% METADATA_INFO: A struct generated by the READ_METADATA function, containing
% a number of fields that are used to determine which TTL channels provide
% information about which stimuli, the resolution for splitting conditions,
% whether to reconstruct trials from whisker stim only, etc.
% 
% 
% Alternatively:
% 
% EVENTS_CHANS:
% a 4-element vector of input channel numbers in the following order:
% [TRIAL_CHAN STIM_ON_CHAN OPTO_CHAN STIM_NR_CHAN]
% TRIAL_CHAN: the ADC channel that keeps track of trials (high = trial);
% STIM_ON_CHAN: the ADC channel that keeps track of when the whisker stimulator is on (high = on);
% OPTO_CHAN: the ADC channel that keeps track of whether the opto stimulation (LED or LASER) is on (high = on);
% STIM_NR_CHAN: the ADC channel that keeps track of which stimulator is being used; 1 or 2.
% 
% 
% TRIALS_FROM_WHISK: When trial sync data is incomplete or unsatisfactory,
% determine 'trials' based on a period of time around the whisker stimulus,
% the period of time is set by WHISK_BUFFER.
% If trial_chan == 0 the script will default to TRIALS_FROM_WHISK == 1;
% 
% 
% WHISK_BUFFER: If TRIALS_FROM_WHISK == true, then the script will generate
% trials that start at whisk_onset - WHISK_BUFFER and last until whisk_onset
% + WHISK_BUFFER. Whisk_buffer is also used to determine whether consecutive
% whisks should be considered part of the same burst within a trial, or whether 
% they should constitute a new trial;
% if inter-whisk_interval > whisk_buffer --> new trial.
% 
% BASELINE_MOVING_WINDOW: if specified, baseline is fixed using this moving 
% minimum window (in ms) for fixing baseline.
% 

if ~exist('baseline_moving_window','var')
    baseline_moving_window = 10020; % Default to 10020 ms to capture the maximum opto stimulus length (10s)
end

% Do we get events_channels only? Or an actual struct pre-populated with metadata information
% as produced by READ_METADATA?
if ~isstruct(metadata_info)
    events_chans            = metadata_info;
    % Unpack 
    trial_input_nr          = events_chans(1);         % Which input channel has the trial TTL
    stim_input_nr           = events_chans(2);         % Which input channel has the stim / whisk TTL
    opto_input_nr       	= events_chans(3);           % Which input channel has the LED TTL
    switch_input_nr         = events_chans(4);  	% Which input channel switches between stimulators?
    
    if nargin < 3
        trials_from_whisk   = false;
    end
    if nargin < 4
        whisk_buffer        = 'auto'; % default is to collect 2 secs from the onset of whisk stimulus
    end
    
    % Hardcoded defaults
    opto_conditions_res   	= 5;    % resolution in ms for automatically extracting conditions from LED delays
    whisk_conditions_res    = 10;  % resolution in ms for automatically extracting conditions from whisker delays
    
else
    trial_input_nr          = metadata_info.trial_channel;          % Which input channel has the trial TTL
    stim_input_nr           = metadata_info.whisk_channel;          % Which input channel has the stim / whisk TTL
    opto_input_nr       	= metadata_info.LED_channel;            % Which input channel has the LED TTL
    switch_input_nr         = metadata_info.stim_switch_channel;  	% Which input channel switches between stimulators?
    
    trials_from_whisk       = metadata_info.trials_from_whisk;
    whisk_buffer            = metadata_info.whisk_buffer;
    
    opto_conditions_res   	= metadata_info.LED_conditions_res;    % resolution in ms for automatically extracting conditions from LED delays
    whisk_conditions_res    = metadata_info.whisk_conditions_res;  % resolution in ms for automatically extracting conditions from whisker delays
    
end

min_whisk_buffer        = 2;


%% /!\ WARNING - SOME HARDCODED VOLTAGE THRESHOLDS /!\

if switch_input_nr ~= 0
    trial_threshold     = 0.25; % For trial, signal goes up to 2.5V or less
    stim_threshold      = 2.7; % For whisking (always during trial), signal goes up to 2.75 - 5V
    opto_threshold    	= 0.0425; % LED is no longer TTL, voltage varies with power (with 5V representing max); 0.05V thresh will detect events above ~1% max power
    switch_threshold    = 2.5; % normal TTL logic - 0 to 5V
else
    trial_threshold     = 0.25; % normal TTL logic - 0 to 5V
    stim_threshold      = 2.5; % normal TTL logic - 0 to 5V
    opto_threshold    	= 0.0425; % LED is no longer TTL, voltage varies with power (with 5V representing max); 0.05V thresh will detect events above ~1% max power
    switch_threshold    = 2.5; % normal TTL logic - 0 to 5V
end

adc_channel_nrs        	= [trial_input_nr stim_input_nr opto_input_nr switch_input_nr];
adc_channel_thresholds 	= [trial_threshold stim_threshold opto_threshold switch_threshold];

if adc_channel_nrs(1) == 0
    trials_from_whisk = 1;
end
if trials_from_whisk
    adc_channel_nrs(1) = 0;
end

%% Some code to find file prefix for data and sync files

data_files 	= dir(fullfile(datafolder,'*.continuous'));
data_files	= {data_files.name}';

is_adc_file = ~cellfun(@isempty,regexp(data_files,'ADC')); % Remove ADC files

chan_files  = data_files(is_adc_file); %
chan_inds   = cell2mat(regexp(data_files,'CH')); % find index of occurrence of 'CH'

chan_ind    = chan_inds(1) - 1; % We only need to look at the prefix for one file
chan_file   = chan_files{1}; %

data_prefix = chan_file(1:chan_ind);

%% 
for a = 1:length(adc_channel_nrs) % loop through the analog input channels
    
    if a == 1 && trials_from_whisk
        continue
    end
    
    if a == 1 || adc_channel_nrs(a) ~= adc_channel_nrs(a-1) % Don't reload data if trace is already loaded
        disp(['Loading ADC input channel ' num2str(adc_channel_nrs(a))])
        disp(['File ' datafolder filesep data_prefix 'ADC' num2str(adc_channel_nrs(a)) '.continuous'])
        [thisTTL timestamps info] = load_open_ephys_data([datafolder filesep data_prefix 'ADC' num2str(adc_channel_nrs(a)) '.continuous']);
        
        %% Special case for fixing baseline of LED input channel:
        if a == 3

            % Moving minimum based on LED conditions res.
            % Operates on resampled 'thisTTL' with 1 sample per 10ms; if
            % vector left in original length this operation takes too long.
            moving_TTL_min  = movmin(thisTTL(1:30:end),baseline_moving_window); 
            
            % smooth transitions with window
            smooth_TTL_min  = smooth(moving_TTL_min,7);
            smooth_TTL_min  = [smooth_TTL_min(:); smooth_TTL_min(end)]; % make sure this vector when resampled will be longer than thisTTL
            
            % bring back to full 30kHz sample rate
            resamp_smooth_TTL_min   = resample(smooth_TTL_min,30,1);
            
            % Correct original TTL
            corr_TTL        = thisTTL - resamp_smooth_TTL_min(1:length(thisTTL));
            
            baseline_wobble = range(smooth_TTL_min);
            
            if baseline_wobble < 0.025 % = up to 05%
                disp(['Baseline stable (' num2str(baseline_wobble/0.05) '% baseline wobble using ' num2str(baseline_moving_window) 'ms moving minimum)'])
            elseif baseline_wobble < 0.05 % = up to 1%
              	beep
                warning(['Minor baseline instability (' num2str(baseline_wobble/0.05) '% baseline wobble using ' num2str(baseline_moving_window) 'ms moving minimum)'])
                disp(['Adjusting minimum threshold for event detection to 1.5% of range'])
                adc_channel_thresholds(a) = 0.075;
            elseif baseline_wobble < 0.1 % = up to 2%
                beep
                warning(['Moderate baseline instability (' num2str(baseline_wobble/0.05) '% baseline wobble using ' num2str(baseline_moving_window) 'ms moving minimum)'])
                disp(['Adjusting minimum threshold for event detection to 3 % of range'])
                adc_channel_thresholds(a) = 0.15;
            elseif baseline_wobble < 0.25 % = up to 5%
                beep
                warning(['High baseline instability (' num2str(baseline_wobble/0.05) '% baseline wobble using ' num2str(baseline_moving_window) 'ms moving minimum)'])
                disp(['Adjusting minimum threshold for event detection to 7.5% of range'])
                adc_channel_thresholds(a) = 0.375;
            elseif baseline_wobble > 0.25
                beep
                warning(['Severe baseline instability (' num2str(baseline_wobble/0.05) '% baseline wobble using ' num2str(baseline_moving_window) 'ms moving minimum)'])
                disp(['Make sure to check baseline moving minimum window'])
                disp(['Adjusting minimum threshold for event detection to 10% of range'])
                adc_channel_thresholds(a) = 0.5;
            end
            
%             % Uncomment For debugging
%             figure
%             plot(thisTTL(1:100:end),'k-','LineWidth',2)
%             hold on
%             plot(corr_TTL(1:100:end),'b-')
%             plot(resamp_smooth_TTL_min(1:100:end),'c-')
%             plot([0 length(thisTTL)/100], [adc_channel_thresholds(a) adc_channel_thresholds(a)],'r-')
%             keyboard
%             % end debugging code
            
            % Apply moving minimum correction
            thisTTL         = corr_TTL;
        end
        starttime       = min(timestamps);              % find start time
        endtime         = max(timestamps);              % find end time
        timestamps      = (1:length(thisTTL)) / 30000;  % manually create new timestamps at 30kHz, openephys sometimes suffers from timestamp wobble even though data acquisition is spot on
        timestamps      = timestamps + starttime;       % add start time to the newly created set of timestamps
        
    end
    
    thisTTL_bool   	= thisTTL > adc_channel_thresholds(a); % find where the TTL signal is 'high'
    
    start_inds      = find(diff(thisTTL_bool) > 0.5);   % find instances where the TTL goes from low to high
    end_inds        = find(diff(thisTTL_bool) < -0.5);  % find instances where the TTL goes from high to low
    
    if ~isempty(start_inds) % Some channels may not have events (e.g. stim switch channel if only 1 stimulator used)
        end_inds(end_inds < start_inds(1))       = []; % discard potential initial end without start
        start_inds(start_inds > end_inds(end))   = []; % discard potential final start without end
    end
    
    start_times 	= timestamps(start_inds);   % find the timestamps of start events
    end_times    	= timestamps(end_inds);     % find the timestamps of end events
    
    switch a % this determines what the start and end timestamps should be assigned to: trial/trial, LED/opto stim or stim/whisk stim.
        case 1
            trial_starts    = start_times(:);
            trial_ends      = end_times(:);
        case 2
            stim_starts 	= start_times(:);
            stim_ends     	= end_times(:);
            
            % Determine stimulus amplitude from signal
            stim_amps       = NaN(size(start_inds));
            for i = 1:length(start_inds)
                stim_segment    = thisTTL(start_inds(i):end_inds(i));
                stim_amps(i)   	= ((median(stim_segment) - 2.5) / 2.5) * 100; % Stimulus amplitude in % of max
            end
        case 3
            opto_starts      = start_times(:);
            opto_ends        = end_times(:);
            
            opto_powers      = NaN(size(start_inds));
            for i = 1:length(start_inds)
                stim_segment    = thisTTL(start_inds(i):end_inds(i));
                opto_powers(i) 	= median(stim_segment) / 5 * 100; % Stimulus amplitude in % of max
            end
            
        case 4
            switch_up       = start_times(:);
            switch_down     = end_times(:);
    end
end

%% Determine trials from whisker stim?
if ischar(whisk_buffer) && strcmpi(whisk_buffer, 'auto')
    whisk_buffer    = min_whisk_buffer;
    auto_buff       = true;
else
    auto_buff       = false;
end

if trials_from_whisk
    % We are setting trial starts and ends based on the whisker stimulus;
    % discard previous trial data
    trial_starts    = [];
    trial_counter   = 1;
    for a = 1:length(stim_starts)
        this_stim_start = stim_starts(a);
        if a == 1
            % first stimulus, so this will set the first trial start (= this_stim_start - whisk_buffer)
            trial_starts(trial_counter) = this_stim_start - whisk_buffer;
            trial_counter   = trial_counter + 1; % keep track of which trial we are on
            continue
        elseif (stim_starts(a) - whisk_buffer) <= stim_starts(a-1)
            % the interval between this stim start and the previous one is
            % too small for them to have happened in different trials;
            % don't increment trial number, and investigate next stim start
            % time
            continue
        elseif (stim_starts(a) - whisk_buffer) > stim_starts(a-1)
            % interval between this stim start and the previous one is
            % large and so this stimulus is happening in a new trial;
            % set new trial start, and increment trial counter
            trial_starts(trial_counter) = this_stim_start - whisk_buffer;
            trial_counter = trial_counter + 1;
        end
    end
    
    if auto_buff
        % If no whisk_buffer has been specified, use distance between subsequent trials to set trial_length
        trial_spacing 	= round(mean(diff(trial_starts)));
        trial_length    = trial_spacing - 1;
        pre_whisk       = trial_length / 2; % if trial_length is uneven, have fewer seconds before than after whisk
        post_whisk      = trial_length / 2; % see above
        
        corr_starts  	= trial_starts + whisk_buffer; % add min_whisk_buffer again to recover the onset of the first stimulus for each trial
        trial_starts 	= corr_starts - pre_whisk; 
        trial_ends      = corr_starts + post_whisk;
    else
        trial_ends      = trial_starts + 2 * whisk_buffer;
    end
    
end

%% A lot of cleanup and repair from here

if isempty(stim_starts)
    stim_starts = [0 0.02];
    stim_ends   = [0.01 00.03]; % set some fake whisk stimuli outside of the trials to avoid empty vars 
    stim_amps   = [1 1];
end

% determine median trial length
trial_times     = trial_ends - trial_starts;
trial_length    = round(median(trial_times),1);

total_length 	= round(median(diff(trial_starts)),1);
trial_gap       = median(trial_starts(2:end)-trial_ends(1:end-1));

%% Work out the velocity (length) of a whisk, and the frequency of a whisker stimulus burst

% Find which whisking onsets are the first of a trial, and which onsets
% are the last of a trial
allwhisk_firstvect          = stim_starts(find(diff(stim_starts) > (trial_length/2))+1);
allwhisk_lastvect           = stim_starts(find(diff(stim_starts) > (trial_length/2)));

first_stim_amps             = stim_amps(find(diff(stim_starts) > (trial_length/2))+1);
first_stim_amps             = [stim_amps(1); first_stim_amps(:)];

whisk_starts            	= [stim_starts(1); allwhisk_firstvect(:)];
whisk_lasts              	= [allwhisk_lastvect(:); stim_starts(end)];

whisk_ends               	= stim_ends(find(diff(stim_starts) > (trial_length/2))+1);
whisk_ends                	= [stim_ends(1); whisk_ends(:)];

whisk_lengths              	= whisk_ends - whisk_starts;
whisk_freqs              	= NaN(size(whisk_starts));

for a = 1:length(whisk_starts)
    this_whisk_start    = whisk_starts(a);
    this_whisk_end      = whisk_lasts(a);
    q_whisks            = stim_starts > this_whisk_start & stim_starts < this_whisk_end;
    
    this_whisk_freq   	= mean(round(1./diff(stim_starts(q_whisks))));
    if isempty(this_whisk_freq)
        this_whisk_freq = 99;
    elseif isnan(this_whisk_freq)
        this_whisk_freq = 99;
    end
    whisk_freqs(a)      = this_whisk_freq;
end

stim_starts             = whisk_starts;
stim_amps               = first_stim_amps;

%% Build multiple opto stim capacity here
%% opto burst
if isempty(opto_starts)
    opto_starts = [0 0.02];
    opto_ends   = [0.01 00.03]; % set some fake opto stimuli outside of the trials
    opto_powers = [1 1];
end

% Find instances where the difference between a previous and next stimulus 
% is more than 1/4 trial length; this should be where one trial ends and the
% next one begins
first_opto_inds             = find(diff(opto_starts) > trial_gap)+1;
last_opto_inds              = find(diff(opto_starts) > trial_gap);

% make sure to include the first onset and the last offset, which will not 
% be captured by the diff criterion (no gap before the start, no gap after
% the end)
first_opto_inds             = [1; first_opto_inds];
last_opto_inds              = [last_opto_inds; length(opto_starts)];

if ~isempty(first_opto_inds)
    opto_firsts                 = opto_starts(first_opto_inds);
    opto_lasts                  = opto_ends(last_opto_inds);
    
    opto_first_amps             = opto_powers(first_opto_inds);
    opto_last_amps              = opto_powers(last_opto_inds);
    opto_amps                   = max(opto_first_amps,opto_last_amps);
    
else
    opto_firsts                 = [];
    opto_lasts                  = [];
    
    opto_burst_ends             = opto_ends;
end

opto_freqs                      = NaN(size(opto_starts));

for a = 1:length(opto_firsts)
    this_opto_first     = opto_firsts(a);
    this_opto_last   	= opto_lasts(a);
    
    q_opto_burst        = opto_starts > this_opto_first & opto_starts < this_opto_last;
    
    this_opto_freq   	= mean(round(1./diff(opto_starts(q_opto_burst))));
    if isempty(this_opto_freq)
        this_opto_freq  = 99;
    elseif isnan(this_opto_freq)
        this_opto_freq  = 99;
    end
    
    opto_freqs(a)      = this_opto_freq;
    
end


%% Match events to trials
ntrials                 = length(trial_starts);

whisk_stim_onsets       = NaN(size(trial_starts));
whisk_stim_lengths      = NaN(size(trial_starts));
whisk_stim_freqs        = NaN(size(trial_starts));
whisk_stim_relay        = NaN(size(trial_starts));
whisk_stim_amplitudes   = NaN(size(trial_starts));

opto_onsets             = NaN(size(trial_starts));
opto_offsets        	= NaN(size(trial_starts));
opto_current_levels   	= NaN(size(trial_starts));
opto_freq               = NaN(size(trial_starts));

for a = 1:ntrials
    this_trial_start    = trial_starts(a);
    this_trial_end      = trial_ends(a);
    
    % see whether there was a whisker stimulus
    select_whisk_start 	= whisk_starts >= this_trial_start & whisk_starts <= this_trial_end;
    
    if sum(select_whisk_start) > 0
        if sum(select_whisk_start) > 1
            beep
            warning('Multiple whisker stimulus values found for this trial')
            
            first_whisk_start_ind                       = find(select_whisk_start,1);
            select_whisk_start                          = false(size(select_whisk_start));
            select_whisk_start(first_whisk_start_ind)   = true;
        end
        
        whisk_stim_onsets(a)            = stim_starts(select_whisk_start);
        whisk_stim_lengths(a)       = whisk_lengths(select_whisk_start);
        whisk_stim_freqs(a)         = whisk_freqs(select_whisk_start);
        whisk_stim_amplitudes(a)    = stim_amps(select_whisk_start);
        
        % Determine which stimulator is being used (relay up = stim 2, relay down = stim 1)
        stim_start_mat_temp         = repmat(whisk_stim_onsets(a),size(switch_up));
        is_switch_up               	= stim_start_mat_temp > switch_up & stim_start_mat_temp < switch_down;
        
        if any(is_switch_up)
            whisk_stim_relay(a)     = 2;
        else
            whisk_stim_relay(a)     = 1;
        end
    end

    
    % see whether there was an LED on / offset here
    select_opto_start   = opto_firsts >= this_trial_start & opto_firsts <= this_trial_end;
    select_opto_end 	= opto_lasts >= this_trial_start & opto_lasts <= this_trial_end;
       
    if sum(select_opto_start) == 1 && sum(select_opto_end) == 1
        opto_onsets(a)           = opto_firsts(select_opto_start);
        opto_offsets(a)          = opto_lasts(select_opto_end);
        opto_current_levels(a)   = max([opto_amps(select_opto_start) opto_amps(select_opto_end)]);
        opto_freq(a)             = opto_freqs(select_opto_start);
    elseif sum(select_opto_start) > 1 || sum(select_opto_end) > 1
        warning('Multiple opto stimulus values found for this trial')
        opto_onsets(a)           = min(opto_firsts(select_opto_start));
        opto_offsets(a)          = max(opto_lasts(select_opto_end));
        opto_current_levels(a)   = max(opto_powers(select_opto_start));
    elseif sum(select_opto_start) ~= sum(select_opto_end)
        warning('Mismatch in number of detected opto onsets and offsets for this trial')
    end
    
end

%% Done with clean-up and event extraction; now determine the different conditions

% Find whisker stim lengths; make histogram of all stim length values, find
% the peaks in the histogram, and then get rid of jitter in timing data by 
% rounding everything to those peak values
binvec                      = [0:0.0001:2];
[pks, locs]                 = findpeaks(smooth(histc(whisk_stim_lengths,binvec),3),'MinPeakHeight',3);
length_vals                 = binvec(locs);
if numel(length_vals) == 1
    % a single whisker stimulation length; just grab median to remove jitter
    median_whisk_length     = nanmedian(whisk_lengths);
    whisk_stim_lengths   	= repmat(median_whisk_length,size(whisk_stim_lengths));
elseif numel(length_vals) == 0
    median_whisk_length     = NaN;
    whisk_stim_lengths   	= repmat(median_whisk_length,size(whisk_stim_lengths));
else
    % multiple stimulus velocities for this experiment; set each value to 
    % its nearest peak / 'local median' value to get rid of jitter
    whisk_stim_lengths          = interp1(length_vals,length_vals,whisk_stim_lengths,'nearest','extrap');
end

whisk_stim_amplitudes       = round(whisk_stim_amplitudes);     % round to nearest 1% to remove jitter


%% opto current level fixing -- make sure current levels are grouped together into different levels sensibly

opto_current_levels(isnan(opto_current_levels)) = 0; % Set NaN values (= no LED detected) to 0

% Cluster the range of values together and set each value to the mean of its 
% nearest cluster so we don't create spurious conditions
opto_current_levels     = contract_to_cluster_mean(opto_current_levels,20,'percentage');

opto_current_levels     = round(opto_current_levels); % round to nearest integer

%%

% recover LED delays
opto_delays                 = round((opto_onsets(:) - trial_starts(:)) / opto_conditions_res,3) * opto_conditions_res;

% recover whisking delays
whisk_delays                = round((whisk_stim_onsets(:) - trial_starts(:)) / whisk_conditions_res,3) * whisk_conditions_res;

% recover LED durations
opto_durations           	= opto_offsets - opto_onsets;
opto_durations              = round(opto_durations(:) / opto_conditions_res,3) * opto_conditions_res;

% reconstruct trial matrix
trial_conditions         	= [whisk_delays(:) whisk_stim_relay(:)  whisk_stim_amplitudes(:)  whisk_stim_freqs(:) round(1./whisk_stim_lengths(:)) opto_delays(:) opto_durations(:) opto_current_levels(:)];

trial_conditions(isnan(trial_conditions))   = 999; % pass numerical flag for missing values / absent stimuli, 'unique' doesn't work well with NaNs (NaN ~= NaN)

% extract different conditions from trial matrix
[conditions, cond_inds, cond_vect]          = unique(trial_conditions,'rows');

conditions(conditions == 999)               = NaN; % replace flag with NaN again so it is clear which stimuli are absent for certain conditions
trial_conditions(trial_conditions == 999)   = NaN;

%% We've got all the info; start constructing the output variable:

% Things that vary by condition
for a = 1:size(conditions,1)
    q_cond_trials                           = cond_vect == a; 
    sync_data.conditions(a).trial_starts  	= trial_starts(q_cond_trials);
    sync_data.conditions(a).trial_ends    	= trial_ends(q_cond_trials);
    
    sync_data.conditions(a).whisk_starts 	= whisk_stim_onsets(q_cond_trials);
    sync_data.conditions(a).opto_onsets  	= opto_onsets(q_cond_trials);
    sync_data.conditions(a).opto_offsets  	= opto_offsets(q_cond_trials);

    sync_data.conditions(a).whisk_onset   	= conditions(a,1);
    sync_data.conditions(a).whisk_stim_nr 	= conditions(a,2);
    sync_data.conditions(a).whisk_amp     	= conditions(a,3);
    sync_data.conditions(a).whisk_freq    	= conditions(a,4);
    sync_data.conditions(a).whisk_velocity	= conditions(a,5);
    
    sync_data.conditions(a).LED_onset    	= conditions(a,6);
    sync_data.conditions(a).LED_duration 	= conditions(a,7);
    sync_data.conditions(a).LED_power    	= conditions(a,8);
    
    sync_data.conditions(a).n_trials       	= sum(q_cond_trials);
end

% Things that are true across the entire experiment:
sync_data.data_folder     	= datafolder; % full file path to original raw data location
sync_data.rec_start_time  	= starttime;
sync_data.rec_end_time    	= endtime;
sync_data.rec_duration    	= endtime - starttime;
sync_data.trial_length   	= trial_length;
sync_data.trial_interval  	= total_length;
sync_data.block_length   	= total_length * length(conditions);
sync_data.protocol_duration = total_length * length(trial_starts);
sync_data.trial_starts      = trial_starts(:);
sync_data.trial_ends        = trial_ends(:);
sync_data.whisk_starts      = whisk_delays(:);
sync_data.whisk_stim_nr 	= whisk_stim_relay(:);
sync_data.whisk_amps        = whisk_stim_amplitudes(:);
sync_data.whisk_burst_freq  = whisk_freqs(:);
sync_data.whisk_veloc       = round(1./whisk_stim_lengths(:));
sync_data.opto_delays       = opto_delays(:);
sync_data.opto_durations    = opto_durations(:);
sync_data.opto_power        = opto_current_levels(:);

if isstruct(metadata_info)
    sync_data.parameters        = metadata_info;
end
