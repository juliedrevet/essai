function [expe,aborted,errmsg] = run_expe(subj,session,fmri,expe_raw,start_blck)


addpath ./Toolboxes/Rand
addpath ./Toolboxes/IO
addpath ./Toolboxes/Stimuli/Visual
addpath ./Analysis

% check input arguments
if nargin < 2
    error('Missing subject number! Missing session number!');
elseif nargin == 2
    fmri     = false;
    expe_raw   = [];
    start_blck = 1;
elseif nargin == 3
    expe_raw   = [];
    start_blck = 1;
end
if ~isscalar(subj) || mod(subj,1) ~= 0
    error('Invalid subject number!');
end


%%
% create header
hdr = [];
hdr.subj    = subj;
hdr.session = session;
hdr.date    = datestr(now,'yyyymmdd-HHMM');

% create data folder for interim subject files
foldname = sprintf('./Data/S%02d',subj);
if ~exist(foldname,'dir')
    mkdir(foldname);
end

%% generate experiment for subject
if isempty(expe_raw)
    expe     = gen_expe(subj,session);
    expe.hdr = hdr;
    expe     = orderfields(expe,{'hdr','blck'});
    expe_raw       = expe;
    shape          = reshape(randperm(6),3,2);
    expe_raw.shape = shape;
    jitter_seq     = gen_jitters(subj,session,expe);
    
    % save raw expe structure in case of premature termination
    fname = sprintf('VOLNOISE_IRM_S%02d_session%d_%s_raw',subj,session,datestr(now,'yyyymmdd-HHMM'));
    fname = fullfile(foldname,fname);
    save([fname,'.mat'],'expe_raw');
else % in case of premature termination load raw expe struct already generated
    expe  = expe_raw;
    shape = expe.shape;
    expe = rmfield(expe,'shape');
    jitter_seq  = gen_jitters(subj,session,expe);
    for b = 1:(start_blck-1) % load already saved blocks in general expe struct
        partname = sprintf('VOLNOISE_IRM_S%02d_session%d_b%02d',subj,session,b);
        d = dir(sprintf('./Data/S%02d',subj));
        if isempty(d)
            error('no data can be imported!');
        end
        for i = 1:length(d)
            if strncmp(d(i).name,partname,length(partname))
                blck2merge   = importdata(fullfile(sprintf('./Data/S%02d',subj),d(i).name));
                expe.blck(b) = blck2merge.blck;
                expe.rslt(b) = blck2merge.rslt;
                expe.clck(b) = blck2merge.clck;
                expe.stim(b) = blck2merge.stim;
                expe.logi(b) = blck2merge.logi;
                break;
            end
        end
    end
end
%%

% define output arguments
aborted = false; % aborted prematurely?
errmsg  = [];    % error message

% set screen parameters
if fmri
    % CENIR fMRI configuration
    iscr     = 0;%1;
    res      = [];%[1024 768];
    fps      = [];%60;%
    ppd      = 33;%40;%53(prisma);
    syncflip = true; %?
else
    % default configuration for flat panel displays
    iscr = 0;  % screen index
    res  = []; % screen resolution
    fps  = []; % screen refresh rate
    ppd  = 40; % number of screen pixels per degree of visual angle
    syncflip = true;
end

% set stimulation parameters
fixtn_siz = 0.3*ppd; % fixation point size
shape_siz = 6.0*ppd; % shape size
shape_off = 6.5*ppd; % shape offset
instr_fac = 2.5;     % instruction text magnification factor
quest_fac = 2;       % question mark text magnification factor
goon_fac  = .7;      % go on label text magnification factor
eur_size  = 140;     % euro coin feedback size

% set colors
color_frame = [96,96,96]/255;
lumibg      = [0 0 0];
color_c     = [175,175,175]/255;
color_i     = lumibg;
color_txt   = [175,175,175]/255;
color_cross = [210 40 40]/255;

% create video structure
video = [];
%%
try
    % hide cursor and stop spilling key presses into MATLAB windows
    HideCursor;
%     FlushEvents;
%     ListenChar(2);
    
    % check keyboard responsiveness before doing anything
    fprintf('\n');
    fprintf('Press any key to check keyboard responsiveness... ');
    if WaitKeyPress([],30) == 0
        fprintf('\n\n');
        error('No key press detected after 30 seconds.');
    else
        fprintf('Good.\n\n');
    end
    
    % set keys
    KbName('UnifyKeyNames');
    
    if ~fmri
        warning('KL Log is switched off/n')
        keyresp = KbName({'E','P'});
    else
        keys = {'space' 'ESCAPE' 't' 'b' 'y'};
        KL = KbLogger(KbName(keys) , keys);
        KL.Start;
        keyresp = KbName({'y','b'});
        trigger = KbName('t');
    end
    keywait = KbName('space');
    keyquit = KbName('ESCAPE');
    
    % open main window
    % set screen resolution and refresh rate
    if ~isempty(res) && ~isempty(fps)
        r = Screen('Resolutions',iscr);
        i = find([r.width] == res(1) & [r.height] == res(2));
        if isempty(i) || ~any([r(i).hz] == fps)
            error('Cannot set screen to %d x %d at %d Hz.',res(1),res(2),fps);
        end
        Screen('Resolution',iscr,res(1),res(2),fps);
    end
    % set screen synchronization properties
    % see 'help SyncTrouble',
    %     'help BeampositionQueries' or
    %     'help ConserveVRAMSettings' for more information
    if syncflip
        if ispc
            % soften synchronization test requirements
            Screen('Preference','SyncTestSettings',[],[],0.2,10);
            % enforce beamposition workaround for missing VBL interval
            Screen('Preference','ConserveVRAM',bitor(4096,Screen('Preference','ConserveVRAM')));
        end
        Screen('Preference','VisualDebuglevel',3);
    else
        % skip synchronization tests altogether
        Screen('Preference','SkipSyncTests',1);
        Screen('Preference','VisualDebuglevel',0);
        Screen('Preference','SuppressAllWarnings',1);
    end
    % set font properties
    if ismac
        txtfnt = 'Arial';
        txtsiz = round(1.0*ppd);
    elseif ispc
        txtfnt = 'Arial'; % closest to Helvetica
        txtsiz = round((2/3)*ppd); % text size is ~2/3 smaller in Windows than MacOSX
    else
        txtfnt = 'Arial'; % closest to Helvetica
        txtsiz = round(ppd);
    end
    Screen('Preference','TextAlphaBlending',1);
    Screen('Preference','DefaultFontName',txtfnt);
    Screen('Preference','DefaultFontSize',txtsiz);
    Screen('Preference','DefaultFontStyle',0);
    % prepare configuration and open main window
    PsychImaging('PrepareConfiguration');
    PsychImaging('AddTask','General','UseFastOffscreenWindows');
    PsychImaging('AddTask','General','NormalizedHighresColorRange');
    video.i = iscr;
    video.res = Screen('Resolution',video.i);
    video.h = PsychImaging('OpenWindow',video.i,0);
    [video.x,video.y] = Screen('WindowSize',video.h);
    if syncflip
        video.ifi = Screen('GetFlipInterval',video.h,100,50e-6,10);
    else
        video.ifi = 1/60; % assume 60 Hz
    end
    Screen('BlendFunction',video.h,GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);
    Priority(MaxPriority(video.h));
    Screen('ColorRange',video.h,1);
    Screen('FillRect',video.h,lumibg); %remplir tout l'ecran en couleur lumibg
    Screen('Flip',video.h);
    
    % check screen refresh rate >> in Vasilisa's code (fps is set to 60 at
    % the beginning)
    if ~isempty(fps) && fps > 0 && round(1/video.ifi) ~= fps
        error('Screen refresh rate not equal to expected %d Hz.',fps);
    end
    
    % open offscreen window
    video.hoff = Screen('OpenOffscreenWindow',video.h);
    
    %% create textures
    % load shapes
    shape_tex = zeros(2,6); % shape_tex(1,i)= contour | shape_tex(2,i) = inside
    for ishape = 1:6
        img = double(imread(sprintf('./img/shape%dc.png',ishape)))/255;
        img = imresize(img,shape_siz/size(img,1));
        shape_tex(1,ishape) = Screen('MakeTexture',video.h,cat(3,ones(size(img)),img),[],[],2);
        img = double(imread(sprintf('./img/shape%d.png',ishape)))/255;
        img = imresize(img,shape_siz/size(img,1));
        shape_tex(2,ishape) = Screen('MakeTexture',video.h,cat(3,ones(size(img)),img),[],[],2);
    end
    shape_rec = zeros(3,4); % shape_rec(1,:)=left shape_rec(2,:)=right shape_rec(3,:)=center
    shape_rec(1,:) = CenterRectOnPoint(Screen('Rect',shape_tex(1,1)),video.x/2-shape_off,video.y/2);
    shape_rec(2,:) = CenterRectOnPoint(Screen('Rect',shape_tex(1,1)),video.x/2+shape_off,video.y/2);
    shape_rec(3,:) = CenterRectOnPoint(Screen('Rect',shape_tex(1,1)),video.x/2,video.y/2);
    
    % configure the rectangles around the choice
    shape_add = round(0.1*ppd);
    shape_box = [[ ...
        video.x/2-shape_off-round(RectWidth(shape_rec(1,:)))*0.5-shape_add; ...
        video.y/2-round(RectWidth(shape_rec(1,:)))*0.5-shape_add; ...
        video.x/2-shape_off+round(RectWidth(shape_rec(1,:)))*0.5+shape_add; ...
        video.y/2+round(RectWidth(shape_rec(1,:)))*0.5+shape_add] ...
        [ ...
        video.x/2+shape_off-round(RectWidth(shape_rec(1,:)))*0.5-shape_add; ...
        video.y/2-round(RectWidth(shape_rec(1,:)))*0.5-shape_add; ...
        video.x/2+shape_off+round(RectWidth(shape_rec(1,:)))*0.5+shape_add; ...
        video.y/2+round(RectWidth(shape_rec(1,:)))*0.5+shape_add]];
    
    % load 1eur coin
    [~,~,alpha] =imread('./img/eurocoin.png');
    [I,J]=find(alpha>=50);
    [X2,~,~] =imread('./img/eurocoin.png','BackgroundColor',lumibg);
    X3(:,:,1) = X2((min(I)-1):(max(I)+1),(min(J)-1):(max(J)+1),1);
    X3(:,:,2) = X2((min(I)-1):(max(I)+1),(min(J)-1):(max(J)+1),2);
    X3(:,:,3) = X2((min(I)-1):(max(I)+1),(min(J)-1):(max(J)+1),3);
    img_euro = imresize(X3,eur_size/size(X3,1));
    win_tex = Screen('MakeTexture',video.h,img_euro);
    win_rec = CenterRectOnPoint(Screen('Rect',win_tex),video.x/2,video.y/2);
    
    % "no reward" cross 
    img_cross = ones(ceil((sqrt(2)*eur_size)),20)*1.;
    losetex = Screen('MakeTexture', video.h, img_cross,[],[],2);
    
    % fixation point
    img = CreateCircularAperture(fixtn_siz);
    fixtn_tex = Screen('MakeTexture',video.h,cat(3,ones(size(img)),img),[],[],2);
    fixtn_rec = CenterRectOnPoint(Screen('Rect',fixtn_tex(1)),video.x/2,video.y/2);
    
    % question mark
    Screen('TextSize',video.h,round(txtsiz*quest_fac));
    quest_txt = '?';
    [normBoundsRect, offsetBoundsRect]= Screen('TextBounds',video.h,quest_txt);
    quest_rec = CenterRectOnPoint(normBoundsRect,video.x/2-offsetBoundsRect(1),video.y/2);
    
    % "press escape to continue" label
    Screen('TextSize',video.h,round(txtsiz*goon_fac));
    goon_txt = 'appuyez sur [espace] pour continuer';
    goon_rec = CenterRectOnPoint(Screen('TextBounds',video.h,goon_txt),video.x/2,video.y-round(1.2*ppd));
    
    %% set duration/jitters and setup params
    % jitter values in seconds
    iti   = [.5 2.2 3.9]; % inter-trial interval (fixation point before stim onset)
    stout = [.45 2.1 3.75]-.3; % end of stim to outcome duration
    % stimulus duration
    d_stim  = 1.300;
    timeout = 1.300; %(will continue automatically if no response done)
    % duration before response framed (to avoid thinking response made
    % before key press)
    d_frame = 5*video.ifi;
    % outcome duration
    d_out = 0.700;
    % maximum number of consecutive trials with same shape position
    pseudopos = 3;
    
    %% first flip
    t  = Screen('Flip',video.h);
    T0 = t;
    
    % draw welcome screen
    Screen('TextSize',video.h,round(txtsiz));
    labeltxt = sprintf('appuyez sur [espace] pour d�marrer l''exp�rience');
    labelrec = CenterRectOnPoint(Screen('TextBounds',video.h,labeltxt),video.x/2,round(1.2*ppd));
    Screen('DrawText',video.h,labeltxt,labelrec(1),labelrec(2),color_txt);
    Screen('TextSize',video.h,round(txtsiz*instr_fac));
    labeltxt = 'Bienvenue!';
    labelrec = CenterRectOnPoint(Screen('TextBounds',video.h,labeltxt),video.x/2,video.y/2);
    Screen('DrawText',video.h,labeltxt,labelrec(1),labelrec(2),color_txt);
    Screen('DrawingFinished',video.h);
    Screen('Flip',video.h);
    WaitKeyPress(keywait);
    
    Screen('TextSize',video.h,round(txtsiz*instr_fac));
    labeltxt = 'Bienvenue!';
    labelrec = CenterRectOnPoint(Screen('TextBounds',video.h,labeltxt),video.x/2,video.y/2);
    Screen('DrawText',video.h,labeltxt,labelrec(1),labelrec(2),color_txt);
    Screen('DrawingFinished',video.h);
    Screen('Flip',video.h);
    
    nblck = length(expe.blck);
    cum_gain = 0; % cumulative gain (in euros)
    
    for iblck = start_blck:nblck
        blck = expe.blck(iblck);
        ntrl = blck.ntrl;
        %ntrl = 6;
        
        % create results structure
        rslt          = [];
        rslt.resp     = zeros(1,ntrl);
        rslt.feedback = zeros(1,ntrl);
        rslt.respkb   = zeros(1,ntrl);
        rslt.rt       = zeros(1,ntrl);
        rslt.shape    = zeros(1,ntrl);
        
        % create clock structure
        clck       = [];
        clck.tinst = zeros(1,1);     % the time of instruction screen presentation
        clck.tfix1 = zeros(1,ntrl);  % fixation 1 onset (s)
        clck.tstim = zeros(1,ntrl);  % stimulus pair onset (s)
        clck.tresp = zeros(1,ntrl);  % response (s)
        clck.tfix2 = zeros(1,ntrl);  % fixation 2 (s)
        clck.toutc = zeros(1,ntrl);  % outcome onset (s)
        clck.s2o   = zeros(1,ntrl);  % diff between stim an outcome (s)
        
        % create stimulus presentation structure
        stim       = [];
        stim.shape = shape(iblck,:);
        
        % left and right shape index
        pos = zeros(1,ntrl);
        pos(1:pseudopos) = ceil(2*rand(1,pseudopos));
        for i = (pseudopos+1):ntrl
            ipos = ceil(2*rand(1));
            if sum(pos((i-pseudopos):(i-1))==ipos)>=pseudopos
                pos(i) = 3-ipos;
            else
                pos(i) = ipos;
            end
        end
        
        while abs(diff(hist(pos,1:2)))~=0
            pos = zeros(1,ntrl);
            pos(1:pseudopos) = ceil(2*rand(1,pseudopos));
            for i = (pseudopos+1):ntrl
                ipos = ceil(2*rand(1));
                if sum(pos((i-pseudopos):(i-1))==ipos)>=pseudopos
                    pos(i) = 3-ipos;
                else
                    pos(i) = ipos;
                end
            end
        end
        
        stim.pos(1,:) = pos;             % 1st line: left shape index
        stim.pos(2,:) = 3-stim.pos(1,:); % 2nd line: right shape index        
        stim.iti_jitters = iti(jitter_seq.iti(iblck,:));
        stim.stout_jitters = stout(jitter_seq.stout(iblck,:));
        stim.iti_jitters_idx = jitter_seq.iti(iblck,:);
        stim.stout_jitters_idx = jitter_seq.stout(iblck,:);
        stim.pos_shape  = zeros(2,ntrl);
        stim.ifi = video.ifi;

        if fmri
            fprintf('Waiting for the trigger...\n')
            % wait for 1 dummy scans before flipping the instruction screen and starting the trials
            dummy_scan = 1;
            
            for ds = 1 : dummy_scan+1
                
                while 1
                    [keyIsDown, secs, keyCode] = KbCheck;
                    if keyIsDown && keyCode(trigger)
                        
                        if ds == 1
                            fprintf('Dummy-scan detected!\n')
                            T0 = secs;
                        end
                        
                        if ds > 1
                            fprintf('Starting the task!\n')
                            T0_Stim = secs;
                        end
                        
                        break
                    end
                end
                
                WaitSecs(0.300);
            end
            fprintf('... MRI trigger received \n');
            
            % show beginning of block screen
            Screen('TextSize',video.h,round(txtsiz*instr_fac));
            labeltxt = sprintf('Bloc %d/%d',iblck,nblck);
            labelrec = CenterRectOnPoint(Screen('TextBounds',video.h,labeltxt),video.x/2,video.y/2);
            Screen('DrawText',video.h,labeltxt,labelrec(1),labelrec(2),color_txt);
            Screen('DrawingFinished',video.h);
            t = Screen('Flip',video.h);
            clck.tinst(iblck) = t-T0;
            
            % draw fixation point
            Screen('DrawTexture',video.h,fixtn_tex,[],fixtn_rec,[],[],[],color_txt);
            Screen('DrawingFinished',video.h);
            t = Screen('Flip',video.h,t+roundfp(2.000)); % show fixation point 2 seconds after instructions screen
        else
            
            % show beginning of block screen
            Screen('TextSize',video.h,round(txtsiz*instr_fac));
            labeltxt = sprintf('Bloc %d/%d',iblck,nblck);
            labelrec = CenterRectOnPoint(Screen('TextBounds',video.h,labeltxt),video.x/2,video.y/2);
            Screen('DrawText',video.h,labeltxt,labelrec(1),labelrec(2),color_txt);
            Screen('TextSize',video.h,round(txtsiz*goon_fac));
            labeltxt = 'appuyez sur [espace] pour d�marrer';
            labelrec = CenterRectOnPoint(Screen('TextBounds',video.h,labeltxt),video.x/2,video.y-round(1.2*ppd));
            Screen('DrawText',video.h,labeltxt,labelrec(1),labelrec(2),color_txt);
            Screen('DrawingFinished',video.h);
            t = Screen('Flip',video.h);
            clck.tinst(iblck) = t-T0;

            WaitKeyPress(keywait);
            
            % draw fixation point
            Screen('DrawTexture',video.h,fixtn_tex,[],fixtn_rec,[],[],[],color_txt);
            Screen('DrawingFinished',video.h);
            t = Screen('Flip',video.h);
        end
        
        clck.tfix1(1) = t-T0;

        
        %%
        
        for itrl = 1:ntrl
            
            % check if abort key is pressed
            if CheckKeyPress(keyquit)
                aborted = true;
%                 ShowCursor;
%                 sca;
                break
            end
            
            % left/right shape index
            il = stim.pos(1,itrl);
            ir = stim.pos(2,itrl);
            
            draw_stim(il,ir);
            Screen('TextSize',video.h,round(txtsiz*quest_fac));
            Screen('DrawText',video.h,quest_txt,quest_rec(1),quest_rec(2),color_txt);
            Screen('DrawingFinished',video.h);
            t = Screen('Flip',video.h,t+roundfp(stim.iti_jitters(itrl)));
            clck.tstim(itrl) = t-T0;
            t_on  = t;
            t_out = t_on+roundfp(d_stim+stim.stout_jitters(itrl));
            
            [response,tkey] = WaitKeyPress(keyresp,timeout,false);
            rslt.rt(itrl)   = tkey-t;
            clck.tresp(itrl)= tkey-T0;
            
            draw_stim(il,ir);
            Screen('DrawTexture',video.h,fixtn_tex,[],fixtn_rec,[],[],[],color_txt);
            
            if response ~= 0 % if timeout not reached
                rslt.resp(itrl)   = stim.pos(response,itrl);
                rslt.respkb(itrl) = response;
                rslt.shape(itrl)  = stim.shape(stim.pos(response,itrl));
                % frame shape chosen by participant
                Screen('FrameRect',video.h,color_frame,shape_box(:,response),8);
                Screen('DrawingFinished',video.h);
                t = Screen('Flip',video.h,tkey+roundfp(d_frame));
            else
                rslt.resp(itrl)   = 0;
                rslt.respkb(itrl) = 0;
                rslt.shape(itrl)  = 0;
                Screen('DrawingFinished',video.h);
                t = Screen('Flip',video.h);
            end
            clck.tfix2(itrl) = t-T0;
            
            % show outcome in the middle
            irew = blck.outcome(itrl); % {1;2} index of rewarding shape
                        
            if (rslt.resp(itrl) == irew) % show win outcome
                Screen('DrawTexture',video.h,win_tex,[],win_rec);
                rslt.feedback(itrl) = 1;
            else % show no reward outcome
                Screen('DrawTexture',video.h,win_tex,[],win_rec);
                Screen('DrawTexture', video.h, losetex, [], [], 45,[],[],color_cross);
                Screen('DrawTexture', video.h, losetex, [], [], -45,[],[],color_cross);
                rslt.feedback(itrl) = 0;
            end
            if response ~= 0
                Screen('FrameRect',video.h,color_frame,shape_box(:,response),8);
            end
            draw_stim(il,ir);
            Screen('DrawingFinished',video.h);            
            
            t  = Screen('Flip',video.h,t_out);
            
            clck.toutc(itrl) = t-T0;
            clck.t_out(itrl) = t_out-T0;
            clck.s2o(itrl)   = t_out-t_on;
            
            Screen('DrawTexture',video.h,fixtn_tex,[],fixtn_rec,[],[],[],color_txt);
            Screen('DrawingFinished',video.h);
            t = Screen('Flip',video.h,t+roundfp(d_out));
            clck.tfix1(itrl+1) = t-T0;

        end % end of trial loop
        
        % ITI fixation point
        Screen('DrawTexture',video.h,fixtn_tex,[],fixtn_rec,[],[],[],color_txt);
        Screen('DrawingFinished',video.h);
        t = Screen('Flip',video.h,t+roundfp(1));
        clck.tend = t-T0;

        % compute performances (euros actually seen)
        rslt.perf = sum(rslt.resp(1:ntrl) == blck.outcome(1:ntrl))/ntrl;
        
        perfRL   = zeros(1,5000);
        perfWSLS = zeros(1,5000);
        for i = 1:5000
            perfRL(i)   = simulRLperf(blck,ntrl);
            perfWSLS(i) = simulWSLSperf(blck,ntrl);
        end
        
        rslt.perfRL   = perfRL;
        rslt.perfWSLS = perfWSLS;
 
        KL.KbEvents
        KL.GetQueue;
        KL.ScaleTime;
        KL.ComputeDurations;
        KL.KbEvents
        assignin('base','KL',KL)
        if fmri
            TTL_indexs = find(cell2mat(KL.KbEvents{3,2}(:,2)));
            TTL = cell2mat(KL.KbEvents{3,2}(TTL_indexs,1)) + T0;
        else
            T0      = 0;
            T0_Stim = 0;
            TTL     = 0;
        end
        
        logi = struct();
        logi.TTL = TTL;
        logi.KL  = KL.CopyObject;
        logi.T0  = T0;
        logi.T0_Stim = T0_Stim;
        
        % store results and block substructures
        expe_blck.blck = blck;
        expe_blck.rslt = rslt;
        expe_blck.clck = clck;
        expe_blck.stim = stim;
        expe_blck.logi = logi; 
        
        % update experiment structure
        expe.blck(iblck) = blck;
        expe.rslt(iblck) = rslt;
        expe.clck(iblck) = clck;
        expe.stim(iblck) = stim;
        expe.logi(iblck) = logi;

        % save temporary file (block per block)
        fpath = foldname;
        fname = sprintf('VOLNOISE_IRM_S%02d_session%d_b%02d_%s',hdr.subj,session,iblck,datestr(now,'yyyymmdd-HHMM'));
        if aborted
            if ~exist([fpath,'/aborted'],'dir')
                mkdir([fpath,'/aborted']);
            end
            fpath = [foldname,'/aborted/'];
            fname = [fname,'_aborted'];
        end
        fname = fullfile(fpath,fname);
        save([fname,'.mat'],'expe_blck');
        
        if aborted
            break
        end
        
        % draw perf screen
        h = histc(rslt.perf,[0 linspace(min(mean(perfRL),.85),max(mean(perfRL),.85),5) 1]);
        gain     = find(h)-1;
        cum_gain = cum_gain+gain;
        
        Screen('TextSize',video.h,round(txtsiz));
        labeltxt = double(sprintf('Vous avez gagn� %d%c de bonus sur ce bloc!',gain,char(8364)));
        labelrec = CenterRectOnPoint(Screen('TextBounds',video.h,labeltxt),video.x/2,video.y/2);
        Screen('DrawText',video.h,labeltxt,labelrec(1),labelrec(2),color_txt);
        Screen('TextSize',video.h,round(txtsiz*goon_fac));
        Screen('DrawText',video.h,goon_txt,goon_rec(1),goon_rec(2),color_txt);
        Screen('DrawingFinished',video.h);
        Screen('Flip',video.h);
        WaitKeyPress(keywait);
        
        Screen('TextSize',video.h,round(txtsiz));
        labeltxt = double(sprintf('Vous avez gagn� %d%c de bonus sur ce bloc!',gain,char(8364)));
        labelrec = CenterRectOnPoint(Screen('TextBounds',video.h,labeltxt),video.x/2,video.y/2);
        Screen('DrawText',video.h,labeltxt,labelrec(1),labelrec(2),color_txt);
        Screen('DrawingFinished',video.h);
        Screen('Flip',video.h);
%         WaitKeyPress(keywait);
        
    end % block loop
    
    if aborted
        Priority(0);
        Screen('CloseAll');
        %     FlushEvents;
        %     ListenChar(0);
        ShowCursor;
        sca;
        return
    end
    
    % save complete file
    fpath = foldname;
    fname = sprintf('VOLNOISE_IRM_S%02d_session%d_%s',hdr.subj,session,datestr(now,'yyyymmdd-HHMMSS'));
    fname = fullfile(fpath,fname);
    save([fname,'.mat'],'expe');
    
    perf_tot     = 0;
    perfRL_tot   = 0;
    perfWSLS_tot = 0;
    
    for i = 1:nblck
        perf_tot     = perf_tot+expe.rslt(i).perf/nblck;
        perfWSLS_tot = perfWSLS_tot+mean(expe.rslt(i).perfWSLS)/nblck;
        perfRL_tot   = perfRL_tot+mean(expe.rslt(i).perfRL)/nblck;
    end
    
    fprintf('\n\n Performances\n')
    fprintf('\tSubj:\t %d%%\n', round(perf_tot*100))
    fprintf('\tRL:\t %d%%\n', round(perfRL_tot*100))
    fprintf('\tWSLS:\t %d%%\n', round(perfWSLS_tot*100))
    fprintf('... %d euro(s) de bonus!\n\n',cum_gain)
%     
%     if aborted
%         Screen('CloseAll');
%         return
%     end
% ====================================================================
% Vasilisa (uncomment for fMRI) 
% KL.Stop;
% ====================================================================
    
    % close Psychtoolbox
    Priority(0);
    Screen('CloseAll');
%     FlushEvents;
%     ListenChar(0);
    ShowCursor;
    
catch ME
    
    KL.GetQueue;
    KL.Stop;
    KL.ScaleTime;
    KL.ComputeDurations;
    
    % close Psychtoolbox
    Priority(0);
    Screen('CloseAll');
%     FlushEvents;
%     ListenChar(0);
    ShowCursor;
    
    % handle error
    if nargout > 2
        errmsg = ME;
        %errmsg = rmfield(errmsg,'stack');
    else
        rethrow(ME);
    end
    
end

%%
    function [t] = roundfp(t,dt)
        % apply duration rounding policy for video flips
        % where t  - desired (input)/rounded (output) duration
        %       dt - desired uniform jitter on duration (default: none)
        n = round(t/video.ifi);
        % apply uniform jitter
        if nargin > 1 && dt > 0
            m = round(dt/video.ifi);
            n = n+ceil((m*2+1)*rand)-(m+1);
        end
        % convert frames to duration
        t = (n-0.5)*video.ifi;
    end

%%
    function draw_stim(il,ir)
        % draw left stimulus
        is = stim.shape(il);
        Screen('DrawTexture',video.h,shape_tex(1,is),[],shape_rec(1,:),[],[],[],color_c);
        Screen('DrawTexture',video.h,shape_tex(2,is),[],shape_rec(1,:),[],[],[],color_i);
        stim.pos_shape(1,itrl) = is;
        % draw right stimulus
        is = stim.shape(ir);
        Screen('DrawTexture',video.h,shape_tex(1,is),[],shape_rec(2,:),[],[],[],color_c);
        Screen('DrawTexture',video.h,shape_tex(2,is),[],shape_rec(2,:),[],[],[],color_i);
        stim.pos_shape(2,itrl) = is;
    end

end