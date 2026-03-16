using PWMPrettyPrint
using Documenter

DocMeta.setdocmeta!(PWMPrettyPrint, :DocTestSetup, :(using PWMPrettyPrint); recursive=true)

makedocs(;
    modules=[PWMPrettyPrint],
    authors="Shane Kuei-Hsien Chu (skchu@wustl.edu)",
    sitename="PWMPrettyPrint.jl",
    format=Documenter.HTML(;
        canonical="https://kchu25.github.io/PWMPrettyPrint.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/kchu25/PWMPrettyPrint.jl",
    devbranch="main",
)
