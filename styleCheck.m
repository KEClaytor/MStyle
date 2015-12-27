%% Function to evaluate MATLAB code for style
% styleCheck
%   Evaluates MATLAB code for style, according to [1].
% [problems] = styleCheck(file)
%   Examines only file for style correctness.
% [problems] = styleCheck(directory)
%   Examines all of the *.m files in directory for style correctness.
% [problems] = styleCheck(directory '-r')
%   Recursively search through child directories. Note, you should either
%   give it directories on the path, or specify a full directory path.
% [problems] = styleCheck(directory, '-v')
%   Print out problems to the screen (default).
% [problems] = styleCheck(directory, '-fix')
%   TODO: Fixes errors in place. Note: This could introduce errors, you
%   should make sure to run your tests after this.
%
% [1] Implements some of "Style Guidelines 2.0":
%   http://www.mathworks.com/matlabcentral/fileexchange/46056-matlab-style-guidelines-2-0
%
% TODO: Configure with "styleCheck -config"

function [eOut] = styleCheck(target, varargin)
    nVargs = length(varargin);
    verbose = false;
    recursive = false;
    for ii = 1:nVargs
        switch varargin{ii}
            case '-r'
                recursive = true;
            case '-v'
                verbose = true;
            otherwise
                fprintf('Unknown input to styleCheck');
        end
    end
    
    %% Create output structure
    % Start counting
    eOut.Errors = {};
    eOut.McCabe = [];
    eOut.TotalErrors = [];
    
    %% Target handling - directory, vs. file
    % Check to see if we were passed a directory, or a file?
    % target = dir(input);
    % returns a directory structure, or a single filename
    
    if exist(target, 'dir')
        curdir = dir(target);
        % Check each element in target
        for ii = 1:length(curdir)
            % Are we a directory? If so do we want recursion?
            newtarget = fullfile(target, curdir(ii).name);
            if curdir(ii).isdir
                switch curdir(ii).name
                    case {'.','..'}
                        % Do nothing
                    otherwise
                        if recursive
                            eSub = styleCheck(newtarget, varargin{:});
                            eOut = addSubErrors(eOut, eSub);
                        end
                end
            else
                [~, ~, ext] = fileparts(curdir(ii).name);
                switch ext
                    case {'.m'}
                        eSub = styleCheck(newtarget, varargin{:});
                        eOut = addSubErrors(eOut, eSub);
                    otherwise
                        fprintf('Skipping: %s\n', curdir(ii).name);
                end
                
            end
        end
    else
        %% Found a file, parse it and get results
        [~, basename, ext] = fileparts(target);
        switch ext
            case {'.m'}
                % OK - continue.
            otherwise
                % How'd we get here? Inform, but don't eval and then return.
                fprintf('Tried to scan %s - returning.\n', target)
                return;
        end
        fprintf('\nEvaluating: %s\n', target)
        
        % Did we want to run the matlab code checker?
        fprintf('Running MATLAB code checker...\n');
        checkcode(target);
        %
        %     if strcmpi(basename, 'lamp');
        %         disp('pause')
        %     end
        
        % Compute the McCabe complexity
        ccresult = checkcode(target, '-cyc');
        mccabe = 0;
        if ~isempty(ccresult)
            for ii = 1:length(ccresult)
                s = ccresult(ii).message;
                mccabe = mccabe + sum(str2double(regexp(s, '\d*', 'match')));
            end
        end
        fprintf('McCabe Complexity: %d\n', mccabe)
        fprintf('...done.\n');
        
        % Loop through all of our checks
        [sE, nsE] = getStyleElements();
        
        % For each line in the file
        fname = target;
        fid = fopen(fname);
        
        %% Loop through lines and apply the style elements
        line = fgetl(fid);
        lineNum = 1;
        error_cnts = zeros(1, nsE);
        while ischar(line) || (line ~= -1)
            % Skip blank lines
            if length(line) >= 1
                % Skip comments
                if regexp(line, '\s+%') == 1;
                    for ii = 1:nsE
                        rule = sE{ii}.rule;
                        if ischar(rule)
                            % Rule is a regexp, evaluate it
                            [errInd] = regexp(line, rule);
                            if ~isempty(errInd)
                                report(line, lineNum, errInd, sE{ii}.reason, verbose);
                                error_cnts(ii) = error_cnts(ii) + length(errInd);
                            end
                        else
                            % Apply the rule
                            if sE{ii}.rule(line)
                                % Currently, the only rule is line length 80.
                                % TODO: Modify the errInd off of the hardcode value here
                                report(line, lineNum, 80, sE{ii}.reason, verbose);
                                error_cnts(ii) = error_cnts(ii) + 1;
                            end
                        end
                    end
                end
            end
            % Get the next line
            line = fgetl(fid);
            lineNum = lineNum + 1;
        end
        % and report any problems we've found
        % Close the file
        fclose(fid);
        
        % Add to the error structure
        eOut.Errors{1}.name = basename;
        for ii = 1:nsE
            eOut.Errors{1}.reason{ii} = sE{ii}.reason;
        end
        eOut.Errors{1}.counts = error_cnts;
        eOut.McCabe = mccabe;
        eOut.TotalErrors = sum(eOut.Errors{1}.counts);
        
        % Report the tally
        fprintf('File: %s\n\tErrors found: %d\n', basename, eOut.TotalErrors);
        return;
    end
    
    fprintf('\n\n===============SUMMARY===============\n');
    fprintf('Files analyzed: %d\n', length(eOut.TotalErrors));
    fprintf('Total errors found: %d\n', sum(eOut.TotalErrors));
    fprintf('Average McCabe complexity: %4.1f\n', mean(eOut.McCabe));
    
    % List things I don't check for yet
    dispUnchecked()
    
end

%% Add the recursively returned structure to the next higher level
function eOut = addSubErrors(eOut, eSub)
    % Skip if we have the results for a directory?
    % if ~isstruct(eOut.Errors{1}.filename)
    % Error structure array
    eOut.Errors = [eOut.Errors, eSub.Errors];
    % Total scalar count
    eOut.McCabe = [eOut.McCabe, eSub.McCabe];
    eOut.TotalErrors = [eOut.TotalErrors, eSub.TotalErrors];
    % end
end

%% Report function
% Report line number, and what the problem is
function report(line, lineNum, ind, reason, verbose)
    for ii = 1:length(ind)
        fprintf('L %d (C %d): %s\n', lineNum, ind(ii), reason);
        if verbose
            fprintf('%s\n%s^\n', ...
                line(1:min([80, length(line)])), ...
                repmat('-', [1, ind(ii)-1]));
        end
    end
end

%% Get style elements to check for
function [sE, ii] = getStyleElements()
    
    % Grab all style elements from our configuration
    sE = cell(1);
    ii = 1;
    
    
    % Note the first bit of each:
    
    % Whitespace around comparisons (=, >=, etc), commas, logical operators.
    % Missing left space
    sE{ii}.rule = '(?<=[\w\]])(?<ls>[~&|<>=]*)';
    sE{ii}.replacement = ' $<ls>';
    sE{ii}.reason = 'Comparisons should begin with whitespace.';
    ii = ii + 1;
    % Missing right space - include commas in this
    sE{ii}.rule = '(?<rs>[&|<>=]*)(?=[\w\[\]])';
    sE{ii}.replacement = '$<rs> ';
    sE{ii}.reason = 'Comparisons should end with whitespace.';
    ii = ii + 1;
    % Missing dual space is covered by applying left or right spaces
    
    % Missing right space after comma
    sE{ii}.rule = '(?<rs>[,])(?=[\w\[\]])';
    sE{ii}.replacement = '$<rs> ';
    sE{ii}.reason = 'Commas should be followed by whitespace.';
    ii = ii + 1;
    
    % Remove 2+ spaces unless followed by an inline comment
    sE{ii}.rule = '(?<=[\w=])\s{2,}(?=[\w\.][^%])';
    sE{ii}.replacement = ' ';
    sE{ii}.reason = 'Avoid 2+ spaces (excluding indents & inline comments).';
    
    % Check for a comment header to the file
    % Check for left hand zeros
    % Check that i/j are not being used as loop variables (suggest ii, jj)
    
    % Lines are too long
    sE{ii}.rule = @(x) length(x)>80;
    sE{ii}.replacement = @(x) x;
    sE{ii}.reason = 'Lines should not exceed 80 characters.';
    ii = ii + 1;
end

%% List of things not yet checked for:
function dispUnchecked()
    fprintf('\nThings not checked:\n')
    fprintf('\t> Anything in a comment is ignored.\n');
    fprintf('\t> Header comments to be read with help <filename>.\n');
    fprintf('\t> Variable names should be legible.\n');
    fprintf('\t> Reduce 3 or more blank lines to 2 blank lines (use cells).\n');
    fprintf('\t> Proofread indentation (hit ctrl-a ctrl-i).\n');
    fprintf('\t> Source control (svn, git, hg, etc.).\n')
end
