%% Function to evaluate MATLAB code for style
% styleCheck(file)
%   Prints all your problems to the screen.
% [problems] = styleCheck(file)
%   Returns a string with your problems in it.
% [problems] = styleCheck(directory)
%   Cell array with each element corresponding to a file in the directory.
%   If the directory contains sub-directories, these will be recursively
%   searched. The sub-directories will appear as a cell array within the
%   parent cell array.
%
% Generally uses the styleguide espoused in "Style Guidelines 2.0":
%   http://www.mathworks.com/matlabcentral/fileexchange/46056-matlab-style-guidelines-2-0
%
% Configured with "styleCheck configure"

function [n_err_tot] = styleCheck(target)
    verbose = true;
    recursive = false;
    
    n_err_tot = 0;
    
    fprintf('\nEvaluating: %s\n', target)
    % Did we want to run the matlab code checker?
    fprintf('Running MATLAB code checker...\n');
    checkcode(target);
    fprintf('...done.\n');
    
    % Loop through all of our checks
    [sE, nsE] = getStyleElements();
    
    % For each line in the file
    fname = target;
    % fname = 'resort_crosstab.m';
    fid = fopen(fname);
    
    %% Loop through lines and apply the style elements
    line = fgetl(fid);
    lineNum = 1;
    while ischar(line) || (line ~= -1)
        % Skip blank lines
        if length(line) >= 1
            % Skip comments
            if ~strcmp(line(1), '%')
                for ii = 1:nsE
                    rule = sE{ii}.rule;
                    if ischar(rule)
                        % Rule is a regexp, evaluate it
                        [errInd] = regexp(line, rule);
                        if ~isempty(errInd)
                            report(line, lineNum, errInd, sE{ii}.reason, verbose);
                            n_err_tot = n_err_tot + 1;
                        end
                    else
                        % Apply the rule
                        if sE{ii}.rule(line)
                            % Currently, the only rule is line length 80.
                            % TODO: Modify the errInd off of the hardcode value here
                            report(line, lineNum, [80], sE{ii}.reason, verbose);
                            n_err_tot = n_err_tot + 1;
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
    
    % Report the tally
    fprintf('File: %s\n\tErrors found: %d\n', fname, n_err_tot);
    return;
    
    % List things I don't check for yet
    dispUnchecked()
    
end

%% Report function
% Report line number, and what the problem is
function report(line, lineNum, ind, reason, verbose)
    for ii = 1:length(ind)
        fprintf('Line %d (%d): %s\n', lineNum, ind(ii), reason);
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
