clear all;
Directory = 'F:\Sorted_Cortical';
reload_all =0;

Layer_bounds_width = [0 128 50 241 207 107 273]; % Layer thickness from Svoboda,Hooks and Sheperd, Barrel Cortex , Hanbook of brain microcircuits, OUP
Layer_bounds = [0 128 419 626 1006];

if (reload_all == 1)
    
prep_folders = dir(fullfile(Directory,'Sorted_Units'));
    prep_names      = {prep_folders([prep_folders.isdir]).name}; % Get directories only
    prep_names(ismember(prep_names, {'.' '..'})) = []; % remove . and ..
  
    for k = 1 : numel(prep_names);
  Date = prep_names{k};
  disp(Date)
 U = Unit_Classification(Directory,Date);
 if ~ isempty(U);
    if k == 1
    All_units = U;
    else
     All_units = [All_units;U]
     end;
    close all;
    end;
   end;
    save(fullfile(Directory,'All_units.mat'),'All_units');
else
    load(fullfile(Directory,'All_units.mat'));
end;


    Depth = All_units.Unit_Depth;
    Light_Drive = sum([All_units.Light_Drive_Rate All_units.Light_Drive_Prob],2)/2;
    Light_Drive(Light_Drive <1) = 0;
    Light_Flash = sum([All_units.Light_LEDFlash_Rate All_units.Light_LEDFlash_Prob],2)/2;
    Light_Flash(Light_Flash <1) = 0;
    Light_Timing = sum([All_units.Light_Timing_Rate All_units.Light_Timing_Prob],2)/2;
    Light_Timing(Light_Timing <1) = 0;
    
    Drive_Resp_Depths= Depth(Light_Drive ==1);
    Flash_Resp_Depths = Depth(Light_Flash ==1);
    Timing_Resp_Depths = Depth(Light_Timing ==1);
    Drive_nonResp_Depths= Depth(Light_Drive ==0);
    Flash_nonResp_Depths = Depth(Light_Flash ==0);
    Timing_nonResp_Depths = Depth(Light_Timing ==0);
    
    
    whisk_resp_drive = sum([All_units.Whisk_Drive_Rate All_units.Whisk_Drive_Prob],2)/2;
    whisk_resp_drive(whisk_resp_drive <1) = 0;
    
    whisk_resp_timing = sum([All_units.Whisk_Timing_Rate All_units.Whisk_Timing_Prob],2)/2;
    whisk_resp_timing(whisk_resp_timing <1) = 0;
    
    WDrive_Resp_Depths= Depth(whisk_resp_drive ==1);
    WTiming_Resp_Depths = Depth(whisk_resp_timing ==1);
    
    WDrive_nonResp_Depths= Depth(whisk_resp_drive ==0);
    WTiming_nonResp_Depths = Depth(whisk_resp_timing ==0);
    
    for k = 1 : numel(Light_Timing)
       Light_resp(k) = (Light_Drive(k) ==1) || (Light_Flash(k) ==1) || (Light_Timing(k) ==1);
       Whisk_resp(k) = (whisk_resp_drive(k) ==1) || (whisk_resp_timing(k) ==1);
    end;
    
    Light_count = nansum(Light_resp);
    Light_noncount = numel(Light_Timing)-Light_count;
    
    Whisk_count = nansum(Whisk_resp);
    Whisk_noncount = numel(Light_Timing)-Whisk_count;
    
    Light_Depth_All = Depth(Light_resp ==1);
    nonLight_Depth_All = Depth(~(Light_resp ==1));
    
    Whisk_Depth_All = Depth(Whisk_resp ==1);
    nonWhisk_Depth_All = Depth(~(Whisk_resp ==1));
    
    
    ha = figure();
    subplot(3,1,1);
    plot(Light_Drive,Depth,'b*');
    title('Light response drive');
    xlim([-0.5 1.5])
    set(gca,'Ydir','reverse')
    
    subplot(3,1,2);
    plot(Light_Flash,Depth,'b*');
     title('Light response flash');
      xlim([-0.5 1.5])
    set(gca,'Ydir','reverse')
       
    
    subplot(3,1,3);
    plot(Light_Timing,Depth,'b*');
    xlim([-0.5 1.5])
    set(gca,'Ydir','reverse')
     title('Light response timing');  
        
    ha = figure();
    subplot(2,1,1);
    plot(whisk_resp_drive,Depth,'b*');
    title('Whisk response Drive');
    xlim([-0.5 1.5])
    set(gca,'Ydir','reverse');
    
    
    subplot(2,1,2);
    plot(whisk_resp_timing,Depth,'b*');
    title('Whisk response timing');
    xlim([-0.5 1.5])
    set(gca,'Ydir','reverse')
    
    hist_edges = [Layer_bounds];
    
    figure();
    subplot(3,1,1);
    hold on;
    histogram(Drive_Resp_Depths,hist_edges);
    histogram(Drive_nonResp_Depths,hist_edges);
    title('Drive Response');
    
    subplot(3,1,2);
    hold on;
    histogram(Flash_Resp_Depths,hist_edges);
    histogram(Flash_nonResp_Depths,hist_edges);
    
    title('Flash Response');
    
    subplot(3,1,3);
    hold on;
    histogram(Timing_Resp_Depths,hist_edges);
    histogram(Timing_nonResp_Depths,hist_edges);
    title('Timing Response');
    
    
    ha = figure();
    subplot(2,1,1);
    hold on;
     histogram(WDrive_Resp_Depths,hist_edges);
     histogram(WDrive_nonResp_Depths,hist_edges);
      title('Whisk response Drive');
    
    
    subplot(2,1,2);
     hold on;
     histogram(WTiming_Resp_Depths,hist_edges);
     histogram(WTiming_nonResp_Depths,hist_edges);
    title('Whisk response timing');
    