using PWMPrettyPrint
using Test

@testset "PWMPrettyPrint.jl" begin
    @testset "logoshow runs without error" begin
        pfm = [0.7 0.1 0.1 0.5;
               0.1 0.8 0.1 0.2;
               0.1 0.05 0.7 0.2;
               0.1 0.05 0.1 0.1]
        buf = IOBuffer()
        @test logoshow(buf, pfm) === nothing
        output = String(take!(buf))
        @test length(output) > 0
        # should contain position labels
        @test occursin("1", output)
        @test occursin("4", output)
    end

    @testset "PWM wrapper display" begin
        pfm = [0.9 0.1; 0.02 0.8; 0.05 0.05; 0.03 0.05]
        w = PWM(pfm)
        buf = IOBuffer()
        show(buf, MIME("text/plain"), w)
        output = String(take!(buf))
        @test occursin("PWM", output)
        @test occursin("DNA", output)
    end

    @testset "RNA mode" begin
        pfm = [0.7 0.1; 0.1 0.8; 0.1 0.05; 0.1 0.05]
        buf = IOBuffer()
        @test logoshow(buf, pfm; rna=true) === nothing
        w = PWM(pfm; rna=true)
        buf2 = IOBuffer()
        show(buf2, MIME("text/plain"), w)
        @test occursin("RNA", String(take!(buf2)))
    end

    @testset "custom height and width" begin
        pfm = [0.7 0.1 0.1; 0.1 0.8 0.1; 0.1 0.05 0.7; 0.1 0.05 0.1]
        buf = IOBuffer()
        @test logoshow(buf, pfm; height=12, col_width=6) === nothing
    end

    @testset "uniform column (no IC) renders without error" begin
        pfm = [0.25 0.9; 0.25 0.02; 0.25 0.05; 0.25 0.03]
        buf = IOBuffer()
        @test logoshow(buf, pfm) === nothing
    end
end
