"""
Build the documentation as a pdf using LaTeX

Note this requires LuaTeX to be installed, e.g. on Ubuntu or Mint
```
sudo apt install texlive-luatex
```
It may also need the `texlive-latex-extra` [JTO: already had this installed, so haven't
tested without it].
"""

using Pkg

repo_dir = dirname(dirname(@__FILE__))
Pkg.develop([PackageSpec(path=joinpath(repo_dir, "moment_kinetics")),
             PackageSpec(path=joinpath(repo_dir, "makie_post_processing", "makie_post_processing")),
             PackageSpec(path=joinpath(repo_dir, "plots_post_processing", "plots_post_processing"))])
Pkg.instantiate()

using Documenter
using moment_kinetics

makedocs(
    sitename = "momentkinetics",
    format = Documenter.LaTeX(),
    modules = [moment_kinetics],
    authors = "M. Barnes, J.T. Omotani, M. Hardman",
    pages = ["moment_kinetic_equations.md"]
)
