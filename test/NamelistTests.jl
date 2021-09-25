module Mod

using Test

using Fortran90Namelists

debug_mode = false

filenames = [joinpath(dirname(@__FILE__),"data",filename) for filename in readdir(joinpath(dirname(@__FILE__), "data"))]

for filename in filenames
    @testset "Test $(basename(filename))" begin
        data_read = readnml(filename; verbose=debug_mode)
        @test data_read !== nothing
        string_write = writenml(tempname(), data_read; verbose=debug_mode)
        @test string_write !== nothing
    end
end

end