using OrderedCollections

function fortran_parse(str)
    fdata = Fortran90Namelists.FortranToJulia.FortranData(str)
    for types in [Int, Float64, Bool, String]
        try
            return Fortran90Namelists.parse(types, fdata)
        catch
        end 
    end
end

#= ==== =#
#  READ  #
#= ==== =#
"""
    readnml(filename::String; verbose=false)::AbstractDict

Parse fortran namelist in given filename and returns data in nested dictionary structure

NOTE: This parser has the following known limitations (which may be fixed in the future):
- Cannot handle vector indexes ==> we should use sparsearrays
- Cannot handle multidimensional arrays
- Cannot handle complex numbers
- Cannot handle `!` `;` `#` in strings
- Cannot handle 1.0+0 exponential notation
- Will completely neglect comments
- Will completely neglect text outside of namelist delimiters

These limitations can easily be seen by running regression tests.
Still, even with limited functionalites this should cover most common FORTRAN namelist usage.
"""
function readnml(filename::String; verbose=false)::AbstractDict
    open(filename, "r") do io
        readnml(io; verbose=verbose)
    end
end

function readnml(io::IO; verbose=false)
    data = OrderedDict()
    readnml!(io, data; verbose=verbose)
end

function readnml!(io, data; verbose=false)

    tk = Tokenize.Tokenizer()

    h = data
    
    for line in eachline(io)
        # skip comments or empty lines
        line = split(line, ";")[1]
        line = split(line, "!")[1]
        line = split(line, "#")[1]
        line = strip(line)
        if length(line) == 0
            continue
        end
        line = replace(line, "\$" => "&")
        line = replace(line, r"^&$" => "/")
        line = replace(line, "&end" => "/")

        # remove spaces
        item = [k for k in Tokenize.lex(tk, line) if length(strip(strip(k), ',')) > 0]
        
        if verbose print(strip(line) * " ") end
        
        # open of namelist
        if item[1] == "&"
            if ! (item[2] in keys(h))
                h[Symbol(item[2])] = OrderedDict()
                h[Symbol(item[2])][:parent] = h
            end
            h = h[Symbol(item[2])]

        # close of namelist
        elseif item[1] == "/"
            child = h
            h = child[:parent]
            delete!(child, :parent)

        # parsing of elements
        elseif (h !== data)
            if (item[2] == "=")
                # simple values
                if length(item) == 3
                    value = fortran_parse(item[3])

                # arrays (handles repetitions)
                else
                    tmp = item[3:end]
                    value = Any[]
                    for k in 1:length(tmp)
                        if (k - 1 > 1) && (tmp[k - 1] == "*")
                        elseif tmp[k] == "*"
                        elseif (k + 1 < length(tmp)) && (tmp[k + 1] == "*")
                            for reps in 1:Int(fortran_parse(tmp[k]))
                                push!(value, fortran_parse(tmp[k + 2]))
                            end
                        else
                            push!(value, fortran_parse(tmp[k]))
                        end
                    end
                    value = collect(promote(value...))
                end
                h[Symbol(item[1])] = value
                if verbose print("[$(typeof(value))] -> $(value)") end
            else
                if verbose print("[SKIP index]") end
            end
        else
            if verbose print("[SKIP outside]") end
        end
        if verbose println() end
    end

    return data
end

#= ===== =#
#  WRITE  #
#= ===== =#

"""
    writenml(filename::String, data::AbstractDict; verbose=false)::String

Write nested dictionary structure as fortran namelist to a given filename

NOTE: For a list of known limitations look at the help of readnml()
"""
function writenml(filename::String, data::AbstractDict; verbose=false)::String
    open(filename, "w") do io
        writenml(io, data; verbose=verbose)
    end
end

function writenml(io::IO, data::AbstractDict; verbose=false)
    txt = []

    for nml in keys(data)
        push!(txt, "&$(nml)")
        for (item, value) in data[nml]
            if typeof(value) <: Vector
                frtn_string = join(map(x -> JuliaToFortran.to_fortran(x).data, value), " ")
            else
                frtn_string = JuliaToFortran.to_fortran(data[nml][item]).data
            end
            push!(txt, "$(item) = $(frtn_string)")
        end
        push!(txt, "/")
    end
    txt = join(txt, "\n")

    if verbose println(txt) end

    write(io, txt)

    return txt
end
