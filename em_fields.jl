module em_fields

export setup_em_fields
export update_phi!

using type_definitions: mk_float
using array_allocation: allocate_float
using velocity_moments: update_density!

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
function update_phi!(fields, moments, fvec, vpa, nz, composition, t)
    n_ion_species = composition.n_ion_species
    @boundscheck size(fields.phi,1) == nz || throw(BoundsError(fields.phi))
    @boundscheck size(fields.phi0,1) == nz || throw(BoundsError(fields.phi0))
    @boundscheck size(moments.dens,1) == nz || throw(BoundsError(moments.dens))
    @boundscheck size(moments.dens,2) == composition.n_species || throw(BoundsError(moments.dens))
    if composition.boltzmann_electron_response
        if moments.evolve_density
            dens = fvec.density
        else
            for is ∈ 1:composition.n_ion_species
                if moments.dens_updated[is] == false
                    @views update_density!(moments.dens[:,is], vpa.scratch, fvec.pdf[:,:,is], vpa, nz)
                    moments.dens_updated[is] = true
                end
            end
            dens = moments.dens
        end
        @inbounds for iz ∈ 1:nz
            total_density = 0.0
            for is ∈ 1:composition.n_ion_species
                #total_density += moments.dens[iz,is]
                total_density += dens[iz,is]
            end
            fields.phi[iz] = composition.T_e * log(total_density)
        end
        if fields.force_phi
            @inbounds for iz ∈ 1:nz
                fields.phi[iz] += fields.phi0[iz]*fields.drive_amplitude*sin(t*fields.drive_frequency)
            end
        end
    end
end

end
