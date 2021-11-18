module WallBCDebug

# Regression test using wall boundary conditions. Runs to steady state and then
# checks phi profile against saved reference output.

include("setup.jl")

# Create a temporary directory for test output
test_output_directory = tempname()
mkpath(test_output_directory)

# default inputs for tests
test_input_finite_difference = Dict("n_ion_species" => 1,
                                    "n_neutral_species" => 1,
                                    "boltzmann_electron_response" => true,
                                    "run_name" => "finite_difference",
                                    "base_directory" => test_output_directory,
                                    "evolve_moments_density" => false,
                                    "evolve_moments_parallel_flow" => false,
                                    "evolve_moments_parallel_pressure" => false,
                                    "evolve_moments_conservation" => false,
                                    "T_e" => 1.0,
                                    "T_wall" => 1.0,
                                    "initial_density1" => 1.0,
                                    "initial_temperature1" => 1.0,
                                    "z_IC_option1" => "gaussian",
                                    "z_IC_density_amplitude1" => 0.001,
                                    "z_IC_density_phase1" => 0.0,
                                    "z_IC_upar_amplitude1" => 0.0,
                                    "z_IC_upar_phase1" => 0.0,
                                    "z_IC_temperature_amplitude1" => 0.0,
                                    "z_IC_temperature_phase1" => 0.0,
                                    "vpa_IC_option1" => "gaussian",
                                    "vpa_IC_density_amplitude1" => 1.0,
                                    "vpa_IC_density_phase1" => 0.0,
                                    "vpa_IC_upar_amplitude1" => 0.0,
                                    "vpa_IC_upar_phase1" => 0.0,
                                    "vpa_IC_temperature_amplitude1" => 0.0,
                                    "vpa_IC_temperature_phase1" => 0.0,
                                    "initial_density2" => 1.0,
                                    "initial_temperature2" => 1.0,
                                    "z_IC_option2" => "gaussian",
                                    "z_IC_density_amplitude2" => 0.001,
                                    "z_IC_density_phase2" => 0.0,
                                    "z_IC_upar_amplitude2" => 0.0,
                                    "z_IC_upar_phase2" => 0.0,
                                    "z_IC_temperature_amplitude2" => 0.0,
                                    "z_IC_temperature_phase2" => 0.0,
                                    "vpa_IC_option2" => "gaussian",
                                    "vpa_IC_density_amplitude2" => 1.0,
                                    "vpa_IC_density_phase2" => 0.0,
                                    "vpa_IC_upar_amplitude2" => 0.0,
                                    "vpa_IC_upar_phase2" => 0.0,
                                    "vpa_IC_temperature_amplitude2" => 0.0,
                                    "vpa_IC_temperature_phase2" => 0.0,
                                    "charge_exchange_frequency" => 2.0,
                                    "ionization_frequency" => 2.0,
                                    "constant_ionization_rate" => false,
                                    "nstep" => 3,
                                    "dt" => 0.001,
                                    "nwrite" => 2,
                                    "use_semi_lagrange" => false,
                                    "n_rk_stages" => 4,
                                    "split_operators" => false,
                                    "z_ngrid" => 8,
                                    "z_nelement" => 1,
                                    "z_bc" => "wall",
                                    "z_discretization" => "finite_difference",
                                    "vpa_ngrid" => 8,
                                    "vpa_nelement" => 1,
                                    "vpa_L" => 8.0,
                                    "vpa_bc" => "periodic",
                                    "vpa_discretization" => "finite_difference")

test_input_chebyshev = merge(test_input_finite_difference,
                             Dict("run_name" => "chebyshev_pseudospectral",
                                  "z_discretization" => "chebyshev_pseudospectral",
                                  "z_ngrid" => 3,
                                  "z_nelement" => 2,
                                  "vpa_discretization" => "chebyshev_pseudospectral",
                                  "vpa_ngrid" => 3,
                                  "vpa_nelement" => 2))

"""
Run a test for a single set of parameters
"""
# Note 'name' should not be shared by any two tests in this file
function run_test(test_input; args...)
    # by passing keyword arguments to run_test, args becomes a Dict which can be used to
    # update the default inputs

    # Convert keyword arguments to a unique name
    name = test_input["run_name"]
    if length(args) > 0
        name = string(name, "_", (string(k, "-", v, "_") for (k, v) in args)...)

        # Remove trailing "_"
        name = chop(name)
    end

    # Provide some progress info
    println("    - bug-checking ", name)

    # Convert dict from symbol keys to String keys
    modified_inputs = Dict(String(k) => v for (k, v) in args)

    # Update default inputs with values to be changed
    input = merge(test_input, modified_inputs)

    input["run_name"] = name

    # run simulation
    run_moment_kinetics(input)
end

function runtests()

    @testset "Wall boundary conditions" begin
        println("Wall boundary condition tests")

        #@testset "finite difference" begin
        #    run_test(test_input_finite_difference)
        #end

        @testset "Chebyshev" begin
            run_test(test_input_chebyshev)
        end
    end
end

end # WallBCDebug


using .WallBCDebug

WallBCDebug.runtests()