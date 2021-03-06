classdef fmri_speller < handle
% SPELLER is the main parent class for an SSVEP based speller that uses PTB
% for display and stimulation
    properties
        CUE_DUR             = 1.0;
        FB_DUR              = 1.0;
        DEF_STIM_DUR        = 2.0;
        WHITE               = [255, 255, 255];
        BLACK               = [  0,   0,   0];
        RED                 = [255,   0, 102];
        BLUE                = [102,   0, 255];
        GREEN               = [50,   255, 50];
        BG_COLOR            = [  0,   0,   0];
        YELLOW              = [210,  210,  0];
        TEXT_FONT           = 'Arial';
        FONT_SIZE           = 28;
        SM_FONT_SIZE        = 18;
        COPY_SEQ            = '1234';
        copy_seq            = [];
        TRIAL_CNT           = 1;
        numHarmonics        = 3;
        fb_seq
        EXP_END
        escKey
        enterKey
        tKey
        oldDebugLevel
        screens
        screenNumber
        window
        windowRect
        centX
        centY
        ifi
        vbl
        refreshRateHz
        design
        spellerMode
        numTarg
        Copy_Seq_Num
        channels
        sourceType
        classifierType
        spelledLetters
        spelledTxt
        running
        showStart
        trainFileName =[];
        predictiveText
        src_parallel_mode
        keypress_check_vector
        sub_info
        data_dir
        cue_sequence
        vBlockSize
        hBlockSize
        
        % Speller Modes
        debugMode
        wordPredictionMode
        twitterMode
        TTS_Mode
        offlineMode
        
        % PTB Screens
        offScreen
        blankScreen
        startScreen
        endScreen
        
        % Class objects
        sourceObj
        classifierObj
        wordPredictorObj
        twitterObj
        TTS_Obj
    end
    
    methods
        %------------------------------------------------------------------
        % Class constructor:
        function self = fmri_speller(options)
            self.DEF_STIM_DUR = options.stimDuration;
            self.CUE_DUR = options.CUE_DUR;
            self.FB_DUR = options.FB_DUR;
            self.numTarg = options.numTarg;
            self.spellerMode = options.spellerMode;
            self.COPY_SEQ=options.copySeq;
            self.EXP_END = length(self.COPY_SEQ);

            % fmri experiment
            self.EXP_END = 60;
            
            self.sourceType = options.sourceType;
            self.classifierType = options.classifierType;
            self.channels = options.channels;
            self.showStart = options.showStart;
            self.debugMode = options.debugMode;
            self.trainFileName = options.trainFileName;
            self.wordPredictionMode = options.wordPredictionMode;
            self.twitterMode = options.twitterMode;
            self.TTS_Mode = options.TTS_Mode;
            self.src_parallel_mode = options.src_parallel_mode;
            self.sub_info = options.sub_info;
            self.data_dir = options.data_dir;
            self.offlineMode = options.offlineMode;
            if(self.offlineMode)
                self.spellerMode = 'copyspell';
                self.debugMode = true;
                self.wordPredictionMode = false;
            end
            self.vBlockSize = options.vBlockSize;
            self.hBlockSize = options.hBlockSize;
            initialize(self); % initialize speller display
            Priority(1); % set to high priority
        end
        %------------------------------------------------------------------
        
        %------------------------------------------------------------------
        % Main Functions:
        
        function start(self)
        %START is the main runnable that starts and runs the speller after
        %all initialization has been completed
            % send LSL marker to indicate the paradigm has started
            if(strcmp(self.sourceType,'LSL')) 
                sendMarker(self.sourceObj, 'ssvepStart');
            end
            % Show start screen and wait for user to Start
            if(self.showStart)
                Screen('CopyWindow', self.startScreen, self.window);
                Screen('Flip', self.window);
                while 1
                    [~, ~, keyCode] = KbCheck([],[],self.keypress_check_vector);
                    if keyCode(self.enterKey) || keyCode(self.tKey)
                        break;
                    end
                end
            end
            self.running=true;
            while self.running
                % check to see if experiment is done
                if(self.TRIAL_CNT==self.EXP_END+1)
                    while 1
                        [~, ~, keyCode] = KbCheck([],[],self.keypress_check_vector);
                        if keyCode(self.escKey)
                            break;
                        end
                        % Show end screen
                        Screen('CopyWindow', self.endScreen, self.window);
                        Screen('Flip', self.window);
                    end
                    break;
                end
                [~, ~, keyCode] = KbCheck([],[],self.keypress_check_vector);
                if keyCode(self.escKey), break; end
                
                % check to see if experiment is halfway over, then switch
                % stimuli/frequency. 
                if(self.TRIAL_CNT == (self.EXP_END/2) + 1)
                  swapOutStimuli(self);  
                end
                
                displayCue(self);                    % CUE
                stimulate(self);                     % Stimulation
                displayFeedback(self);               % Feedback
            end
            terminate(self); % terminate speller when done
        end
        
        function swapOutStimuli(self)
        % SWAPSTIMULI swaps out stimuli for the fmri paradigm
        % change stimuli text
            self.design.Symbol{1}='1';
            self.design.Symbol{2}='2';
            self.design.Symbol{3}='3';
            
            self.design.StimFreq{1}=14.6;
            self.design.StimFreq{2}=9.2;
            self.design.StimFreq{3}=8.4;
            
            % change stimuli frequency
            % Set stimulus frequencies and flickering codes for each target
            DEFAULT_PHASE   = 0.001;
            waveForm    = 'square';
            for targ_i = 1:1:self.numTarg
                self.design.FlickCode{targ_i} = exp_GenFlickerCode(self,...
                    self.design.LenCode,...
                    self.design.StimFreq{targ_i},...
                    round(self.refreshRateHz),...
                    waveForm,...
                    self.design.StimPhase{targ_i}+DEFAULT_PHASE);
            end 
            
            
            for win_i = 1:1:self.design.LenCode
                % stimuli 
                    fillColor = cell2mat(self.design.FlickCode');
                    stimParam = struct(...
                        'FillColor',    fillColor(:, win_i),...
                        'FrameColor',   fillColor(:, win_i),...
                        'TextColor',    self.BLACK,...
                        'TextFont',     self.TEXT_FONT,...
                        'TextSize',     self.FONT_SIZE);
                    exp_preloadStimuli(self,'stimuli', self.offScreen(win_i), self.design, stimParam)
            end % win_i
            
            % update blank screen
            stimParam = struct(...
                'FillColor',    self.BLACK,...
                'FrameColor',   self.WHITE,...
                'TextColor',    self.WHITE,...
                'TextFont',     self.TEXT_FONT,...
                'TextSize',     self.FONT_SIZE);
            exp_preloadStimuli(self, 'stimuli', self.blankScreen,self.design,stimParam);
        end
        
        function stimulate(self)
        % STIMULATE starts the actual ssvep stimulation sequence. this is a
        % synchronous and discrete speller, therefore, the stimulation
        % turns on and off for a fixed interval, afterwards, classification
        % and feedback can be performed
            self.vbl = Screen('Flip', self.window);
            if(strcmp(self.sourceType,'LSL'))
                sendMarker(self.sourceObj, ['ssvep_' num2str(self.design.StimFreq{self.cue_sequence(self.TRIAL_CNT-1)})...
                    '_' self.COPY_SEQ(self.cue_sequence(self.TRIAL_CNT-1))]);
            end
%             sendTrigger(self.sourceObj,'start'); % trigger start of stimulation
            % Start Gazing (Stimulation) ------------------------------------
            for win_i = 1:1:self.design.LenCode
                % If 'ESC' key is pressed, the iteration will be finished.
%                 [~, ~, keyCode] = KbCheck([],[],self.keypress_check_vector);
%                 if keyCode(self.escKey), break; end
                % Stimulation
                Screen('CopyWindow', self.offScreen(win_i), self.window);
                self.vbl = Screen('Flip', self.window, self.vbl + (0.5*self.ifi));
%                 if(strcmp(self.classifierType,'Mouse'))
%                     % decode selected target from mouse click
%                     decode_mouse_target(self.classifierObj)
%                 end
            end % win_i
%             sendTrigger(self.sourceObj,'stop');   % trigger end of stimulation
            Screen('CopyWindow', self.blankScreen, self.window); 
            Screen('Flip', self.window); % return to blank screen after stimulation
        end
        
        function displayCue(self)
        % DISPLAYCUE displays the cue to the next letter to spell to the
        % user. This is usually used in copy-speller mode
            if(strcmp(self.sourceType,'LSL')) 
                sendMarker(self.sourceObj, 'ssvepCue');
            end
            trialStart = tic;  % Timer for begining of trial
            if(strcmpi(self.spellerMode,'copyspell'))
                % Cue Letter to Spell (Copy Spelling Mode)
                % random cue for fmri
                Txt2Spell = self.COPY_SEQ(self.cue_sequence(self.TRIAL_CNT));
                self.copy_seq = [self.COPY_SEQ '  (' Txt2Spell ')' ];
                cue = self.Copy_Seq_Num(self.cue_sequence(self.TRIAL_CNT));
                
                % Display Cue to user
                exp_visualFeedback(self,self.blankScreen, self.design, cue, self.BLACK, self.GREEN, self.WHITE, self.fb_seq,self.copy_seq);
                Screen('CopyWindow', self.blankScreen, self.window);
                Screen('Flip', self.window);
                
                % return fb and cue stim to normal for stimulation
                exp_visualFeedback(self,self.blankScreen, self.design, cue, self.BLACK, self.WHITE, self.WHITE, self.fb_seq, self.copy_seq);
                
                self.TRIAL_CNT = self.TRIAL_CNT + 1; % update counter
            else
                % Update Word Prediction
                if(self.wordPredictionMode)
                    if(~isempty(self.fb_seq))
                        wp = strsplit(self.fb_seq);
                        self.predictiveText = PredictWords(self.wordPredictorObj,wp{end});
                    else 
                        self.predictiveText = PredictWords(self.wordPredictorObj,[]);
                    end
                    % update the first 9 stimuli of blank screen with new
                    % predictive text
                    for i = 1:self.wordPredictorObj.numWords2Predict
                        self.design.Symbol{i} = [' ' upper(self.predictiveText{i}) ' '];
                        self.design.NameAudio{i} = self.predictiveText{i};
                        Screen(self.blankScreen, 'TextSize', self.SM_FONT_SIZE);
                        exp_visualFeedback(self, self.blankScreen, self.design, i, self.BLACK, self.YELLOW, self.YELLOW, self.fb_seq,[]);
                    end
                        Screen(self.blankScreen, 'TextSize', self.FONT_SIZE);
                end
                Screen('CopyWindow', self.blankScreen, self.window);
                Screen('Flip', self.window);
            end

%             preDrawStimuli(self);  % pre-draw
            while toc(trialStart) <= self.CUE_DUR
                [~, ~, keyCode] = KbCheck([],[],self.keypress_check_vector);
                if keyCode(self.escKey), break; end
            end
        end
        
        function displayFeedback(self)
        % DISPLAYFEEDBACK performs all opterations necessary to generate
        % feedback for an SSVEP speller, including extracting a stimulus
        % time-locked EEG trial, classifiying the EEG trial, and displaying
        % the feedback to the user.
            if(strcmp(self.sourceType,'LSL')) 
                sendMarker(self.sourceObj, 'ssvepISI');
            end
            if(~self.offlineMode)
                % Determine feedback
                trial = readBuffer(self.sourceObj); % extract EEG trial from source
                fb = classifyTrial(self.classifierObj,trial); % classify trial
                self.spelledLetters = [self.spelledLetters fb]; % save spelled leters
                self.spelledTxt = [self.spelledTxt self.design.fbSymbol{fb}];

                % Dispaly feedback to user
                if(self.twitterMode && fb == self.twitterObj.twitterTarg)
                    sendTweet(self.twitterObj,self.fb_seq);
                    show_twitter(self.twitterObj);
                    self.TRIAL_CNT=self.EXP_END+1;
                else
                    if(strcmp(self.design.Symbol{fb},'<'))
                        self.fb_seq = self.fb_seq(1:end-1);
                    else
                        self.fb_seq = [self.fb_seq, self.design.fbSymbol{fb}];
                    end
                end

                % Re-Draw Screen with new feedback
                if(self.wordPredictionMode && fb <=9)
                    Screen(self.blankScreen, 'TextSize', self.SM_FONT_SIZE);
                else
                    Screen(self.blankScreen, 'TextSize', self.FONT_SIZE);
                end
                exp_visualFeedback(self, self.blankScreen, self.design, fb, self.RED, self.RED, self.BLACK, self.fb_seq,self.copy_seq);
                Screen('CopyWindow', self.blankScreen, self.window);
                Screen('Flip', self.window);

                if(self.TTS_Mode)
                    play_text(self.TTS_Obj,fb);
                end

                % Reset screen after display
                if(self.wordPredictionMode && fb <=9)
                    Screen(self.blankScreen, 'TextSize', self.SM_FONT_SIZE);
                end
                exp_visualFeedback(self, self.blankScreen, self.design, fb, self.BLACK, self.WHITE, self.WHITE, self.fb_seq,self.copy_seq);
                Screen(self.blankScreen, 'TextSize', self.FONT_SIZE);
            end
            
            % Implement Random ISI for fmri
            self.FB_DUR = randi(5);
            
            inter_trialStart = tic;
            while toc(inter_trialStart) <= self.FB_DUR
                [~, ~, keyCode] = KbCheck([],[],self.keypress_check_vector);
                if keyCode(self.escKey), break; end
            end
        end
                
        %------------------------------------------------------------------
        
        
        %------------------------------------------------------------------
        % Dependencies:
        function initialize(self)
        % INITIALIZE starts up the PTB windows, speller screens and other
        % modules used to run the BCI speller
            
            
            % determine copy spell or free spell mode
            if(strcmpi(self.spellerMode,'freespell'))
                self.copy_seq=[];
            else
                self.wordPredictionMode = false; % only use WP in freespell
                self.cue_sequence = [ones(1,20)*1 ones(1,20)*2 ones(1,20)*3];
                self.cue_sequence = self.cue_sequence(randperm(length(self.cue_sequence)));
            end
            
            % determine if word completion mode
            if(self.wordPredictionMode)
                self.wordPredictorObj = WordPredictor();
                self.predictiveText = PredictWords(self.wordPredictorObj,[]);
            end
            
            % determine if twitter mode
            if(self.twitterMode)
                self.twitterObj = TwitterApp();
            end
            
            % initialize Signal Source module
            switch self.sourceType
                case 'FT'
                    self.sourceObj = FT(self.DEF_STIM_DUR,1,self.channels, self.debugMode,self.src_parallel_mode);
                case 'LSL'
                    self.sourceObj = LSL(self.DEF_STIM_DUR,1,self.channels, self.debugMode, 'COM9');
            end
            
            % if using lsl, Wait to start lab-recorder, then press 'a'
            if(strcmp(self.sourceType,'LSL'))
                self.keypress_check_vector([self.escKey, self.enterKey, self.tKey]) = 1;
                while 1
                    [~, ~, keyCode] = KbCheck([],[],KbName('a'));
                    if keyCode(KbName('a'))
                        break;
                    end
                end
            end
            
            % Init PTB and generate speller Screens
            exp_GenPTBscreens(self);
            
            % determin if TTS mode
            if(self.TTS_Mode)
                self.TTS_Obj = Text2Speech(self.design.NameAudio);
            end
            
            % initialize Classifier module
            switch self.classifierType
                case 'CCA'
                    self.classifierObj = CCA(self.numHarmonics,self.DEF_STIM_DUR,self.sourceObj.Fs,self.design.StimFreq, self.debugMode);
                case 'CombinedCCA'
                    self.classifierObj = Combined_CCA(self.numHarmonics,self.DEF_STIM_DUR,self.sourceObj.Fs,self.design.StimFreq, self.debugMode, self.trainFileName);
                case 'Mouse'
                    self.classifierObj = Mouse_Classifier(self.window,self.design.StimLoc);
            end
            
        end % END initialze
        
        function terminate(self)
        % TERMINATE closes all PTB windows and terminates any objects
            % save results
            if(strcmp(self.sourceType,'LSL')) 
                sendMarker(self.sourceObj, 'ssvepEnd');
            end
            if(~self.offlineMode)
                COPY_SEQ = self.COPY_SEQ;
                spelledLetters = self.spelledLetters;
                spellerMode = self.spellerMode;
                twitterMode = self.twitterMode;
                wordPredictionMode = self.wordPredictionMode;
                classifierType = self.classifierType;
                sourceType = self.sourceType;
                spelledTxt = self.spelledTxt;
                save([self.data_dir 'S' self.sub_info.sub_id 'S' self.sub_info.session_id...
                    'R' self.sub_info.run_id],'spelledLetters', 'COPY_SEQ','spellerMode','twitterMode',...
                    'wordPredictionMode','classifierType','sourceType','spelledTxt');
            end
            Screen('CloseAll');
            ShowCursor;
            Screen('Preference', 'VisualDebuglevel', self.oldDebugLevel);
            terminate(self.sourceObj);
            if(self.TTS_Mode)
                dispose(self.TTS_Obj);
            end
            Priority(0);
            
        end % END terminate
        
        function exp_GenPTBscreens(self)
        % EXP_GENPTBSCREENS generates the main PTB screens used for
        % stimulation and for start and end of experiments. It
        % pre-generates and pre-loads all screens and frames into memory
        % for fast swapping in real-time
            % Initialize PTB toolbox
            if(~strcmp(self.classifierType,'Mouse')) 
                HideCursor;
            end
            KbName('UnifyKeyNames');
            self.escKey = KbName('ESCAPE');
            self.enterKey = KbName('Return');
            self.tKey = KbName('t');
            self.keypress_check_vector = zeros(1,256);
            self.keypress_check_vector([self.escKey, self.enterKey, self.tKey]) = 1; 
            self.oldDebugLevel = Screen('Preference', 'VisualDebuglevel', 3);
            self.screens = Screen('Screens');
            self.screenNumber = max(self.screens);
            [self.window, self.windowRect] = Screen('OpenWindow', self.screenNumber, self.BG_COLOR, [], [], 2);
            [self.centX, self.centY] = RectCenter(self.windowRect);
            self.ifi = Screen('GetFlipInterval', self.window);
            self.refreshRateHz = round(1/self.ifi);
            display(['Da frequency is : ' num2str(self.refreshRateHz)]);
            % Generate Stimulus design structur
            self.design = exp_GenStimDesign(self,self.spellerMode, self.refreshRateHz, [self.windowRect(3), self.windowRect(4)], self.DEF_STIM_DUR, self.numTarg);
            % translate txt 2 spell 2 number array
            for xx = 1:length(self.COPY_SEQ)
                for jj = 1:length(self.design.Symbol)
                    if(strcmp(self.design.Symbol{jj},self.COPY_SEQ(xx)))
                        self.Copy_Seq_Num(xx) = jj;
                    end
                end
            end
            self.design.CentWindow = [self.centX, self.centY];
            % -------------------------------------------------------------
            % Set Stimulus and text coordinates for stimulation screen
            % -------------------------------------------------------------
            for targ_i = 1:1:self.design.NumTarg  
                % Set coordinates of rectangle vertex
                % [left upper X, left upper Y, right lower X, right lower Y]
                self.design.StimLoc{targ_i} = [...
                    self.design.CenterLoc{targ_i}(1) + self.centX - self.design.LenSide/2,...
                    self.design.CenterLoc{targ_i}(2) + self.centY - self.design.LenSide/2,...
                    self.design.CenterLoc{targ_i}(1) + self.centX + self.design.LenSide/2,...
                    self.design.CenterLoc{targ_i}(2) + self.centY + self.design.LenSide/2];
                
                % Set cordinates of text location
                bounds = Screen(self.window, 'TextBounds', self.design.Symbol{targ_i});
                if(self.wordPredictionMode && targ_i <=9)
                    % make the predictive words left justified
                    self.design.TextLocX{targ_i} = self.design.CenterLoc{targ_i}(1)+self.centX-bounds(RectRight)/1.5;
                else
                    self.design.TextLocX{targ_i} = self.design.CenterLoc{targ_i}(1)+self.centX-bounds(RectRight)/1.5;
                end
                self.design.TextLocY{targ_i} = self.design.CenterLoc{targ_i}(2)+self.centY-bounds(RectBottom)/1.5;
                
            end % targ_i
            % Set coordinates of text filed for visual feedback
            % [left upper X, left upper Y, right lower X, right lower Y]
            self.design.TxtFldLoc = [...
                self.design.LocTxtFld(1) + self.centX - self.design.wTxtFld/2,...
                self.design.LocTxtFld(2) + self.centY - self.design.hTxtFld/2,...
                self.design.LocTxtFld(1) + self.centX + self.design.wTxtFld/2,...
                self.design.LocTxtFld(2) + self.centY + self.design.hTxtFld/2];
            self.design.TxtFldLoc(2)=self.design.TxtFldLoc(2) - 10;
            self.design.TxtFldLoc(4)=self.design.TxtFldLoc(4) - 10;
            bounds = Screen(self.window, 'TextBounds', '>>');
            self.design.TxtLocX = self.design.TxtFldLoc(1)+bounds(RectRight)/2+10;
            self.design.TxtLocY = mean(self.design.TxtFldLoc([2,4]))-bounds(RectBottom)/2;
            
            % -------------------------------------------------------------
            % Set offscreen for stimulation
            % -------------------------------------------------------------
            fillColor = cell2mat(self.design.FlickCode');
            self.offScreen = zeros(1, self.design.LenCode);
            for win_i = 1:1:self.design.LenCode
                
                % Open off-screens
                stimParam = struct(...
                    'FillColor',    fillColor(:, win_i),...
                    'FrameColor',   fillColor(:, win_i),...
                    'TextColor',    self.BLACK,...
                    'TextFont',     self.TEXT_FONT,...
                    'TextSize',     self.FONT_SIZE);
                
                self.offScreen(win_i) = Screen(self.window, 'OpenOffScreenWindow', self.BG_COLOR);
                exp_preloadStimuli(self,'stimuli', self.offScreen(win_i), self.design, stimParam);
                
            end % win_i
            % -------------------------------------------------------------
            % Set blankscreen
            % -------------------------------------------------------------
            % Set offscreen for gaze shift
            stimParam = struct(...
                'FillColor',    self.BLACK,...
                'FrameColor',   self.WHITE,...
                'TextColor',    self.WHITE,...
                'TextFont',     self.TEXT_FONT,...
                'TextSize',     self.FONT_SIZE);
            
            self.blankScreen = Screen(self.window, 'OpenOffScreenWindow', self.BG_COLOR);
            exp_preloadStimuli(self,'blank', self.blankScreen, self.design, stimParam);
            % ---------------------------------------------------------------------
            % Create offscreen for start screen
            % ---------------------------------------------------------------------
            self.startScreen = Screen(self.window, 'OpenOffScreenWindow', self.BG_COLOR);
            
            Screen(self.startScreen, 'TextColor', self.WHITE);
            Screen(self.startScreen, 'TextFont', self.TEXT_FONT);
            Screen(self.startScreen, 'TextSize', self.FONT_SIZE);
            
            startMsg = 'Be prepared. Waiting on scanner to start';
            bounds = Screen(self.startScreen, 'TextBounds', startMsg);
            Screen('DrawText', self.startScreen, startMsg, self.centX-bounds(RectRight)/2, self.centY-bounds(RectBottom)/2, self.WHITE);
            % ---------------------------------------------------------------------
            % Create offscreen for Ending screen
            % ---------------------------------------------------------------------
            self.endScreen = Screen(self.window, 'OpenOffScreenWindow', self.BG_COLOR);
            
            Screen(self.endScreen, 'TextColor', self.WHITE);
            Screen(self.endScreen, 'TextFont', self.TEXT_FONT);
            Screen(self.endScreen, 'TextSize', self.FONT_SIZE);
            
            endMsg = 'Experiment Complete.';
            bounds = Screen(self.endScreen, 'TextBounds', endMsg);
            Screen('DrawText', self.endScreen, endMsg, self.centX-bounds(RectRight)/2, self.centY-bounds(RectBottom)/2, self.WHITE);
        end %END exp_GenPTBscreens
        
        function design = exp_GenStimDesign(self,spellerMode, refresh, resol, stimTime,numTarg)
        %EXP_GENSTIMDESIGN generates a stimulus design structure that
        %contains all of the parameters for the ssvep speller stimulus
        %including the frequency/phase properties of the stimuli
            % stimulus parameters
            DEFAULT_PHASE   = 0.001;
            wid         = resol(1);     % width of screen window
            hei         = resol(2);     % height of screen window
            lenCode     = round(refresh*stimTime);
            numFreq     = numTarg;
            minFreq     = 8.00;
            freqResol   = minFreq/numTarg;
            minPhase    = 0.00;
            phaseResol  = 0.5*pi;
            waveForm    = 'square';
            stimShape   = 'rect';
            numColumn   = min(numTarg,10);
            numRow      = ceil(numTarg/numColumn);
            
            % Set stimulus frequencies and flickering codes for each target
%             for column_i = 1:1:numColumn
%                 for row_i = 1:1:numRow
%                     stimFreq{numColumn*(row_i-1)+column_i} = minFreq + freqResol*(numRow*(column_i-1)+(row_i-1));
%                     stimPhase{numColumn*(row_i-1)+column_i} = wrapTo2Pi(minPhase + phaseResol*(numRow*(column_i-1)+(row_i-1)));
%                 end % row_i
%             end % column_i
            
            % for fmri, we are having 3 stimuli only, here we specify those
            stimFreq{1}=8;
            stimFreq{2}=10;
            stimFreq{3}=12;
            stimPhase{1}=wrapTo2Pi(minPhase + phaseResol*(0));
            stimPhase{2}=wrapTo2Pi(minPhase + phaseResol*(1));
            stimPhase{3}=wrapTo2Pi(minPhase + phaseResol*(2));
            
            % paramaterize the block size
            if(isempty(self.vBlockSize))
                vBlockSize = wid/10;
                hBlockSize = wid/10;
            else
                vBlockSize = self.vBlockSize;
                hBlockSize = self.hBlockSize;
            end
            
            % Set symbols for each stimulus
            tmpSymbol      = {'A', 'B', 'C', '4', '5', '6', '7', '8', '9', '0',...
                'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P',...
                'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'space',...
                'Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '<'};
            % File name for audio files
            tmpNameAudio   = {'1', '2', '3', '4', '5', '6', '7', '8', '9', '0',...
                'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P',...
                'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'space',...
                'Z', 'X', 'C', 'V', 'B', 'N', 'M', 'comma', 'period', 'Back Space'};
            
            eraseTarg   = numTarg;
            enterTarg   = numTarg+1; % It's dummy
            
            if(self.twitterMode)
                tmpSymbol{end} = 'Tweet';
                tmpNameAudio{end} = 'Message Tweeted';
                self.twitterObj.twitterTarg = numTarg;
                % add in backspace
                tmpSymbol{10} = '<';
                tmpNameAudio{10} = 'Back Space';
            end
            
            if(self.wordPredictionMode)   
                for i = 1:self.wordPredictorObj.numWords2Predict
                    tmpSymbol{i} = [' ' upper(self.predictiveText{i}) ' '];
                    tmpNameAudio{i} = self.predictiveText{i};
                end
            end
            
            for i=1:numTarg
                symbol{i} = tmpSymbol{i};
                fbSymbol{i} = tmpSymbol{i};
                if(strcmp(fbSymbol{i},'space') || strcmp(fbSymbol{i},'Tweet'))
                    fbSymbol{i} = ' ';
                end
                nameAudio{i} = tmpNameAudio{i};
            end
            
            % stimulation parameters
            blockSize   = min([vBlockSize, hBlockSize]);
            dist2Targ   = floor(blockSize*0.2);
            lenSide     = blockSize - dist2Targ;
            wTxtFld     = hBlockSize*(numColumn-1) + lenSide;
            hTxtFld     = lenSide/2;
            locTxtFld   = [0, blockSize/2/2 - (blockSize/2*9/2)];
            
            % Set stimulus frequencies and flickering codes for each target
            for targ_i = 1:1:numTarg
                flickCode{targ_i} = exp_GenFlickerCode(self,...
                    lenCode,...
                    stimFreq{targ_i},...
                    round(refresh),...
                    waveForm,...
                    stimPhase{targ_i}+DEFAULT_PHASE);
            end % column_i
            
            % Stimuli location
            if mod(numColumn,2) == 0        % In the case that the number of column is even
                for row_i = 1:1:numRow
                    for column_i = 1:1:numColumn
                        centerLoc{numColumn*(row_i-1)+column_i} =...
                            [hBlockSize*(column_i-numColumn/2) - hBlockSize/2,...
                            blockSize/2 + blockSize*(row_i-1) + blockSize/2 - (blockSize/2*(2*numRow+1)/2)];
                    end % row_i
                end % column_i
            elseif mod(numColumn,2) ~= 0    % In the case that the number of column is odd
                for row_i = 1:1:numRow
                    for column_i = 1:1:numColumn
                        centerLoc{numColumn*(row_i-1)+column_i} =...
                            [hBlockSize*(column_i-(floor(numColumn/2)+1)),...
                            blockSize/2 + blockSize*(row_i-1) + blockSize/2 - (blockSize/2*(2*numRow+1)/2)];
                    end % row_i
                end % column_i
            end
            % Frequencies and phases
            fprintf('BCI-STIM: Stimulation frequencies and phases are...\n');
            for row_i = 1:1:numRow
                fprintf('BCI-STIM: ');
                for column_i = 1:1:numColumn
                    targ_i = numColumn*(row_i-1)+column_i;
                    fprintf('[%f, %.1fpi], ', stimFreq{targ_i}, stimPhase{targ_i}/pi);
                end % row_i
                fprintf('\n');
            end % column_i
            
            % Symbols
            fprintf('BCI-STIM: Symbols for each target are...\n');
            for row_i = 1:1:numRow
                fprintf('BCI-STIM: ');
                for column_i = 1:1:numColumn
                    targ_i = numColumn*(row_i-1)+column_i;
                    fprintf('"%s", ', symbol{targ_i});
                end % row_i
                fprintf('\n');
            end % column_i
            
            design = struct('ModelName' ,spellerMode,...
                'NumTarg'   ,numTarg,...
                'StimShape' ,stimShape,...
                'LenCode'   ,round(lenCode),...
                'MinFreq'   ,minFreq,...
                'FreqResol' ,freqResol,...
                'StimFreq'  ,{stimFreq},...
                'StimPhase' ,{stimPhase},...
                'FlickCode' ,{flickCode},...
                'LenSide'   ,lenSide,...
                'CenterLoc' ,{centerLoc},...
                'Symbol'    ,{symbol},...
                'fbSymbol'  ,{fbSymbol},...
                'wTxtFld'   ,{wTxtFld},...
                'hTxtFld'   ,{hTxtFld},...
                'LocTxtFld' ,{locTxtFld},...
                'NumRow'    ,{numRow},...
                'NumColumn' ,{numColumn},...
                'EraseTarg' ,{eraseTarg},...
                'EnterTarg' ,{enterTarg},...
                'NameAudio' ,{nameAudio});
        end % - END exp_GenStimDesign
        
        function code = exp_GenFlickerCode(~,clen, freq, refresh, varargin)
        % EXP_GENFLICKERCODE generates the flash sequency for each stimuli
        % based on the frequency, waveform type and refreshrate of the
        % monitor.
            if nargin < 2 || isempty(clen)
                error('stats:exp_GenFlickerCode:InputSizeMismatch', 'CLEN, FREQ, REFRESH are required.');
            elseif nargin < 3 || isempty(freq)
                error('stats:exp_GenFlickerCode:InputSizeMismatch', 'FREQ, REFRESH are required.');
            elseif nargin < 4 || isempty(refresh)
                error('stats:exp_GenFlickerCode:InputSizeMismatch', 'REFRESH is required.');
            end % if
            % Select a stimulation signal type
            if nargin < 5 || isempty(varargin{1})
                type = 'sinusoid';
            elseif ischar(varargin{1})
                types = {'sinusoid', 'square'};
                type_i = strmatch(lower(varargin{1}), types);
                if length(type_i) > 1
                    error('stats:exp_GenFlickerCode:BadType', 'Ambiguous value for TYPE: %s', varargin{1});
                elseif isempty(type_i)
                    error('stats:exp_GenFlickerCode:BadType', 'Unknown value for TYPE: %s', varargin{1});
                end % if
                type = types{type_i};
            else
                error('stats:exp_GenFlickerCode:BadType', 'TYPE must be a string.');
            end % if
            
            % Set phase [0 2*pi]
            if nargin < 6 || isempty(varargin{2})
                phase = 0;
            elseif isnumeric(varargin{2})
                phase = wrapTo2Pi(varargin{2});
            end % if
            
            switch type
                
                % Generate flicker code based on square wave
                case 'square'
                    if nargin < 7 || isempty(varargin{3})
                        duty = 50;
                    elseif isnumeric(varargin{3})
                        duty = varargin{2};
                    else
                        error('stats:exp_GenFlickerCode:BadDuty','DUTY must be a number.');
                    end % if
                    
                    index = 0:1:clen-1;
                    tmp = square(2*pi*freq*(index/refresh)+phase, duty);
                    code = (tmp>=0);
                    
                    % Generate flicker code based on sampled sinusoidal wave
                case 'sinusoid'
                    index = 0:1:clen-1;
                    tmp = sin(2*pi*freq*(index/refresh)+phase);
                    %tmp = cos(2*pi*freq*(index/refresh)+phase);
                    code = (tmp+1)/2;
                    
            end % switch model
        end % END exp_GenFlickerCode
        
        function exp_preloadStimuli(self,type, winObj, design, param)
        % EXP_PRELOADSTIMULI preloads the rectanular squares and text for
        % each frame and for each stimuli and draws them on the offscreen,
        % such that the pre-drawn screens can be easily flipped into view.
            Screen(winObj, 'TextColor', param.TextColor);
            Screen(winObj, 'TextFont', param.TextFont);
            Screen(winObj, 'TextSize', param.TextSize);
            
            %Screen('FillRect', winObj, param.FrameColor, design.txtFldLoc);
            for targ_i = 1:1:design.NumTarg
                
                % Set code
                if strcmp(type, 'stimuli')
                    fillColor = repmat(param.FillColor(targ_i),1,3)*255;
                    frameColor = repmat(param.FrameColor(targ_i),1,3)*255;
                elseif strcmp(type, 'blank')
                    fillColor = param.FillColor;
                    frameColor = param.FrameColor;
                end
                
                % Present stimuli
                Screen('FillRect', winObj, fillColor, design.StimLoc{targ_i});
                Screen('FrameRect', winObj, frameColor, design.StimLoc{targ_i});   % Draw rectangle
                if(self.wordPredictionMode && targ_i <= 9)
                    Screen(winObj, 'TextSize', self.SM_FONT_SIZE);
                else
                    Screen(winObj, 'TextSize', self.FONT_SIZE);
                end
                Screen('DrawText', winObj, design.Symbol{targ_i}, design.TextLocX{targ_i}, design.TextLocY{targ_i}, param.TextColor);  % Draw text
                
                
            end % targ_i
            
            % Draw text field for visual feedback
%             Screen('FillRect', winObj, [255, 255, 255], design.TxtFldLoc);
            
            % Set feedback text location
%             Screen('DrawText', winObj, '>>', design.TxtLocX, design.TxtLocY, [0, 0, 0]);
            
        end % END exp_preloadStimuli
        
        function exp_visualFeedback(self,winObj, design, target, fillColor, frameColor, fontColor, fb_seq, copy_seq)
        % EXP_VISUALFEEDBACK is a fucntion that changes the parameters of a
        % single stimulus target (specified by target), such that it can be
        % used to provide visual feedback to the user. it also changes the
        % text box to display the new feedback character and cue char. 
            if nargin > 7 && ~isempty(copy_seq) % copy speller mode
                Screen('FillRect', winObj, fillColor, design.StimLoc{target}); % highlight the selected target square
                Screen('FrameRect', winObj, frameColor, design.StimLoc{target}); % highligh border of selected target
                Screen('DrawText', winObj, design.Symbol{target}, design.TextLocX{target}, design.TextLocY{target}, fontColor); % re-draw text of target
                % text window feedback
%                 Screen('FillRect', winObj, [255, 255, 255], design.TxtFldLoc); % fill in text feedback window with white
%                 Screen(winObj, 'TextSize', self.FONT_SIZE); % always have TextWindow text regular size
%                 Screen('DrawText', winObj, ['>>' copy_seq], design.TxtLocX, design.TxtLocY-diff(design.TxtFldLoc([2,4]))/4, [0, 0, 0]);  
%                 Screen('DrawText', winObj, ['>>' fb_seq], design.TxtLocX, design.TxtLocY+diff(design.TxtFldLoc([2,4]))/4, [0, 0, 0]);
            else % - free spell mode
                Screen('FillRect', winObj, fillColor, design.StimLoc{target});
                Screen('FrameRect', winObj, frameColor, design.StimLoc{target});
                Screen('DrawText', winObj, design.Symbol{target}, design.TextLocX{target}, design.TextLocY{target}, fontColor);
%                 % text window feedback
%                 Screen(winObj, 'TextSize', self.FONT_SIZE); % always have TextWindow text regular size
%                 Screen('FillRect', winObj, [255, 255, 255], design.TxtFldLoc);
%                 Screen('DrawText', winObj, ['>>' fb_seq], design.TxtLocX, design.TxtLocY, [0, 0, 0]); 
            end
        end % END exp_visualFeedback
        %------------------------------------------------------------------  
    end
    
    
end
