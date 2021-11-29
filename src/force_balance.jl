module force_balance

export force_balance!

using ..calculus: derivative!

# use the force balance equation d(nu)/dt + d(ppar + n*upar*upar)/dz =
# -(dens/2)*dphi/dz + R*dens_i*dens_n*(upar_n-upar_i)
# to update the parallel particle flux dens*upar for each species
function force_balance!(pflx, fvec, fields, collisions, vpa, z, dt, spectral, composition)
    # account for momentum flux contribution to force balance
    for is ∈ composition.species_local_range
        if composition.first_proc_in_group
            @views force_balance_flux_species!(pflx[:,is], fvec.density[:,is], fvec.upar[:,is], fvec.ppar[:,is], z, dt, spectral)
            if is ∈ composition.ion_species_range
                # account for parallel electric field contribution to force balance
                @views force_balance_Epar_species!(pflx[:,is], fields.phi, fvec.density[:,is], z, dt, spectral)
            end
        end
    end
    # if neutrals present and charge exchange frequency non-zero,
    # account for collisional friction between ions and neutrals
    if composition.n_neutral_species > 0 && abs(collisions.charge_exchange) > 0.0
        force_balance_CX!(pflx, fvec.density, fvec.upar, collisions.charge_exchange, composition, z, dt)
    end
end

# use the force balance equation d(mnu)/dt + d(ppar + mnu * u)/dz = ...
# to update the momentum flux mnu; this function accounts for the contribution from the
# flux term above
function force_balance_flux_species!(pflx, dens, upar, ppar, z, dt, spectral)
    # calculate the parallel flux of parallel momentum densitg at the previous time level/RK stage
    @. z.scratch = ppar + dens*upar^2
    # calculate d(nu)/dz, averaging the derivative values at element boundaries
    derivative!(z.scratch, z.scratch, z, spectral)
    # update the parallel momentum density to account for the parallel flux of parallel momentum
    @. pflx = dens*upar - dt*z.scratch
end
# use the force balance equation d(mnu)/dt + ... = -n*Epar + ...
# to update mnu; this function accounts for the contribution from the Epar term
function force_balance_Epar_species!(pflx, phi, dens, z, dt, spectral)
    # calculate the (negative of the) parallel electric field.
    # Done like this because passing in -phi would require a temporary buffer to be allocated.
    # So z.scratch = -Epar
    derivative!(z.scratch, phi, z, spectral)
    # update the parallel momentum density to account for the force from the parallel electric field
    #  pflx += 0.5*dt*Epar*dens
    #  => pflx -= 0.5*dt*(-Epar)*dens
    @. pflx -= 0.5*dt*z.scratch*dens
end

function force_balance_CX!(pflx, dens, upar, CX_frequency, composition, z, dt)
    for is ∈ composition.species_local_range
        if composition.first_proc_in_group
            # include contribution to ion acceleration due to collisional friction with neutrals
            if is ∈ composition.ion_species_range
                for isp ∈ composition.neutral_species_range
                    @views @. pflx[:,is] += dt*CX_frequency*dens[:,is]*dens[:,isp]*(upar[:,isp]-upar[:,is])
                end
            end
            # include contribution to neutral acceleration due to collisional friction with ions
            if is ∈ composition.neutral_species_range
                for isp ∈ composition.ion_species_range
                    @views @. pflx[:,is] += dt*CX_frequency*dens[:,is]*dens[:,isp]*(upar[:,isp]-upar[:,is])
                end
            end
        end
    end
end

end
