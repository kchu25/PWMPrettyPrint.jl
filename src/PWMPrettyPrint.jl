module PWMPrettyPrint

export logoshow, PWM

# ══════════════════════════════════════════════════════════════
#  Glyph polygon data (from EntroPlots.jl / gglogo)
#  Each letter is a closed polygon in the unit square [0,1]².
# ══════════════════════════════════════════════════════════════

include("glyphs.jl")

# ══════════════════════════════════════════════════════════════
#  Information‑content helpers  (same maths as EntroPlots.jl)
# ══════════════════════════════════════════════════════════════

"""Per-letter information content for one column of a PFM."""
function ic_column(col, bg; ϵ=1e-20)
    return col .* log2.((col .+ ϵ) ./ bg)
end

"""Total information content of a column (sum of per-letter ICs)."""
function total_ic(col; bg=fill(0.25, length(col)))
    return sum(ic_column(col, bg))
end

# ══════════════════════════════════════════════════════════════
#  Default colour palettes  (RGB tuples for 24-bit ANSI)
# ══════════════════════════════════════════════════════════════

const DNA_COLORS = Dict(
    'A' => (6, 94, 42),     # dark green  (#065E2A)
    'C' => (14, 63, 115),   # dark blue   (#0E3F73)
    'G' => (194, 155, 37),  # gold/amber  (#C29B25)
    'T' => (143, 2, 2),     # dark red    (#8F0202)
)

const RNA_COLORS = Dict(
    'A' => (6, 94, 42),
    'C' => (14, 63, 115),
    'G' => (194, 155, 37),
    'U' => (161, 4, 31),    # (#A1041F)
)

const DNA_LETTERS = ['A', 'C', 'G', 'T']
const RNA_LETTERS = ['A', 'C', 'G', 'U']

# ══════════════════════════════════════════════════════════════
#  ANSI helpers
# ══════════════════════════════════════════════════════════════

_fg(r, g, b)      = "\e[38;2;$(r);$(g);$(b)m"
_bg(r, g, b)      = "\e[48;2;$(r);$(g);$(b)m"
const RESET        = "\e[0m"

# ══════════════════════════════════════════════════════════════
#  Polygon rasterizer
# ══════════════════════════════════════════════════════════════
#
# Given the polygon vertices (xs, ys) in [0,1]² and a target
# bitmap of size (rows, cols), fill every pixel whose centre
# falls inside the polygon.  Uses the classical ray-casting
# (even-odd) point-in-polygon test.

"""
    point_in_polygon(px, py, vx, vy)

Ray-casting even-odd test.  `vx`, `vy` are the polygon vertex
vectors (closed – first vertex == last vertex is fine but not
required).
"""
function point_in_polygon(px::Float64, py::Float64,
                          vx::Vector{Float64}, vy::Vector{Float64})
    n = length(vx)
    inside = false
    j = n
    @inbounds for i in 1:n
        yi, yj = vy[i], vy[j]
        xi, xj = vx[i], vx[j]
        if ((yi > py) != (yj > py)) &&
           (px < (xj - xi) * (py - yi) / (yj - yi) + xi)
            inside = !inside
        end
        j = i
    end
    return inside
end

"""
    rasterize_glyph(vx, vy, rows, cols) -> BitMatrix

Rasterize a polygon into a `rows × cols` bitmap.
Row 1 = top of glyph (y ≈ 1), row `rows` = bottom (y ≈ 0).
"""
function rasterize_glyph(vx::Vector{Float64}, vy::Vector{Float64},
                         rows::Int, cols::Int)
    bmp = falses(rows, cols)
    for r in 1:rows
        # centre of pixel row r  (row 1 = top → y near 1.0)
        py = 1.0 - (r - 0.5) / rows
        for c in 1:cols
            px = (c - 0.5) / cols
            if point_in_polygon(px, py, vx, vy)
                bmp[r, c] = true
            end
        end
    end
    return bmp
end

# Pre-rasterized glyph cache:  letter → (rows, cols) → BitMatrix
# We cache so repeated calls don't re-rasterize.
const _GLYPH_CACHE = Dict{Tuple{String, Int, Int}, BitMatrix}()

function get_glyph_bitmap(letter::String, rows::Int, cols::Int)
    key = (letter, rows, cols)
    get!(_GLYPH_CACHE, key) do
        glyph = get(GLYPHS, letter, nothing)
        if glyph === nothing
            return falses(rows, cols)
        end
        rasterize_glyph(Float64.(glyph.x), Float64.(glyph.y), rows, cols)
    end
end

# ══════════════════════════════════════════════════════════════
#  Compose a full logo into a pixel canvas
# ══════════════════════════════════════════════════════════════
#
# Canvas:  pixel_h  rows  ×  (col_width * n_pos)  columns
# Each cell stores an RGB tuple  (0,0,0) = transparent/background.

const BG_PIXEL = (0, 0, 0)

function _build_canvas(pfm, letters, colors, bg_freq,
                       pixel_h::Int, col_width::Int)
    n_chars = length(letters)
    n_pos   = size(pfm, 2)
    max_ic  = log2(n_chars)
    canvas_w = col_width * n_pos

    # canvas stores RGB per pixel; (0,0,0) = empty
    canvas = fill(BG_PIXEL, pixel_h, canvas_w)

    for j in 1:n_pos
        col = @view pfm[:, j]
        ics = ic_column(col, bg_freq)

        # sort by IC ascending → smallest at bottom, tallest on top
        order = sortperm(ics)

        # column x-range on canvas
        x0 = (j - 1) * col_width + 1
        x1 = j * col_width

        y_cursor = pixel_h  # bottom of canvas (row index)

        for idx in order
            ic_val = max(ics[idx], 0.0)
            frac   = ic_val / max_ic                # fraction of full height
            letter_h = round(Int, frac * pixel_h)   # pixel rows for this letter
            letter_h <= 0 && continue

            letter = string(letters[idx])
            rgb    = colors[letters[idx]]

            # rasterize glyph at (letter_h × col_width)
            bmp = get_glyph_bitmap(letter, letter_h, col_width)

            # paint onto canvas
            for lr in 1:letter_h
                cr = y_cursor - letter_h + lr   # canvas row
                cr < 1 && continue
                for lc in 1:col_width
                    if bmp[lr, lc]
                        canvas[cr, x0 + lc - 1] = rgb
                    end
                end
            end
            y_cursor -= letter_h
        end
    end

    return canvas
end

# ══════════════════════════════════════════════════════════════
#  Render canvas to terminal using half-block characters
# ══════════════════════════════════════════════════════════════
#
# Each printed row encodes TWO pixel rows using '▀':
#   foreground = top pixel colour
#   background = bottom pixel colour
# This doubles effective resolution.

function _render_canvas(io::IO, canvas::Matrix{NTuple{3,Int}},
                        height::Int, col_width::Int, n_pos::Int,
                        max_ic::Float64)
    pixel_h = size(canvas, 1)

    # y-axis labels
    axis_labels = Dict{Int,String}()
    axis_labels[1]      = lpad(string(round(max_ic; digits=1)), 4)
    axis_labels[height]  = lpad("0", 4)
    mid = div(height, 2) + 1
    axis_labels[mid]     = lpad(string(round(max_ic / 2; digits=1)), 4)

    canvas_w = size(canvas, 2)

    for row in 1:height
        # y-axis
        label = get(axis_labels, row, "    ")
        print(io, label, "│")

        top_r = 2 * row - 1
        bot_r = 2 * row

        for c in 1:canvas_w
            top_px = top_r <= pixel_h ? canvas[top_r, c] : BG_PIXEL
            bot_px = bot_r <= pixel_h ? canvas[bot_r, c] : BG_PIXEL

            if top_px == BG_PIXEL && bot_px == BG_PIXEL
                print(io, ' ')
            elseif top_px != BG_PIXEL && bot_px != BG_PIXEL
                # both filled: ▀ with fg=top, bg=bottom
                tr, tg, tb = top_px
                br, bg_, bb = bot_px
                print(io, _fg(tr, tg, tb), _bg(br, bg_, bb), '▀', RESET)
            elseif top_px != BG_PIXEL
                # only top filled
                tr, tg, tb = top_px
                print(io, _fg(tr, tg, tb), '▀', RESET)
            else
                # only bottom filled  → lower half block
                br, bg_, bb = bot_px
                print(io, _fg(br, bg_, bb), '▄', RESET)
            end
        end
        println(io)
    end

    # x-axis
    print(io, "    └")
    for j in 1:n_pos
        s = string(j)
        pad = col_width - length(s)
        pad_l = div(pad, 2)
        pad_r = pad - pad_l
        print(io, ' '^pad_l, s, ' '^pad_r)
    end
    println(io)
end

# ══════════════════════════════════════════════════════════════
#  Public API
# ══════════════════════════════════════════════════════════════

"""
    logoshow([io::IO,] pfm; kwargs...)

Print a colourful sequence logo of the position-frequency matrix
`pfm` directly in the terminal, using **glyph-shaped** letters
rendered with Unicode half-block characters.

# Arguments
- `pfm`: Matrix where **rows = nucleotides** and **columns = positions**.
  Each column should sum to ≈ 1.
- `background`: Background frequencies (default: uniform 0.25 each).
- `rna::Bool`: Use RNA alphabet (A C G U) instead of DNA (A C G T).
- `height::Int`: Logo height in **terminal rows** (default 20).
  Effective vertical resolution is `2 × height` pixels thanks to
  half-block rendering.
- `col_width::Int`: Pixel columns per position (default 8).

# Example
```julia
pfm = [0.7 0.1 0.1 0.5;
       0.1 0.8 0.1 0.2;
       0.1 0.05 0.7 0.2;
       0.1 0.05 0.1 0.1]
logoshow(pfm)
```
"""
function logoshow end

function logoshow(io::IO, pfm::AbstractMatrix{<:Real};
                  background::Union{Nothing,AbstractVector{<:Real}}=nothing,
                  rna::Bool=false,
                  height::Int=20,
                  col_width::Int=8)

    letters = rna ? RNA_LETTERS : DNA_LETTERS
    colors  = rna ? RNA_COLORS  : DNA_COLORS
    n_chars = length(letters)
    n_pos   = size(pfm, 2)
    max_ic  = log2(n_chars)

    @assert size(pfm, 1) == n_chars "PFM must have $(n_chars) rows (got $(size(pfm,1)))"

    bg_freq = something(background, fill(1.0 / n_chars, n_chars))

    # effective pixel height = 2 × terminal rows
    pixel_h = 2 * height

    canvas = _build_canvas(pfm, letters, colors, bg_freq, pixel_h, col_width)
    _render_canvas(io, canvas, height, col_width, n_pos, Float64(max_ic))

    return nothing
end

# Convenience: print to stdout
function logoshow(pfm::AbstractMatrix{<:Real}; kwargs...)
    logoshow(stdout, pfm; kwargs...)
end

# ══════════════════════════════════════════════════════════════
#  PWM wrapper for automatic pretty-printing
# ══════════════════════════════════════════════════════════════

"""
    PWM(pfm; rna=false, background=nothing)

Lightweight wrapper so that `display(PWM(pfm))` shows a colourful
terminal sequence logo.
"""
struct PWM{T<:Real}
    pfm::Matrix{T}
    rna::Bool
    background::Union{Nothing, Vector{T}}
end

function PWM(pfm::AbstractMatrix{T}; rna::Bool=false,
             background::Union{Nothing,AbstractVector{<:Real}}=nothing) where T<:Real
    bg = isnothing(background) ? nothing : Vector{T}(background)
    return PWM{T}(Matrix{T}(pfm), rna, bg)
end

function Base.show(io::IO, ::MIME"text/plain", w::PWM)
    printstyled(io, "PWM ", bold=true)
    println(io, "(", size(w.pfm, 1), "×", size(w.pfm, 2), " ",
            w.rna ? "RNA" : "DNA", ")")
    logoshow(io, w.pfm; rna=w.rna, background=w.background)
end

function Base.show(io::IO, w::PWM)
    print(io, "PWM(", size(w.pfm, 1), "×", size(w.pfm, 2), ")")
end

end
