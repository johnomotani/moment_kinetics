module force_balance

export force_balance!

using ..calculus: derivative!

# use the force balance equation d(nu)/dt + d(ppar + n*upar*upar)/dz =
# -(dens/2)*dphi/dz + R*dens_i*dens_n*(upar_n-upar_i) + Rion*dens_i*dens_n*upar_n
# to update the parallel particle flux dens*upar for each species
function force_balance!(pflx, fvec, fields, collisions, vpa, z, dt, spectral, composition)
    # account for momentum flux contribution to force balance
    for is ∈ 1:composition.n_species
        @views force_balance_flux_species!(pflx[:,is], fvec.density[:,is], fvec.upar[:,is], fvec.ppar[:,is], z, dt, spectral)
    end
    # account for parallel electric field contribution to force balance
    for is ∈ 1:composition.n_ion_species
        @views force_balance_Epar_species!(pflx[:,is], fields.phi, fvec.density[:,is], z, dt, spectral)
    end
    # if neutrals present account for charge exchange and/or ionizatiion collisions
    if composition.n_neutral_species > 0
        # account for collisional friction between ions and neutrals
        if abs(collisions.charge_exchange) > 0.0
            force_balance_CX!(pflx, fvec.density, fvec.upar, collisions.charge_exchange, composition, z.n, dt)
        end
        # account for ionization collisions
        if abs(collisions.ionization) > 0.0
            force_balance_ionization!(pflx, fvec.density, fvec.upar, collisions.ionization,
                                      composition, z.n, dt)
        end
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
    # calculate the parallel electric field
    derivative!(z.scratch, -phi, z, spectral)
    # update the parallel momentum density to account for the force from the parallel electric field
    @. pflx += 0.5*dt*z.scratch*dens
end

function force_balance_CX!(pflx, dens, upar, CX_frequency, composition, nz, dt)
    # include contribution to ion acceleration due to collisional friction with neutrals
    for is ∈ 1:composition.n_ion_species
        for isp ∈ composition.n_ion_species+1:composition.n_species
            # get the absolute species index for the neutral species
            for iz ∈ 1:nz
                pflx[iz,is] += dt*CX_frequency*dens[iz,is]*dens[iz,isp]*(upar[iz,isp]-upar[iz,is])
            end
        end
    end
    # include contribution to neutral acceleration due to collisional friction with ions
    for isp ∈ composition.n_ion_species+1:composition.n_species
        for is ∈ 1:composition.n_ion_species
            # get the absolute species index for the neutral species
            for iz ∈ 1:nz
                pflx[iz,isp] += dt*CX_frequency*dens[iz,isp]*dens[iz,is]*(upar[iz,is]-upar[iz,isp])
            end
        end
    end
end

function force_balance_ionization!(pflx, dens, upar, ionization_frequency, composition, nz, dt)
    # include contribution to ion acceleration due to ionization of neutrals
    for is ∈ 1:composition.n_ion_species
        for isp ∈ composition.n_ion_species+1:composition.n_species
            # get the absolute species index for the neutral species
            for iz ∈ 1:nz
                pflx[iz,is] += dt*ionization_frequency*dens[iz,is]*dens[iz,isp]*upar[iz,isp]
            end
        end
    end
    # include contribution to neutral acceleration due to ionizaton
    for isp ∈ composition.n_ion_species+1:composition.n_species
        for is ∈ 1:composition.n_ion_species
            # get the absolute species index for the neutral species
            for iz ∈ 1:nz
                pflx[iz,isp] -= dt*ionization_frequency*dens[iz,isp]*dens[iz,is]*upar[iz,isp]
            end
        end
    end
end

end
