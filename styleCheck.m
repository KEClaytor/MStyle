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
%   Automatically fixes errors in place.
%   Use with the -v flag to manually approve each of the suggested fixes.
%   Note: This could introduce errors, you should make sure to run your
%   tests after this.
%
% [1] Implements **some** of "Style Guidelines 2.0":
%   http://www.mathworks.com/matlabcentral/fileexchange/46056-matlab-style-guidelines-2-0
% [2] Requires: getkey from the FEX:
%   http://www.mathworks.com/matlabcentral/fileexchange/7465-getkey
%
% TODO: Configure with "styleCheck -config"

function [eOut] = styleCheck(target, varargin)
    nVargs = length(varargin);
    verbose = false;
    recursive = false;
    fix = false;
    for ii = 1:nVargs
        switch varargin{ii}
            case '-r'
                recursive = true;
            case '-v'
                verbose = true;
            case '-fix'
                fix = true;
            otherwise
                fprintf('Unknown input to styleCheck');
        end
    end
    
    %% Create output structure
    % Start counting
    eOut.Errors = {};
    eOut.McCabe = [];
    eOut.TotalErrors = [];
    eOut.TotalFixes = [];
    
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
        
        %% Now load the files
        % For each line in the file
        fname = target;
        fid = fopen(fname);
        if fix
            fname_out = [target, '.tmp'];
            fid_out = fopen(fname_out, 'w+');
        end
        %% Loop through lines and apply the style elements
        line = fgetl(fid);
        lineNum = 1;
        error_cnts = zeros(1, nsE);
        fix_cnts = zeros(1, nsE);
        while ischar(line) || (line ~= -1)
            % Don't analyze blank lines
            if length(line) >= 1
                if regexp(line, '\s*%', 'once');
                    % Don't analyze comments
                else
                    for ii = 1:nsE
                        rule = sE{ii}.rule;
                        if ischar(rule)
                            % Rule is a regexp, evaluate it
                            % These are incidentally only the ones we know how
                            %   to run replacement rules for.
                            [errInd] = regexp(line, rule);
                            if ~isempty(errInd)
                                if fix
                                    [line, fixed] = report_fix(line, lineNum, errInd, sE{ii}, verbose);
                                    if fixed
                                        fix_cnts(ii) = fix_cnts(ii) + length(errInd);
                                    end
                                else
                                    % Just report
                                    report(line, lineNum, errInd, sE{ii}.reason, verbose);
                                end
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
            % If we're fixing write out the line
            if fix
                fprintf(fid_out, '%s\n', line);     % Write to file
                fprintf('%d\t%s\n', lineNum, line); % Report to the screen
            end
            % Get the next line
            line = fgetl(fid);
            lineNum = lineNum + 1;
        end
        % and report any problems we've found
        % Close the file
        fclose(fid);
        if fix
            % And the temporary file
            fclose(fid_out);
            % Replace the original with the temp file and delte the temp
            [s, m, ~] = movefile(fname_out, fname);
            if s == 0
                fprintf(m);
            end
        end
        
        % Add to the error structure
        eOut.Errors{1}.name = basename;
        for ii = 1:nsE
            eOut.Errors{1}.reason{ii} = sE{ii}.reason;
        end
        eOut.Errors{1}.counts = error_cnts;
        eOut.Errors{1}.fixes = fix_cnts;
        eOut.McCabe = mccabe;
        eOut.TotalErrors = sum(eOut.Errors{1}.counts);
        eOut.TotalFixes = sum(eOut.Errors{1}.fixes);
        
        % Report the tally
        fprintf('File: %s\n\tErrors found: %d\n', ...
            basename, eOut.TotalErrors);
        return;
    end
    
    fprintf('\n\n===============SUMMARY===============\n');
    fprintf('Files analyzed: %d\n', length(eOut.TotalErrors));
    fprintf('Total errors found: %d\n', sum(eOut.TotalErrors));
    fprintf('Total errors fixed: %d\n', sum(eOut.TotalFixes));
    fprintf('Average McCabe complexity: %4.1f\n', mean(eOut.McCabe));
    
    % List things I don't check for yet
    dispUnchecked()
    
end

%% Add the recursively returned structure to the next higher level
function eOut = addSubErrors(eOut, eSub)
    % Error structure array
    eOut.Errors = [eOut.Errors, eSub.Errors];
    % Total scalar count
    eOut.McCabe = [eOut.McCabe, eSub.McCabe];
    eOut.TotalErrors = [eOut.TotalErrors, eSub.TotalErrors];
    eOut.TotalFixes = [eOut.TotalFixes, eSub.TotalFixes];
end

%% Report functions
% Report line number, and what the problem is
function report(line, lineNum, inds, reason, verbose)
    indstr = sprintf('%d,', inds);
    fprintf('L %d (C [%s]): %s\n', lineNum, indstr(1:end-1), reason);
    if verbose
        fprintf('%s\n%s\n', ...
            line(1:min([80, length(line)])), ...
            make_error_string(inds));
    end
end

% Report line number, and what the problem is
function [line, fixed] = report_fix(line, lineNum, inds, se, verbose)
    % Get the fixed line
    newline = regexprep(line, se.rule, se.replacement);
    % Report and wait for user input
    indstr = sprintf('%d,', inds);
    fprintf('Replace Line [y/{n}] %d (C [%s]): %s\n', ...
        lineNum, indstr(1:end-1), se.reason);
    fprintf('%s\n%s\n', ...
        line(1:min([80, length(line)])), ...
        make_error_string(inds));
    fprintf('%s\n', newline);
    
    fixed = false;
    if verbose
        % Ask for permission
        k = getkey();
        if k == 121 % ='y'
            fixed = true;
        end
    else
        % Otherwise just replace
        fixed = true;
    end
    if fixed
        line = newline;
        fprintf('Line replaced.\n');
    end
end

function echar = make_error_string(ind)
    echar = sprintf('%s^', repmat('-', [1, ind(1)]));
    for ii = 2:length(ind)
        echar = [echar,...
            sprintf('%s^', repmat('-', [1, ind(ii)-ind(ii-1)-1]))];	%#ok
    end
end

%% Get style elements to check for
function [sE, ii] = getStyleElements()
    
    % Grab all style elements from our configuration
    sE = cell(1);
    ii = 1;
    
    % Missing left space
    sE{ii}.rule = @(x) length(x)>80;
    sE{ii}.replacement = @(x) x;
    sE{ii}.reason = 'Lines should not exceed 80 characters.';
    ii = ii + 1;
    
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
