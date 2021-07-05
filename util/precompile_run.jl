# provide option of running from command line via 'julia moment_kinetics.jl'
using Pkg
Pkg.activate(".")

using TimerOutputs
using moment_kinetics

input_dict = Dict("nstep"=>1, "run_name"=>"precompilation")

to = TimerOutput()
run_moment_kinetics(to, input_dict)

rm("runs/precompilation/", recursive=true)