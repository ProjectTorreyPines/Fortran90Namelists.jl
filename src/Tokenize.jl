"""
# module Tokenize



# Examples

```jldoctest
julia>
```
"""
module Tokenize

using Compat: isnothing
using IterTools: takewhile
using Parameters: @with_kw

export Tokenizer,
    update_chars,
    parse_name,
    parse_string,
    parse_numeric

const PUNCTUATION = raw"=+-*/\\()[]{},:;%&~<>?`|$#@"
const WHITESPACE = raw" \t\r\x0b\x0c"

@with_kw mutable struct Tokenizer
    characters = nothing
    prior_char::Union{Nothing, AbstractChar} = nothing
    char::Union{Nothing, AbstractChar} = nothing
    idx::Int = 0
    prior_delim::Union{Nothing, AbstractChar} = nothing
    group_token::Union{Nothing, AbstractChar} = nothing  # Set to true if inside a namelist group
end  # struct Tokenizer

"""
    update_chars(tk::Tokenizer)

Update the current charters in the tokenizer.
"""
function update_chars(tk::Tokenizer)
    tk.prior_char, tk.char = tk.char, next(tk.characters, '\n')
    tk.idx += 1
end  # function update_chars

function Base.parse(tk::Tokenizer, line)
    tokens = []
    tk.idx = 0   # Bogus value to ensure idx = 1 after first iteration
    tk.characters = Iterators.Stateful(line)  # An iterator generated by `line`
    update_chars(tk)

    while tk.char != '\n'  # NOTE: Cannot be "\n", which is a string!
        # Update namelist group status
        occursin(tk.char, raw"&$") && (tk.group_token = tk.char)

        if !isnothing(tk.group_token) && ((tk.group_token, tk.char) in (('&', '/'), ('$', '$')))
            tk.group_token = nothing  # A group (namelist) ends
        end

        word = ""  # Initialize or clear `word` if exists
        # Ignore whitespace
        if occursin(tk.char, WHITESPACE)  # " \t\r\x0b\x0c"
            while occursin(tk.char, WHITESPACE)
                word *= tk.char  # Read one char to `word`
                update_chars(tk)  # Read the next char until meet a non-whitespace char
            end
        # Ignore comment
        elseif occursin(tk.char, raw"!#") || isnothing(tk.group_token)  # Comment line
            # Abort the iteration and build the comment token
            word = line[tk.idx:end - 1]  # Read to end but not '\n'
            tk.char = '\n'  # NOTE: Cannot be "\n", which is a string!
        # Parse string
        elseif occursin(tk.char, raw"\"'") || !isnothing(tk.prior_delim)  # Meet a string
            word = parse_string(tk)
        # Parse variable
        elseif isletter(tk.char)  # Meet a variable
            word = parse_name(tk, line)
        # Meet a sign
        elseif occursin(tk.char, "+-")
            # Lookahead to check for IEEE value
            tk.characters, lookahead = tee(tk.characters)  # FIXME:
            ieee_val = join(takewhile(isletter, lookahead), "")
            if lowercase(ieee_val) in ("inf", "infinity", "nan")  # Meet an nan/infinity
                word = tk.char * ieee_val
                tk.characters = lookahead
                tk.prior_char = ieee_val[end]
                tk.char = next(lookahead, '\n')
            else
                word = parse_numeric(tk)  # Meet a number
            end
        # Meet a number
        elseif isdigit(tk.char)
            word = parse_numeric(tk)
        # Meet a dot
        elseif tk.char == '.'
            update_chars(tk)
            if isdigit(tk.char)
                frac = parse_numeric(tk)  # A fraction of a number
                word = '.' * frac
            else
                word = '.'  # If not followed by a number
                while isletter(tk.char)
                    word *= tk.char
                    update_chars(tk)
                end
                # A word containing `.` ends
                if tk.char == '.'
                    word *= tk.char
                    update_chars(tk)
                end
            end
        # Meet a punctuation
        elseif occursin(tk.char, PUNCTUATION)
            word = tk.char
            update_chars(tk)
        else
            # This should never happen
            error("This should never happen!")
        end
        push!(tokens, word)
    end  # while loop
    return tokens
end  # function Base.parse

"""
    parse_name(tk::Tokenizer, line)

Tokenize a Fortran name, such as a variable or subroutine.
"""
function parse_name(tk::Tokenizer, line::AbstractString)
    endindex = tk.idx
    for char in line[tk.idx:end]
        !isalnum(char) && !occursin(char, raw"'\"_") && break
        endindex += 1
    end

    word = line[tk.idx:endindex - 1]  # Do not include non-alphanumeric and non-'"_ characters in `word`

    tk.idx = endindex - 1  # Do not include non-alphanumeric and non-'"_ characters
    # Update iterator, minus first character which was already read
    # Continue iterating from `length(word)` => drop the first `length(word) - 1` characters
    tk.characters = Iterators.drop(tk.characters, length(word) - 1)
    update_chars(tk)
    return word
end  # function parse_name

"""
    parse_string(tk::Tokenizer)

Tokenize a Fortran string.
"""
function parse_string(tk::Tokenizer)
    word = ""

    if !isnothing(tk.prior_delim)  # A previous quotation mark presents
        delim = tk.prior_delim  # Read until `delim`
        tk.prior_delim = nothing
    else
        delim = tk.char  # No previous quotation mark presents
        word *= tk.char  # Read this character
        update_chars(tk)
    end

    while true
        if tk.char == delim
            # Check for escaped delimiters
            update_chars(tk)
            if tk.char == delim
                word *= repeat(delim, 2)
                update_chars(tk)
            else
                word *= delim
                break
            end
        elseif tk.char == '\n'
            tk.prior_delim = delim
            break
        else
            word *= tk.char
            update_chars(tk)
        end
    end

    return word
end  # function parse_string

"""
    parse_numeric(tk::Tokenizer)

Tokenize a Fortran numerical value.
"""
function parse_numeric(tk::Tokenizer)
    word = ""
    frac = false

    if tk.char == '-'
        word *= tk.char  # `word == "-"``
        update_chars(tk)
    end

    # Read as long as `tk.char` is a digit, or not a dot
    while isdigit(tk.char) || (tk.char == '.' && !frac)
        # Only allow one decimal point
        if tk.char == '.'
            frac = true  # If meet '.', break the loop
        end
        word *= tk.char
        update_chars(tk)
    end

    # Check for float exponent
    if occursin(tk.char, "eEdD")
        word *= tk.char
        update_chars(tk)
    end

    if occursin(tk.char, "+-")
        word *= tk.char
        update_chars(tk)
    end

    while isdigit(tk.char)
        word *= tk.char
        update_chars(tk)
    end

    return word
end  # function parse_numeric

isalnum(c) = isletter(c) || isnumeric(c)

function next(iterable, default)
    x = iterate(iterable)
    isnothing(x) ? default : first(x)
end

end
