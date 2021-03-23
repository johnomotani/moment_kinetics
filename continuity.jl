module continuity

export continuity_equation!

using derivatives: derivative!
using velocity_moments: update_moments!

# use the continuity equation dn/dt + d(n*upar)/dz to update the density n for all species
function continuity_equation!(dens_out, fvec_in, moments, z, vpa, dt, spectral)
    # update the parallel flow velocity upar
    update_moments!(moments, fvec_in.pdf, vpa, z.n)
    # use the continuity equation dn/dt + d(n*upar)/dz to update the density n
    # for each species
    n_species = size(dens_out,2)
    for is ∈ 1:n_species
        @views continuity_equation_single_species!(dens_out[:,is],
            fvec_in.density[:,is], moments.upar[:,is], z, dt, spectral)
    end
end
# use the continuity equation dn/dt + d(n*upar)/dz to update the density n
function continuity_equation_single_species!(dens_out, dens_in, upar, z, dt, spectral)
    # calculate the particle flux nu
    @. z.scratch = dens_in*upar
    # calculate d(nu)/dz, averaging the derivative values at element boundaries
    derivative!(z.scratch, z.scratch, z, spectral)
    # update the density
    @. dens_out -= dt*z.scratch
end

end