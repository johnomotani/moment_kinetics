module em_fields

export setup_em_fields
export update_phi!

using ..type_definitions: mk_float
using ..array_allocation: allocate_float
using ..input_structs
using ..velocity_moments: update_density!

struct fields
    # phi is the electrostatic potential
    phi::Array{mk_float}
    # phi0 is the initial electrostatic potential
    phi0::Array{mk_float}
    # if including an external forcing for phi, it is of the form
    # phi_external = phi0*drive_amplitude*sinpi(t*drive_frequency)
    force_phi::Bool
    drive_amplitude::mk_float
    drive_frequency::mk_float
end

function setup_em_fields(m, force_phi, drive_amplitude, drive_frequency)
    phi = allocate_float(m)
    phi0 = allocate_float(m)
    return fields(phi, phi0, force_phi, drive_amplitude, drive_frequency)
end

# update_phi updates the electrostatic potential, phi
function update_phi!(fields, fvec, z, composition)
    n_ion_species = composition.n_ion_species
    @boundscheck size(fields.phi,1) == z.n || throw(BoundsError(fields.phi))
    @boundscheck size(fields.phi0,1) == z.n || throw(BoundsError(fields.phi0))
    @boundscheck size(fvec.density,1) == z.n || throw(BoundsError(fvec.density))
    @boundscheck size(fvec.density,2) == composition.n_species || throw(BoundsError(fvec.density))
    
    # first, calculate Sum_{i} Z_i n_i 
    z.scratch .= 0.0
    @inbounds for is ∈ 1:composition.n_ion_species
        for iz ∈ 1:z.n
            z.scratch[iz] += fvec.density[iz,is]
        end
    end
    
    if composition.electron_physics == boltzmann_electron_response
        N_e = 1.0
        #println("using boltzmann_electron_response")
        println(" N_e ", N_e)
    elseif composition.electron_physics == boltzmann_electron_response_with_simple_sheath
        #  calculate Sum_{i} Z_i n_i u_i = J_||i at z = 0 
        jpar_i = 0.0
        @inbounds for is ∈ 1:composition.n_ion_species
            jpar_i += fvec.density[1,is]*fvec.upar[1,is]
        end
        println("jpar_i", jpar_i)
        N_e = 2.0 * sqrt( pi * composition.me_over_mi) * jpar_i * exp( - composition.phi_wall)   
        #println("using boltzmann_electron_response_with_simple_sheath")
        println("N_e ", N_e)
    end
    
    
    if composition.electron_physics ∈ (boltzmann_electron_response, boltzmann_electron_response_with_simple_sheath)
        #z.scratch .= @view(fvec.density[:,1])
        #@inbounds for is ∈ 2:composition.n_ion_species
        #    for iz ∈ 1:z.n
        #        z.scratch[iz] += fvec.density[iz,is]
        #    end
        #end
        # calculate phi from 
        # Sum_{i} Z_i n_i = N_e exp[ e phi / T_e]
        @inbounds for iz ∈ 1:z.n
            fields.phi[iz] =  composition.T_e * log(z.scratch[iz]/ N_e )
        end
        # if fields.force_phi
        #     @inbounds for iz ∈ 1:z.n
        #         fields.phi[iz] += fields.phi0[iz]*fields.drive_amplitude*sin(t*fields.drive_frequency)
        #     end
        # end
    end
    
    ## can calculate phi at z = L and hence phi_wall(z=L) using jpar_i at z =L if needed
    
end

end
