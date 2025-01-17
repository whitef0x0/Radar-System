%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% function out = extract_raw_data (in)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Copyright (c) 2014-2017, Infineon Technologies AG
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without modification,are permitted provided that the
% following conditions are met:
%
% Redistributions of source code must retain the above copyright notice, this list of conditions and the following
% disclaimer.
%
% Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
% disclaimer in the documentation and/or other materials provided with the distribution.
%
% Neither the name of the copyright holders nor the names of its contributors may be used to endorse or promote
% products derived from this software without specific prior written permission.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
% INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE  FOR ANY DIRECT, INDIRECT, INCIDENTAL,
% SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
% WHETHER IN CONTRACT, STRICT LIABILITY,OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DESCRIPTION:
% This simple example demos the acquisition of data.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% cleanup and init
% Before starting any kind of device the workspace must be cleared and the
% MATLAB Interface must be included into the code. 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clc
disp('******************************************************************');
addpath('..\..\RadarSystemImplementation'); % add Matlab API
clear all %#ok<CLSCR>
close all
resetRS; % close and delete ports

% 1. Create radar system object
szPort = findRSPort; % scan all available ports
oRS = RadarSystem(szPort); % setup object and connect to board

disp('Connected RadarSystem:');
oRS %#ok<*NOPTS>

% 2. Enable automatic trigger with frame time 1s
%oRS.oEPRadarBase.set_automatic_frame_trigger(1000000);  % in microsec?
%oRS.oEPRadarBase.set_automatic_frame_trigger(250000);
oRS.oEPRadarBase.set_automatic_frame_trigger(500000);
min_frame_interval = oRS.oEPRadarBase.min_frame_interval_us 

% Graden's additional settings below
%oRS.oEPRadarBase.set.num_samples_per_chirp(obj, val)
rawData = [];
chirps_per_frame = 48;
samples_per_chirp = 32; 
oRS.oEPRadarBase.stop_automatic_frame_trigger; % stop it to change values 
oRS.oEPRadarBase.num_chirps_per_frame = chirps_per_frame;   
oRS.oEPRadarBase.num_samples_per_chirp = samples_per_chirp; % can be [32, 64, 128, 256] 
chirps_data = zeros(chirps_per_frame, samples_per_chirp);    %each row is chirp
rangeFFT_length = 512; 
range_select = 20;  %which 'bin' to collect phase.if zero, then will autodetect
Ta = 0.5;          %aquisition time (time per frame)
plot_buffer_size = 1000;    %how many points to display on plot
plot_buffer = zeros(1,plot_buffer_size);   %circular buffer??, init with zeros
time_buffer = zeros(1,plot_buffer_size);   %circular buffer??
curr_time = 0.00        %assumes that each plot point is aqcuired linearly according to aquistion time



%signal analyis
data_buffer_size = 1000; 
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

j=0; 
total_time = 0;
while true
	tic;
	
    % 3. Trigger radar chirp and get the raw data
    [mxRawData, sInfo] = oRS.oEPRadarBase.get_frame_data;
    
    ydata = mxRawData; % get raw data
    
    rawData = [rawData, mxRawData];
    
    disp(ydata); %used to be disp(ydata');
    
    %TODO: mxRawData in form eg 64x1x4, so samples x frames? x chirps
    %eg mxRawData(:,:,1) is first chirp, in a column of 64 values
    for i = 1:chirps_per_frame
        chirps_data(i, :) = mxRawData(:, 1, i).';
        %plot(chirps_data(i,:)); 
        %drawnow
    end  
    %chirps_data = mxRawData(:, 1, :);   %replace four_frames with above formatted data
    %chirps_data = mxRawData.'; 
    for i = 1:chirps_per_frame
        rangeFFT = fft(chirps_data(i,:),rangeFFT_length,2);   %take FFT of single chirp
        rangeFFT = rangeFFT(1:(rangeFFT_length/2));
		if range_select == 0
            range_min = round(min_distance/((Fs/(rangeFFT_length/2))*((c*Tc)/(4*BW))));
            [max_val, range_select] = max(rangeFFT(range_min:end)); 
        end
        detected_distance = range_select*((Fs/(rangeFFT_length/2))*((c*Tc)/(4*BW)))
        
        phase = angle(rangeFFT);
        phase_point = phase(range_select); 
        curr_time = curr_time + (Ta/chirps_per_frame)
        plot_buffer = [plot_buffer(2:end) phase_point];
        time_buffer = [time_buffer(2:end) curr_time];  

		%signal analyis
        data_buffer = [data_buffer(2:end) phase_point];
        data_time_buffer = [data_time_buffer(2:end) curr_time]; 		
    end
    
	figure(1); 
    subplot(2,1,1);
    plot(time_buffer, plot_buffer); 
	title('Phase vs Time');
    xlim([(curr_time - plot_buffer_size*(Ta/chirps_per_frame))  curr_time]);
    %ylim( [-1  1]); 
    %xticks(((curr_time - plot_buffer_size*(Ta/chirps_per_frame)):5:curr_time)); 
    drawnow
	
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
    
	plot_timer = plot_timer+toc; 
    if plot_timer >= 4
        plot_toggle = ~plot_toggle;
        plot_timer= 0;
    end
    if plot_toggle == true  
        subplot(2,1,2);
        axis_phaseFFT = (0:1:((phaseFFT_length/2)-1))*((chirps_per_frame/Ta)/(phaseFFT_length/2)); 
        plot(axis_phaseFFT, phaseFFT); 
        title(['Phase FFT, freq = ',num2str(signal_freq)]);
        xlim([0  3.5]);
    else
        subplot(2,1,2);
        axis_rangeFFT = (0:1:((rangeFFT_length/2)-1))*(Fs/(rangeFFT_length/2))*((c*Tc)/(4*BW));
        plot(axis_rangeFFT, rangeFFT); 
        title(['Range FFT, dist = ',num2str(detected_distance)]);
        xlim([0  5]);
    end
    %annotation('textbox',[0 0 .1 .2],'String',['Looptime', num2str(loop_time)],'EdgeColor','none');  

    j = j+1;
    loop_time = toc
    %toc
    total_time = total_time + loop_time;
    av_runtime = total_time/j
	
end;