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

    @testset "custom background frequencies" begin
        pfm = [0.7 0.1; 0.1 0.7; 0.1 0.1; 0.1 0.1]
        bg  = [0.3, 0.2, 0.2, 0.3]
        buf = IOBuffer()
        @test logoshow(buf, pfm; background=bg) === nothing
        @test length(String(take!(buf))) > 0
        # PWM wrapper with background
        w = PWM(pfm; background=bg)
        buf2 = IOBuffer()
        show(buf2, MIME("text/plain"), w)
        @test occursin("PWM", String(take!(buf2)))
    end

    @testset "output structure" begin
        pfm = [0.9 0.05; 0.05 0.9; 0.025 0.025; 0.025 0.025]
        buf = IOBuffer()
        logoshow(buf, pfm)
        output = String(take!(buf))
        # y-axis: IC labels and separator
        @test occursin("│", output)
        @test occursin("└", output)
        # ANSI colour codes present (24-bit fg)
        @test occursin("\e[38;2;", output)
        # correct number of newlines = height + 1 (x-axis line)
        height = 5
        @test count('\n', output) == height + 1
    end

    @testset "wrong PFM size throws" begin
        bad_pfm = [0.5 0.5; 0.5 0.5; 0.0 0.0]   # 3 rows, not 4
        @test_throws AssertionError logoshow(IOBuffer(), bad_pfm)
    end

    @testset "compact show method" begin
        pfm = [0.9 0.1; 0.02 0.8; 0.05 0.05; 0.03 0.05]
        w = PWM(pfm)
        buf = IOBuffer()
        show(buf, w)
        @test String(take!(buf)) == "PWM(4×2)"
    end

    # ── Multi-logo tests ─────────────────────────────────────
    @testset "multi-logo without names" begin
        pfm1 = [0.7 0.1; 0.1 0.7; 0.1 0.1; 0.1 0.1]
        pfm2 = [0.1 0.8; 0.8 0.1; 0.05 0.05; 0.05 0.05]
        buf = IOBuffer()
        @test logoshow(buf, [pfm1, pfm2]) === nothing
        output = String(take!(buf))
        @test length(output) > 0
        # auto-numbered titles
        @test occursin("Motif 1", output)
        @test occursin("Motif 2", output)
    end

    @testset "multi-logo with names" begin
        pfm1 = [0.7 0.1; 0.1 0.7; 0.1 0.1; 0.1 0.1]
        pfm2 = [0.1 0.8; 0.8 0.1; 0.05 0.05; 0.05 0.05]
        buf = IOBuffer()
        @test logoshow(buf, [pfm1, pfm2]; names=["TATA", "SP1"]) === nothing
        output = String(take!(buf))
        @test occursin("TATA", output)
        @test occursin("SP1", output)
    end

    @testset "multi-logo per_row wrapping" begin
        pfm = [0.7 0.1; 0.1 0.7; 0.1 0.1; 0.1 0.1]
        pfms = [pfm, pfm, pfm, pfm, pfm]
        buf = IOBuffer()
        @test logoshow(buf, pfms; per_row=2) === nothing
        output = String(take!(buf))
        # should have all 5 motif titles
        for i in 1:5
            @test occursin("Motif $i", output)
        end
    end

    @testset "multi-logo single element" begin
        pfm = [0.7 0.1; 0.1 0.7; 0.1 0.1; 0.1 0.1]
        buf = IOBuffer()
        @test logoshow(buf, [pfm]; names=["Only"]) === nothing
        @test occursin("Only", String(take!(buf)))
    end

    @testset "multi-logo mismatched names throws" begin
        pfm = [0.7 0.1; 0.1 0.7; 0.1 0.1; 0.1 0.1]
        @test_throws AssertionError logoshow(IOBuffer(), [pfm, pfm]; names=["one"])
    end

    @testset "multi-logo empty vector throws" begin
        @test_throws AssertionError logoshow(IOBuffer(), Matrix{Float64}[])
    end
end
