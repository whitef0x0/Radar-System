%the following should replace the while loop in extract_raw_data.m
clear all;clc
%load current version of dataLogger.py
clear classes
mod = py.importlib.import_module('dataLogger');   
py.importlib.reload(mod);
%%%%%%%%%%%%for testing purposes, delete later....%%%%%%%%%%%%%%%%%%%
[raw, label]=xlsread('test1b.csv');
Q = raw(2:2:end,:);                         
I = raw(1:2:end,:);
phasor_matrix = complex(I,Q);             %matrix of Q and I data combined into complex time domain data
num_of_frames = length(phasor_matrix(:,1));     %column length = number of frames
combined = []; 
samples_per_chirp = 64; 
num_of_chirps = 24; 
for frame_num = 1:num_of_frames 
    %frame = zeros(24, 63);
    %frame(1,:) = phasor_matrix(frame_num, 1:63); 
    %for i=2:num_of_chirps
    %frame = zeros(num_of_chirps-2, samples_per_chirp);   %don't include first and last chirp because for some they have only 63 samples, also first chirp is corrupted
    frame = zeros(num_of_chirps, samples_per_chirp-1);     %only add 63 data points for now until can fix data input
    frame(1,:) = phasor_matrix(frame_num, (samples_per_chirp:(samples_per_chirp*2-2)) );      
    for i=2:num_of_chirps                                                                    
        frame(i,:) = phasor_matrix( frame_num, ((i-1)*samples_per_chirp):((i-1)*samples_per_chirp + samples_per_chirp-2 ));
    end
    combined = [combined; frame]; 
    frame_index = 1; 
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

rawData = [];

chirps_per_frame = 4;
samples_per_chirp = 64; 
rangeFFT_length = 512; 
range_select = 0;  %which 'bin' to collect phase. if zero, then will autodetect
Ta = 0.25;          %aquisition time (time per frame)
plot_buffer_size = 2000;    %how many points to display on plot
plot_buffer = zeros(1,plot_buffer_size);   %circular buffer??, init with zeros
time_buffer = zeros(1,plot_buffer_size);   %circular buffer??
curr_time = 0.00;        %assumes that each plot point is aqcuired linearly according to aquistion time

%signal analyis
data_buffer_size = 2000; 
data_buffer = zeros(1, data_buffer_size);
data_time_buffer = zeros(1, data_buffer_size);
phaseFFT_length = 2048; %make sure this is > data_buffer_size and is a power of 2
polynum = 6;            %polynomial degree for detrending
min_distance = 0.5;     %rangeFFT will be truncated below this (to ignore low freq spikes)
Fs = 42666.0;           %sample rate (Hz)
Tc = 1500e-6;                   %chirp time in secs
c = 3e8;
BW = 200e6;             %bandwidth in Hz
plot_timer = 0; 
plot_toggle = false;
loop_time = 0; 

%python communication
python_buffer = zeros(1, chirps_per_frame); 

j=0; 
total_time = 0;
while true
%for count = 0:10
    tic;
    %for testing purposes%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    pause(0.25);
    four_frames = combined(frame_index:(frame_index+3) , :);
    frame_index = frame_index+4; 
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
%     % From infineon code - 3. Trigger radar chirp and get the raw data
%     [mxRawData, sInfo] = oRS.oEPRadarBase.get_frame_data;
%     ydata = mxRawData; % get raw data
%     rawData = [rawData, mxRawData];     %TODO note, make sure that the rawData is incrementing correctly (dimensions)
%     disp(ydata); %used to be disp(ydata');
    
    %TODO: format ydata into matrix, which each row is 1 chirp 
    %eg 4 chirps = 4 rows, 64 columns (64 samples_per_chirp)
    chirps_data = four_frames;   %replace four_frames with above formatted data
    for i = 1:chirps_per_frame
        rangeFFT = fft(chirps_data(i,:),rangeFFT_length,2);   %take FFT of single chirp
        rangeFFT = rangeFFT(1:(rangeFFT_length/2));
        phase = angle(rangeFFT);
        if range_select == 0
            range_min = round(min_distance/((Fs/(rangeFFT_length/2))*((c*Tc)/(4*BW))));
            [max_val, range_select] = max(rangeFFT(range_min:end)); 
            detected_distance = range_select*((Fs/(rangeFFT_length/2))*((c*Tc)/(4*BW)));
        end
        phase_point = phase(range_select);
        
%         time = datestr(now,'HH:MM:SS FFF');
%         dataString = sprintf('Time: %s Data: %f', time, phase_point);
%         try
%             loggedData = py.dataLogger.sendData(dataString)
%         catch
%             fprintf('Unable to connect to server.  Run test_server.py\n');
%         end

        python_buffer(i) = phase_point; 
        
        curr_time = curr_time + (Ta/chirps_per_frame);
        plot_buffer = [plot_buffer(2:end) phase_point];
        time_buffer = [time_buffer(2:end) curr_time]; 
        
        %signal analyis
        data_buffer = [data_buffer(2:end) phase_point];
        data_time_buffer = [data_time_buffer(2:end) curr_time]; 
    end
    
    % figure(1); %hold on
    % subplot(2,1,1);
    % plot(time_buffer, plot_buffer); 
    % title('Phase vs Time');
    % xlim([(curr_time - plot_buffer_size*(Ta/chirps_per_frame))  curr_time]);
    % %xticks(((curr_time - plot_buffer_size*(Ta/chirps_per_frame)):5:curr_time)); 
    % %TODO may need to also define y axis range with ylim[]
    % drawnow
    
    %signal analyis
    %code that calculates dominant frquency
    [p,s,mu] = polyfit(data_time_buffer,data_buffer,polynum);
    f_y = polyval(p,data_time_buffer,[],mu);
    detrended_data = data_buffer - f_y;
    %TODO: plot detrended??
    phaseFFT = abs(fft(detrended_data,phaseFFT_length));
    phaseFFT = phaseFFT(1:(phaseFFT_length/2));     %truncate last half
    %TODO am i losing info by truncating? should i be recombining somehow?
    [max_mag, max_freq] = max(phaseFFT);
    signal_freq = max_freq*((chirps_per_frame/Ta)/(phaseFFT_length/2));
    %calculate normalized magnitude
    phase_mean = mean(phaseFFT);
    phase_sd = std(phaseFFT);
    norm_max_mag = (max_mag - phase_mean)/phase_sd;
    
    time = datestr(now,'HH:MM:SS FFF');
    dateString = sprintf('Time: %s', time);
    try
        loggedData = py.dataLogger.sendData(dateString, signal_freq, norm_max_mag, python_buffer)
    catch
        fprintf('Unable to connect to server.  Run test_server.py\n');
    end
    %loggedData = py.dataLogger.sendData(dateString, signal_freq, python_buffer)
    
    % plot_timer = plot_timer+toc; 
    % if plot_timer >= 4
    %     plot_toggle = ~plot_toggle;
    %     plot_timer= 0;
    % end
    % if plot_toggle == true  
    %     subplot(2,1,2);
    %     axis_phaseFFT = (0:1:((phaseFFT_length/2)-1))*((chirps_per_frame/Ta)/(phaseFFT_length/2)); 
    %     plot(axis_phaseFFT, phaseFFT); 
    %     title(['Phase FFT, freq = ',num2str(signal_freq)]);
    %     xlim([0  3.5]);
    % else
    %     subplot(2,1,2);
    %     axis_rangeFFT = (0:1:((rangeFFT_length/2)-1))*(Fs/(rangeFFT_length/2))*((c*Tc)/(4*BW));
    %     plot(axis_rangeFFT, rangeFFT); 
    %     title(['Range FFT, dist = ',num2str(detected_distance)]);
    %     xlim([0  5]);
    % end
    % %annotation('textbox',[0 0 .1 .2],'String',['Looptime', num2str(loop_time)],'EdgeColor','none');  

    % j = j+1;
    % loop_time = toc
    % %toc
    % total_time = total_time + loop_time;
    % av_runtime = total_time/j
   
    
end