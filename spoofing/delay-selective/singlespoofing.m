%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%               ProcessGnssMeasScript.m,         %%%%%%%%%%%%%%%%
%%%%%%%%%%% script to read GnssLogger output, compute and plot: %%%%%%%%%%%
%%%%%%%% pseudoranges, C/No, and weighted least squares PVT solution  %%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Author: Frank van Diggelen
% Open Source code for processing Android GNSS Measurements
% Modified by Alex Minetto (NavSAS Research Group) 
% Last update: Alex Minetto & Simone Zocca 12-Oct-2021
% Last update: Andrea Nardin 19-Oct-2023
% Spoofing enhancement: Andrea Nardin 10-Mar-2024
% Custom Multi-Sat Spoofing Modification applied
% NOTE: Compatible with GNSSLogger App v2.0.0.1
% WARNING: CodeType breaks the code for logs retrieved by GNSSLogger App
% v3.0.0.1
% you can run the data in pseudoranges log files collected through your device by: 
% 1) changing 'dirName = ...' to match the local directory you are using:
% 3) running ProcessGnssMeasScript.m script file (this script) 
clc, close all, clear all
% include library functions (utilities and functions)
addpath('library')

% ***** SETTINGS *********************************************************
%% input data (GNSS logger)
% To add your own data:
% save data from GnssLogger App, and edit dirName and prFileName appropriately
prFileName    = 'aperto_a_2.txt';
dirName       = 'demoFiles/antani/';

%% true position
%param.llaTrueDegDegM = [45.01496, 7.43229, 600];
%enter true WGS84 lla, if you know it:
%param.llaTrueDegDegM = [37.422578, -122.081678, -28]; %Charleston Park Test Site
param.llaTrueDegDegM = [];

%% Spoofing settings
spoof.active = 1; % [1: spoofing active, 0: spoofing disabled]
spoof.target_prns = [32, 12, 6, 25, 11]; % NEW: Array of multiple satellites to spoof
spoof.delay_seconds = 1e-6; % NEW: ~30 meter delay. Small enough to fool the solver!

%% Plots
plotAccDeltaRange = 0;
plotPseudorangeRate = 1;
%********************* END SETTINGS ***************************************

%% Set the data filter and Read log file
dataFilter = SetDataFilter;
[gnssRaw,gnssAnalysis] = ReadGnssLogger(dirName,prFileName,dataFilter);
if isempty(gnssRaw), return, end

%% Get online ephemeris from Nasa CCDIS service, first compute UTC Time from gnssRaw:
fctSeconds = 1e-3*double(gnssRaw.allRxMillis(end));
utcTime = Gps2Utc([],fctSeconds);
allGpsEph = GetNasaHourlyEphemeris(utcTime,dirName);
if isempty(allGpsEph), return, end

%% process raw measurements, compute pseudoranges:
% Standard processing first
[gnssMeas] = ProcessGnssMeas(gnssRaw);

%% --- CUSTOM MULTI-SAT SPOOFING INJECTION ---
if spoof.active
    c = 299792458; % Speed of light (m/s)
    delay_meters = spoof.delay_seconds * c; 
    
    % Loop through each PRN in your target list
    for i = 1:length(spoof.target_prns)
        current_prn = spoof.target_prns(i);
        target_idx = find(gnssMeas.Svid == current_prn);
        
        % Inject the error directly into the pseudorange (PrM)
        if ~isempty(target_idx)
            gnssMeas.PrM(target_idx) = gnssMeas.PrM(target_idx) + delay_meters;
            disp(['[SPOOFING] Successfully added ', num2str(delay_meters), ' meters to PRN ', num2str(current_prn)]);
        else
            disp(['[WARNING] PRN ', num2str(current_prn), ' not found in measurements.']);
        end
    end
end
%% --------------------------------------------

%% plot pseudoranges and pseudorange rates
h1 = figure;
[colors] = PlotPseudoranges(gnssMeas,prFileName);
if plotPseudorangeRate
    h2 = figure;
    PlotPseudorangeRates(gnssMeas,prFileName,colors);
end
h3 = figure;
PlotCno(gnssMeas,prFileName,colors);

%% compute WLS position and velocity
% We pass an empty spoof struct here because we already spoofed the raw measurements above
dummy_spoof.active = 0; 
gpsPvt = GpsWlsPvt(gnssMeas,allGpsEph,dummy_spoof);

% compute median position
iFi = isfinite(gpsPvt.allLlaDegDegM(:,1));%index into finite results
llaMed = median(gpsPvt.allLlaDegDegM(iFi,:));

%% plot PVT results
h4 = figure;
ts = 'Raw Pseudoranges, Weighted Least Squares solution';
PlotPvt(gpsPvt,prFileName,param.llaTrueDegDegM,ts); drawnow;
h5 = figure;
PlotPvtStates(gpsPvt,prFileName);

%% Plot Accumulated Delta Range 
if (any(isfinite(gnssMeas.AdrM) & gnssMeas.AdrM~=0)) 
    [gnssMeas]= ProcessAdr(gnssMeas);
    if plotAccDeltaRange
    h6 = figure;
    PlotAdr(gnssMeas,prFileName,colors);
    [adrResid]= GpsAdrResiduals(gnssMeas,allGpsEph,param.llaTrueDegDegM);drawnow
    end
end
if exist('adrRedis','var') && ~isempty(adrResid)
    h7 = figure;
    PlotAdrResids(adrResid,gnssMeas,prFileName,colors);
end

%% plot PVT on geoplot
h8 = figure('Name','[Optional] Plot Positioning Solution on Map');
geoplot(gpsPvt.allLlaDegDegM(:,1),gpsPvt.allLlaDegDegM(:,2)), hold on
% animated geoplot
for epochIdx = 1:size(gpsPvt.allLlaDegDegM,1)
figure(h8)
geoplot(gpsPvt.allLlaDegDegM(epochIdx,1),gpsPvt.allLlaDegDegM(epochIdx,2),'ro','MarkerSize',4,'MarkerFaceColor','r') 
drawnow
pause(0.01)
end
%% end of ProcessGnssMeasScript