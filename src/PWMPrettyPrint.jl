module PWMPrettyPrint

export logoshow, PWM

# ══════════════════════════════════════════════════════════════
#  Glyph polygon data (from EntroPlots.jl / gglogo)
# ══════════════════════════════════════════════════════════════
include("glyphs.jl")

# ══════════════════════════════════════════════════════════════
#  Information-content helpers
# ══════════════════════════════════════════════════════════════

function ic_column(col, bg; ϵ=1e-20)
    col .* log2.((col .+ ϵ) ./ bg)
end

function total_ic(col; bg=fill(0.25, length(col)))
    sum(ic_column(col, bg))
end

# ══════════════════════════════════════════════════════════════
#  Colour palettes – vivid, classic logo colours
# ══════════════════════════════════════════════════════════════

const DNA_COLORS = Dict(
    'A' => (0,   200,  50),   # green
    'C' => (20,  100, 220),   # blue
    'G' => (230, 160,   0),   # amber
    'T' => (220,  20,  20),   # red
)
const RNA_COLORS = Dict(
    'A' => (0,   200,  50),
    'C' => (20,  100, 220),
    'G' => (230, 160,   0),
    'U' => (220,  20,  20),
)

const DNA_LETTERS = ['A', 'C', 'G', 'T']
const RNA_LETTERS = ['A', 'C', 'G', 'U']

# ══════════════════════════════════════════════════════════════
#  ANSI 24-bit colour helpers
# ══════════════════════════════════════════════════════════════

_fg(r, g, b) = "\e[38;2;$(r);$(g);$(b)m"
_bg(r, g, b) = "\e[48;2;$(r);$(g);$(b)m"
const RESET   = "\e[0m"

# ══════════════════════════════════════════════════════════════
#  Braille sub-pixel layout
# ══════════════════════════════════════════════════════════════
#
#  Each braille character cell = 2 columns × 4 rows of dots.
#  Unicode U+2800 + bitmask, where:
#
#    col 0 (left)   col 1 (right)
#      dot1 (bit0)    dot4 (bit3)   ← pixel row 0 (top)
#      dot2 (bit1)    dot5 (bit4)   ← pixel row 1
#      dot3 (bit2)    dot6 (bit5)   ← pixel row 2
#      dot7 (bit6)    dot8 (bit7)   ← pixel row 3 (bottom)
#
#  So a (sub_row, sub_col) pixel maps to:

const BRAILLE_BIT = (
    # sub_col=0 (left)          sub_col=1 (right)
    (0, 3),   # sub_row 0
    (1, 4),   # sub_row 1
    (2, 5),   # sub_row 2
    (6, 7),   # sub_row 3
)

# ══════════════════════════════════════════════════════════════
#  Fast binary polygon rasterizer  (1 sample per pixel)
# ══════════════════════════════════════════════════════════════

function point_in_polygon(px::Float64, py::Float64,
                          vx::Vector{Float64}, vy::Vector{Float64})
    inside = false
    j = length(vx)
    @inbounds for i in eachindex(vx)
        yi, yj = vy[i], vy[j]
        xi, xj = vx[i], vx[j]
        if ((yi > py) != (yj > py)) &&
           (px < (xj - xi) * (py - yi) / (yj - yi) + xi)
            inside = !inside
        end
        j = i
    end
    inside
end

# Cache: (letter, rows, cols) → BitMatrix
const _GLYPH_CACHE = Dict{Tuple{String,Int,Int}, BitMatrix}()

function get_glyph_bitmap(letter::String, rows::Int, cols::Int)
    get!(_GLYPH_CACHE, (letter, rows, cols)) do
        glyph = get(GLYPHS, letter, nothing)
        glyph === nothing && return falses(rows, cols)
        vx = Float64.(glyph.x)
        vy = Float64.(glyph.y)
        bmp = falses(rows, cols)
        for r in 1:rows
            py = 1.0 - (r - 0.5) / rows
            for c in 1:cols
                px = (c - 0.5) / cols
                bmp[r, c] = point_in_polygon(px, py, vx, vy)
            end
        end
        bmp
    end
end

# ══════════════════════════════════════════════════════════════
#  Canvas: pixel_h × canvas_w grid, each cell = (R,G,B) UInt8
#          (0,0,0) means empty / background
# ══════════════════════════════════════════════════════════════

function _build_canvas(pfm, letters, colors, bg_freq,
                       pixel_h::Int, col_w::Int)
    n_chars  = length(letters)
    n_pos    = size(pfm, 2)
    max_ic   = log2(n_chars)
    canvas_w = col_w * n_pos

    canvas = zeros(UInt8, pixel_h, canvas_w, 3)   # R/G/B planes

    for j in 1:n_pos
        col   = @view pfm[:, j]
        ics   = ic_column(col, bg_freq)
        order = sortperm(ics)          # smallest IC → bottom of stack

        x0       = (j - 1) * col_w + 1
        y_cursor = pixel_h             # start at the very bottom

        for idx in order
            ic_val   = max(ics[idx], 0.0)
            letter_h = round(Int, ic_val / max_ic * pixel_h)
            letter_h <= 0 && continue

            letter    = string(letters[idx])
            r0, g0, b0 = colors[letters[idx]]
            bmp       = get_glyph_bitmap(letter, letter_h, col_w)

            for lr in 1:letter_h
                cr = y_cursor - letter_h + lr
                cr < 1 && continue
                for lc in 1:col_w
                    if bmp[lr, lc]
                        xc = x0 + lc - 1
                        canvas[cr, xc, 1] = r0
                        canvas[cr, xc, 2] = g0
                        canvas[cr, xc, 3] = b0
                    end
                end
            end
            y_cursor -= letter_h
        end
    end

    canvas
end

# ══════════════════════════════════════════════════════════════
#  Render to terminal using braille  (2 px wide × 4 px tall / char)
# ══════════════════════════════════════════════════════════════
#
#  Each printed character cell covers a 2×4 block of canvas pixels.
#  We pick the most-common non-background colour in that block as the
#  foreground, then encode all lit pixels as a single braille glyph
#  in that colour.  Background pixels remain black (terminal default).
#
#  Result: effective resolution = col_w/2 chars wide × pixel_h/4 rows tall
#          (with the same number of terminal characters as before but
#           4× more pixel information encoded per row).

function _dominant_color(canvas, rows, cols, r0, r1, c0, c1)
    # tally non-zero pixels; return the most frequent colour
    counts = Dict{NTuple{3,UInt8}, Int}()
    @inbounds for r in r0:r1, c in c0:c1
        rv = canvas[r, c, 1]
        gv = canvas[r, c, 2]
        bv = canvas[r, c, 3]
        (rv == 0 && gv == 0 && bv == 0) && continue
        key = (rv, gv, bv)
        counts[key] = get(counts, key, 0) + 1
    end
    isempty(counts) && return nothing
    argmax(counts)
end

function _render_canvas(io::IO, canvas,
                        height::Int, col_w::Int, n_pos::Int,
                        max_ic::Float64)
    pixel_h  = size(canvas, 1)
    canvas_w = size(canvas, 2)

    # Number of braille character rows/cols
    br_rows = height          # each braille row = 4 pixel rows → pixel_h = 4*height
    br_cols = canvas_w ÷ 2   # each braille col = 2 pixel cols

    # y-axis: 3 evenly spaced labels – top, middle, bottom
    fmt_ic(v) = isinteger(v) ? string(Int(v)) : string(Int(round(v)))
    axis_labels = Dict{Int,String}()
    axis_labels[1]                  = lpad(fmt_ic(max_ic), 2)
    axis_labels[br_rows]            = lpad("0", 2)
    axis_labels[(1 + br_rows + 1) ÷ 2] = lpad(fmt_ic(max_ic / 2), 2)

    for br_r in 1:br_rows
        label = get(axis_labels, br_r, "  ")
        print(io, label, "│")

        # pixel rows covered by this braille row
        pr0 = (br_r - 1) * 4 + 1
        pr1 = min(br_r * 4, pixel_h)

        for br_c in 1:br_cols
            # pixel cols covered by this braille col
            pc0 = (br_c - 1) * 2 + 1
            pc1 = min(br_c * 2, canvas_w)

            color = _dominant_color(canvas, pixel_h, canvas_w, pr0, pr1, pc0, pc1)

            if color === nothing
                print(io, ' ')
                continue
            end

            # Build the braille bitmask
            mask = 0
            for sr in 0:3
                pr = pr0 + sr
                pr > pixel_h && continue
                for sc in 0:1
                    pc = pc0 + sc
                    pc > canvas_w && continue
                    if canvas[pr, pc, 1] != 0 || canvas[pr, pc, 2] != 0 || canvas[pr, pc, 3] != 0
                        mask |= 1 << BRAILLE_BIT[sr+1][sc+1]
                    end
                end
            end

            mask == 0 && (print(io, ' '); continue)

            r0c, g0c, b0c = Int(color[1]), Int(color[2]), Int(color[3])
            print(io, _fg(r0c, g0c, b0c), Char(0x2800 + mask), RESET)
        end
        println(io)
    end

    # x-axis – one label per position, spaced col_w/2 chars apart
    char_w = col_w ÷ 2
    print(io, "  └")
    for j in 1:n_pos
        s      = string(j)
        pad    = char_w - length(s)
        lpad_n = div(pad, 2)
        rpad_n = pad - lpad_n
        print(io, ' '^lpad_n, s, ' '^rpad_n)
    end
    println(io)
end

# ══════════════════════════════════════════════════════════════
#  Public API
# ══════════════════════════════════════════════════════════════

"""
    logoshow([io,] pfm; background, rna, height, col_width)

Render a sequence logo directly in the terminal using **braille
sub-pixel characters** for high resolution and **uniform solid
colours** (no anti-aliasing blending).

Each braille character encodes a 2 × 4 pixel block, giving
effectively twice the horizontal and four times the vertical
pixel density of ordinary text, while remaining fast (binary
rasterisation, O(pixels) with no supersampling).

# Arguments
- `pfm`       – 4 × L position-frequency matrix (rows = A/C/G/T).
- `background`– background frequencies (default: uniform 0.25).
- `rna`       – use A/C/G/U alphabet (default false).
- `height`    – terminal rows (default 20; pixel height = 4 × height).
- `col_width` – pixel columns per position, **must be even** (default 12).
"""
function logoshow end

function logoshow(io::IO, pfm::AbstractMatrix{<:Real};
                  background::Union{Nothing,AbstractVector{<:Real}} = nothing,
                  rna::Bool      = false,
                  height::Int    = 5,
                  col_width::Int = 10)

    col_width = col_width + (col_width & 1)  # ensure even

    letters = rna ? RNA_LETTERS : DNA_LETTERS
    colors  = rna ? RNA_COLORS  : DNA_COLORS
    n_chars = length(letters)
    n_pos   = size(pfm, 2)
    max_ic  = log2(n_chars)

    @assert size(pfm, 1) == n_chars "PFM must have $n_chars rows (got $(size(pfm,1)))"

    bg_freq = something(background, fill(1.0 / n_chars, n_chars))
    pixel_h = 4 * height          # braille rows encode 4 pixel rows each

    canvas = _build_canvas(pfm, letters, colors, bg_freq, pixel_h, col_width)
    _render_canvas(io, canvas, height, col_width, n_pos, Float64(max_ic))
    nothing
end

logoshow(pfm::AbstractMatrix{<:Real}; kw...) = logoshow(stdout, pfm; kw...)

# ══════════════════════════════════════════════════════════════
#  PWM wrapper – auto pretty-print in REPL
# ══════════════════════════════════════════════════════════════

"""
    PWM(pfm; rna=false, background=nothing)

Wraps a position-frequency matrix so that displaying it in the
REPL prints a colourful terminal sequence logo.
"""
struct PWM{T<:Real}
    pfm::Matrix{T}
    rna::Bool
    background::Union{Nothing,Vector{T}}
end

function PWM(pfm::AbstractMatrix{T}; rna::Bool = false,
             background::Union{Nothing,AbstractVector{<:Real}} = nothing) where T<:Real
    bg = isnothing(background) ? nothing : Vector{T}(background)
    PWM{T}(Matrix{T}(pfm), rna, bg)
end

function Base.show(io::IO, ::MIME"text/plain", w::PWM)
    printstyled(io, "PWM", bold=true)
    println(io, " (", size(w.pfm,1), "×", size(w.pfm,2), " ",
            w.rna ? "RNA" : "DNA", ")")
    logoshow(io, w.pfm; rna=w.rna, background=w.background)
end

Base.show(io::IO, w::PWM) =
    print(io, "PWM(", size(w.pfm,1), "×", size(w.pfm,2), ")")

end
